import SwiftUI

@main
struct CountLogApp: App {
    @StateObject private var repository: RecordsRepository
    @StateObject private var settings: WebDAVSettings
    @StateObject private var uploader: WebDAVUploader

    init() {
        let repository = RecordsRepository()
        let settings = WebDAVSettings()
        _repository = StateObject(wrappedValue: repository)
        _settings = StateObject(wrappedValue: settings)
        _uploader = StateObject(wrappedValue: WebDAVUploader(repository: repository, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                CountFlowView()
                    .tabItem { Label("撮影", systemImage: "camera.viewfinder") }
                HistoryView()
                    .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
                GuideView()
                    .tabItem { Label("ガイド", systemImage: "book") }
                SettingsView()
                    .tabItem { Label("設定", systemImage: "gearshape") }
            }
            .environmentObject(repository)
            .environmentObject(settings)
            .environmentObject(uploader)
            .task {
                // 起動時に未送信の記録があれば再送を試みる
                await uploader.retryPending()
            }
        }
    }
}
