import Foundation

enum L {
    static var chinese: Bool {
        let selection = UserDefaults.standard.string(forKey:"language") ?? "system"
        return selection == "zh" || (selection == "system" && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
    }
    static func t(_ english: String, _ chinese: String) -> String { self.chinese ? chinese : english }
}

import SwiftUI
// Explicit wrapper alias also supports SDKs that introduce an @State macro.
typealias ViewState<Value> = SwiftUI.State<Value>
