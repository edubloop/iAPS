import SwiftUI
import Swinject

extension TIRAnalysis {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            NavigationView {
                TIRSummaryView(state: state)
                    .navigationTitle("TIR Insights")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close", action: state.hideModal)
                        }
                    }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}
