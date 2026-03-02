// Track 2: TIRAnalysisProvider protocol — data fetch + engine entry point.
// Track 5 will add Screen registration and View routing.

enum TIRAnalysis {
    enum Config {}
}

protocol TIRAnalysisProvider: Provider {
    /// Fetches glucose + carbs from HealthKit, pump history from file storage,
    /// runs TIRAnalysisEngine.analyze(_:), and returns the classified event list
    /// together with window coverage metadata.
    func runAnalysis(windowDays: Int) async -> TIRAnalysisResult
}
