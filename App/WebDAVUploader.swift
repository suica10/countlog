import Foundation
import Security

/// パスワードを Keychain に保存する小さなラッパー。
enum KeychainHelper {
    private static let service = "jp.onejpkey.countlog.webdav"
    private static let account = "password"

    static func savePassword(_ password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func readPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// WebDAV 接続設定。URL とユーザー名は UserDefaults、パスワードは Keychain。
final class WebDAVSettings: ObservableObject {
    @Published var baseURL: String
    @Published var username: String
    @Published var password: String

    private enum Keys {
        static let baseURL = "webdav.baseURL"
        static let username = "webdav.username"
    }

    init() {
        baseURL = UserDefaults.standard.string(forKey: Keys.baseURL) ?? "https://suica10.duckdns.org/countlog"
        username = UserDefaults.standard.string(forKey: Keys.username) ?? "counter"
        password = KeychainHelper.readPassword() ?? ""
    }

    func save() {
        UserDefaults.standard.set(baseURL, forKey: Keys.baseURL)
        UserDefaults.standard.set(username, forKey: Keys.username)
        KeychainHelper.savePassword(password)
    }
}

/// 記録（エビデンス一式）を WebDAV サーバーへ自動アップロードする。
/// アップロード先: <base>/<yyyy-MM-dd>/<uuid>/ に image.jpg / marked.jpg / record.json
final class WebDAVUploader: ObservableObject {
    private let repository: RecordsRepository
    private let settings: WebDAVSettings

    init(repository: RecordsRepository, settings: WebDAVSettings) {
        self.repository = repository
        self.settings = settings
    }

    // MARK: - Upload

    func upload(_ record: CountRecord) async {
        repository.setUploadState("uploading", for: record.id)
        let dateFolder = Self.dateFolderName(for: record.createdAt)
        let recordFolder = "\(dateFolder)/\(record.id.uuidString)"

        // 日付フォルダと記録フォルダを用意する（既にあればエラーになるが無視する）
        for path in [dateFolder, recordFolder] {
            if let url = makeURL(path: path) {
                _ = try? await URLSession.shared.data(for: authorizedRequest(url: url, method: "MKCOL"))
            }
        }

        var success = true
        for name in ["image.jpg", "marked.jpg", "record.json"] {
            guard let url = makeURL(path: "\(recordFolder)/\(name)") else {
                success = false
                break
            }
            do {
                let data = try Data(contentsOf: repository.fileURL(for: record, name: name))
                var request = authorizedRequest(url: url, method: "PUT")
                request.setValue(name.hasSuffix(".json") ? "application/json" : "image/jpeg",
                                 forHTTPHeaderField: "Content-Type")
                request.httpBody = data
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    success = false
                    break
                }
            } catch {
                success = false
                break
            }
        }
        repository.setUploadState(success ? "done" : "failed", for: record.id)
    }

    /// pending / failed の記録をすべて再送する。アプリ起動時に呼ばれる。
    func retryPending() async {
        let targets = repository.records.filter {
            repository.uploadState(for: $0) == "pending" || repository.uploadState(for: $0) == "failed"
        }
        for record in targets {
            await upload(record)
        }
    }

    /// 接続テスト。PROPFIND (Depth: 0) が 200 / 207 / 301 なら成功とみなす。
    func testConnection() async -> Bool {
        guard let url = makeURL(path: "") else { return false }
        var request = authorizedRequest(url: url, method: "PROPFIND")
        request.setValue("0", forHTTPHeaderField: "Depth")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return [200, 207, 301].contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func makeURL(path: String) -> URL? {
        var base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        return URL(string: path.isEmpty ? base + "/" : base + "/" + path)
    }

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let credentials = "\(settings.username):\(settings.password)"
        let token = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func dateFolderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
