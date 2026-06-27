import Foundation

struct AppleIntelligenceProvider: LLMProvider {
    let name = "Apple Intelligence"

    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken> {
        AsyncStream { continuation in
            Task {
                let prompt = messages.last?.content ?? ""

                let responses = generateLocalResponse(for: prompt)
                for response in responses {
                    continuation.yield(.delta(response))
                    try? await Task.sleep(for: .milliseconds(30))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private func generateLocalResponse(for prompt: String) -> [String] {
        let words = [
            "Это", "заглушка", "локальной", "LLM-модели.", 
            "В", "реальном", "приложении", "здесь", "будет", 
            "интеграция", "с", "Apple Intelligence", "или", 
            "Core ML", "моделью.", "Архитектура", "готова", 
            "к", "подключению", "любого", "провайдера."
        ]
        return words.map { $0 + " " }
    }
}
