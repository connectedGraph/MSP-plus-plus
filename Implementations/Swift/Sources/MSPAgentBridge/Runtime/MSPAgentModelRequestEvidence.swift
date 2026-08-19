import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

struct MSPAgentModelRequestEvidence: Sendable {
    var runID: String
    var sequence: Int
    var model: String
    var inputCount: Int
    var userInputHashes: [String]
    var toolCount: Int
    var stream: String

    init(runID: String, sequence: Int, request: MSPAgentRequestEnvelope) {
        self.runID = runID
        self.sequence = sequence
        self.model = request.payload["model"]?.stringValue ?? ""
        self.inputCount = request.input.count
        self.userInputHashes = Self.requestUserInputTexts(request)
            .map(Self.sha256Hex)
        self.toolCount = request.payload["tools"]?.arrayValue?.count ?? 0
        self.stream = Self.stringField(request.payload["stream"])
    }

    var requestFields: [String: String] {
        commonFields.merging([
            "request_layer": "runtime_provider",
            "request_run_id": runID,
            "request_sequence": "\(sequence)",
            "model": model,
            "input_count": "\(inputCount)",
            "tool_count": "\(toolCount)",
            "stream": stream
        ]) { _, new in new }
    }

    var responseFields: [String: String] {
        commonFields.merging([
            "model_request_layer": "runtime_provider",
            "model_request_run_id": runID,
            "model_request_sequence": "\(sequence)",
            "model_request_model": model
        ]) { _, new in new }
    }

    private var commonFields: [String: String] {
        [
            "request_user_input_count": "\(userInputHashes.count)",
            "request_user_input_hash_algorithm": "sha256-utf8",
            "request_user_input_sha256s": userInputHashes.joined(separator: ","),
            "request_last_user_input_sha256": userInputHashes.last ?? ""
        ]
    }

    private static func requestUserInputTexts(_ request: MSPAgentRequestEnvelope) -> [String] {
        request.input
            .compactMap(\.objectValue)
            .filter { $0["type"]?.stringValue == "message" && $0["role"]?.stringValue == "user" }
            .map { message in
                (message["content"]?.arrayValue ?? [])
                    .compactMap(\.objectValue)
                    .filter { $0["type"]?.stringValue == "input_text" }
                    .compactMap { $0["text"]?.stringValue }
                    .joined(separator: "\n")
            }
    }

    private static func stringField(_ value: MSPAgentJSONValue?) -> String {
        switch value {
        case .string(let string):
            return string
        case .bool(let bool):
            return "\(bool)"
        case .number(let number):
            return "\(number)"
        case .object, .array, .null, nil:
            return ""
        }
    }

    static func sha256Hex(_ text: String) -> String {
        let data = Data(text.utf8)
        #if canImport(CryptoKit)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        #else
        return MSPAgentSHA256.digest(data)
            .map { String(format: "%02x", $0) }
            .joined()
        #endif
    }
}
