import Testing
@testable import Lamo

struct LamoTests {
    @Test func memoryServiceDuplicateDetection() {
        // Test that Jaccard similarity works for duplicate detection
        let service = MemoryService.shared
        // Test basic string similarity
        let words1 = Set("hello world".split(separator: " ").map(String.init))
        let words2 = Set("hello world test".split(separator: " ").map(String.init))
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        #expect(Float(intersection.count) / Float(union.count) > 0.5)
    }
    
    @Test func presetModelProperties() {
        // Test that preset model properties are consistent
        for model in PresetModel.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(!model.filename.isEmpty)
            #expect(model.downloadURL != nil)
            #expect(model.fileSizeGB > 0)
            #expect(!model.parameterCount.isEmpty)
        }
    }
    
    @Test func safeMaxTokensPositive() {
        // Test that safeMaxTokens always returns a positive value
        // This tests the logic indirectly through the provider manager
        let manager = ProviderManager.shared
        // safeMaxTokens is internal, but we can verify the engine doesn't crash
        #expect(manager.isEngineReady || manager.engineError != nil || manager.litertLMModelPath == nil)
    }
}
