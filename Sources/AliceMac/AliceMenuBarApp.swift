import AliceCore
import SwiftUI

@main
struct AliceMenuBarApp: App {
    @StateObject private var viewModel = AliceMenuBarViewModel()

    var body: some Scene {
        MenuBarExtra("Alice", systemImage: "text.book.closed") {
            ContentView(viewModel: viewModel)
                .frame(width: 420, height: 480)
        }
        .menuBarExtraStyle(.window)

        Settings {
            ShortcutSettingsView(viewModel: viewModel)
                .frame(minWidth: 680, minHeight: 500)
                .padding(16)
        }
    }
}
