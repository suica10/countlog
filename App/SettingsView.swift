import SwiftUI

/// 設定タブ：WebDAV 接続先の設定と接続テスト。
struct SettingsView: View {
    @EnvironmentObject private var settings: WebDAVSettings
    @EnvironmentObject private var uploader: WebDAVUploader

    @State private var savedMessage = false
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("URL", text: $settings.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("ユーザー名", text: $settings.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("パスワード", text: $settings.password)
                } header: {
                    Text("WebDAV 接続先")
                } footer: {
                    Text("確定した記録は、このサーバーの <日付>/<記録ID> フォルダへ自動でアップロードされます。パスワードは端末の Keychain に保存されます。")
                }

                Section {
                    Button("保存") {
                        settings.save()
                        savedMessage = true
                        testResult = nil
                    }
                    if savedMessage {
                        Text("保存しました")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await runConnectionTest() }
                    } label: {
                        HStack {
                            Text("接続テスト")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting)
                    if let testResult {
                        Text(testResult)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("このアプリについて") {
                    Text("検数ログ（CountLog）v0.1")
                    Text("数量検査の目的は「数えること」ではなく「エビデンスを残すこと」。このアプリは、写真・個数・日時を1セットの記録として残し、サーバーへ自動で送ります。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }

    private func runConnectionTest() async {
        isTesting = true
        testResult = nil
        savedMessage = false
        let ok = await uploader.testConnection()
        testResult = ok ? "接続できました" : "接続できませんでした。URL・ユーザー名・パスワードと、ネットワークを確認してください。"
        isTesting = false
    }
}
