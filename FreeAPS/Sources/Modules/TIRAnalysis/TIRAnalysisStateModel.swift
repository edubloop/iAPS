import Foundation
import SwiftUI
import Swinject

// Track 1 stub.
// Track 2 will add @Published properties for engine results and Combine subscriptions.
// Track 4 will add @Published properties for UI binding.
extension TIRAnalysis {
    final class StateModel: BaseStateModel<Provider> {
        override func subscribe() {}
    }
}
