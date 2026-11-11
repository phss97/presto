import Foundation
import llama

public enum LlamaCppError: LocalizedError, Sendable {
    case modelLoadFailed(String)
    case contextInitFailed
    case tokenizationFailed
    case decodeFailed(Int32)
    case emptyGeneration

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load local GGUF model at \((path as NSString).lastPathComponent)."
        case .contextInitFailed:
            return "Failed to initialize Metal inference context."
        case .tokenizationFailed:
            return "Failed to tokenize input text."
        case .decodeFailed(let code):
            return "Local LLM decode failed (code \(code))."
        case .emptyGeneration:
            return "Local LLM returned an empty translation."
        }
    }
}

private let llamaSilentLogCallback: ggml_log_callback = { _, _, _ in }

public actor LlamaCppBackend {
    public static let shared = LlamaCppBackend()

    private var didInitBackend = false
    private var loadedModelPath: String?
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var idleUnloadTask: Task<Void, Never>?

    private let idleTimeoutSeconds: Double = 300

    private init() {}

    public func unload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        loadedModelPath = nil
    }

    public func isModelLoaded() -> Bool {
        model != nil && context != nil
    }

    public func translate(
        text: String,
        to targetLanguage: Language,
        modelURL: URL,
        onLoadingModel: (@Sendable () -> Void)? = nil
    ) async throws -> String {
        idleUnloadTask?.cancel()
        defer {
            scheduleIdleUnload()
        }

        ensureBackendInitialized()

        if loadedModelPath != modelURL.path || model == nil || context == nil {
            onLoadingModel?()
            try loadModel(at: modelURL.path)
        }

        guard let model, let context else {
            throw LlamaCppError.contextInitFailed
        }

        guard let vocab = llama_model_get_vocab(model) else {
            throw LlamaCppError.contextInitFailed
        }

        if let memory = llama_get_memory(context) {
            llama_memory_clear(memory, true)
        }

        let systemPrompt = TranslationPromptBuilder.systemInstructions(for: targetLanguage)
        let userPrompt = TranslationPromptBuilder.userPrompt(for: text, targetLanguage: targetLanguage)
        let formattedPrompt = formatChatPrompt(model: model, system: systemPrompt, user: userPrompt)

        let promptTokens = try tokenize(text: formattedPrompt, vocab: vocab, addSpecial: true, parseSpecial: true)
        guard !promptTokens.isEmpty else {
            throw LlamaCppError.tokenizationFailed
        }

        let contextLimit = Int(llama_n_ctx(context))
        let maxBatch = 512
        var batch = llama_batch_init(Int32(maxBatch), 0, 1)
        defer {
            llama_batch_free(batch)
        }

        // Evaluate prompt in batches
        var offset = 0
        while offset < promptTokens.count {
            let chunkCount = min(maxBatch, promptTokens.count - offset)
            batch.n_tokens = Int32(chunkCount)
            for i in 0..<chunkCount {
                let pos = offset + i
                batch.token[i] = promptTokens[pos]
                batch.pos[i] = Int32(pos)
                batch.n_seq_id[i] = 1
                batch.seq_id[i]![0] = 0
                batch.logits[i] = (pos == promptTokens.count - 1) ? 1 : 0
            }

            let status = llama_decode(context, batch)
            if status != 0 {
                throw LlamaCppError.decodeFailed(status)
            }
            offset += chunkCount
        }

        let samplerParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerParams) else {
            throw LlamaCppError.contextInitFailed
        }
        defer {
            llama_sampler_free(sampler)
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        let maxGeneratedTokens = min(
            max(256, promptTokens.count * 3),
            max(256, contextLimit - promptTokens.count - 16)
        )

        var currentPos = Int32(promptTokens.count)
        var utf8Bytes: [UInt8] = []
        utf8Bytes.reserveCapacity(text.utf8.count * 2)
        var pieceBuffer = [CChar](repeating: 0, count: 256)

        for _ in 0..<maxGeneratedTokens {
            try Task.checkCancellation()

            let nextToken = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, nextToken) {
                break
            }

            let pieceLen = llama_token_to_piece(
                vocab,
                nextToken,
                &pieceBuffer,
                Int32(pieceBuffer.count),
                0,
                false
            )
            if pieceLen > 0 {
                for idx in 0..<Int(pieceLen) {
                    utf8Bytes.append(UInt8(bitPattern: pieceBuffer[idx]))
                }
            } else if pieceLen < 0 {
                var largeBuffer = [CChar](repeating: 0, count: Int(-pieceLen) + 8)
                let retryLen = llama_token_to_piece(
                    vocab,
                    nextToken,
                    &largeBuffer,
                    Int32(largeBuffer.count),
                    0,
                    false
                )
                if retryLen > 0 {
                    for idx in 0..<Int(retryLen) {
                        utf8Bytes.append(UInt8(bitPattern: largeBuffer[idx]))
                    }
                }
            }

            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = currentPos
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            currentPos += 1

            let decodeStatus = llama_decode(context, batch)
            if decodeStatus != 0 {
                throw LlamaCppError.decodeFailed(decodeStatus)
            }
        }

        let rawOutput = String(decoding: utf8Bytes, as: UTF8.self)
        let cleaned = TranslationPromptBuilder.cleanOutput(rawOutput, originalSource: text)
        guard !cleaned.isEmpty else {
            throw LlamaCppError.emptyGeneration
        }
        return cleaned
    }

    private func ensureBackendInitialized() {
        guard !didInitBackend else { return }
        llama_log_set(llamaSilentLogCallback, nil)
        llama_backend_init()
        didInitBackend = true
    }

    private func loadModel(at path: String) throws {
        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        loadedModelPath = nil

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = -1 // Offload all layers to Metal GPU

        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw LlamaCppError.modelLoadFailed(path)
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 4096
        ctxParams.n_batch = 512
        ctxParams.n_ubatch = 512
        let cpuCores = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 1))
        ctxParams.n_threads = Int32(cpuCores)
        ctxParams.n_threads_batch = Int32(cpuCores)

        guard let loadedContext = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            throw LlamaCppError.contextInitFailed
        }

        self.model = loadedModel
        self.context = loadedContext
        self.loadedModelPath = path
    }

    private func formatChatPrompt(model: OpaquePointer, system: String, user: String) -> String {
        let templatePtr = llama_model_chat_template(model, nil)
        let systemRole = "system"
        let userRole = "user"

        return systemRole.withCString { sysRoleCStr in
            userRole.withCString { userRoleCStr in
                system.withCString { sysCStr in
                    user.withCString { userCStr in
                        let messages = [
                            llama_chat_message(role: sysRoleCStr, content: sysCStr),
                            llama_chat_message(role: userRoleCStr, content: userCStr)
                        ]

                        let initialCapacity = max(512, (system.utf8.count + user.utf8.count) * 2 + 128)
                        var buffer = [CChar](repeating: 0, count: initialCapacity)

                        let written = messages.withUnsafeBufferPointer { msgBuf in
                            llama_chat_apply_template(
                                templatePtr,
                                msgBuf.baseAddress,
                                msgBuf.count,
                                true,
                                &buffer,
                                Int32(buffer.count)
                            )
                        }

                        if written > Int32(buffer.count) {
                            var resized = [CChar](repeating: 0, count: Int(written) + 16)
                            let retryWritten = messages.withUnsafeBufferPointer { msgBuf in
                                llama_chat_apply_template(
                                    templatePtr,
                                    msgBuf.baseAddress,
                                    msgBuf.count,
                                    true,
                                    &resized,
                                    Int32(resized.count)
                                )
                            }
                            if retryWritten > 0 {
                                let bytes = resized.prefix(Int(retryWritten)).map { UInt8(bitPattern: $0) }
                                return String(decoding: bytes, as: UTF8.self)
                            }
                        } else if written > 0 {
                            let bytes = buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }
                            return String(decoding: bytes, as: UTF8.self)
                        }

                        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
                    }
                }
            }
        }
    }

    private func tokenize(
        text: String,
        vocab: OpaquePointer,
        addSpecial: Bool,
        parseSpecial: Bool
    ) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        var capacity = max(32, utf8Count + 16)
        var tokens = [llama_token](repeating: 0, count: capacity)

        let count = text.withCString { cStr in
            llama_tokenize(
                vocab,
                cStr,
                Int32(utf8Count),
                &tokens,
                Int32(capacity),
                addSpecial,
                parseSpecial
            )
        }

        if count < 0 {
            capacity = Int(-count) + 8
            tokens = [llama_token](repeating: 0, count: capacity)
            let retryCount = text.withCString { cStr in
                llama_tokenize(
                    vocab,
                    cStr,
                    Int32(utf8Count),
                    &tokens,
                    Int32(capacity),
                    addSpecial,
                    parseSpecial
                )
            }
            guard retryCount >= 0 else {
                throw LlamaCppError.tokenizationFailed
            }
            return Array(tokens.prefix(Int(retryCount)))
        }

        return Array(tokens.prefix(Int(count)))
    }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        let timeout = idleTimeoutSeconds
        idleUnloadTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self.unload()
        }
    }
}
