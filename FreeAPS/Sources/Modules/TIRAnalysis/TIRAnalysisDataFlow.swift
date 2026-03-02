enum TIRAnalysis {
    enum Config {}
}

protocol TIRAnalysisProvider: Provider {
    /// Fetches glucose + carbs from selected source (Nightscout or HealthKit), pump history from file storage,
    /// runs TIRAnalysisEngine.analyze(_:), and returns the classified event list
    /// together with window coverage metadata.
    func runAnalysis(windowDays: Int) async -> TIRAnalysisResult
}
