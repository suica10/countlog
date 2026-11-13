import Foundation
import UIKit
import ImageIO

/// マーカー位置（正規化座標 0...1、原点は左上）
struct Marker: Codable, Equatable {
    var x: Double
    var y: Double
}

/// 数量検査の記録（エビデンス）。
/// 保存後は不変。アップロード状態は別ファイルで管理し、この構造は書き換えない。
struct CountRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    /// 機械が出した下書きの個数
    let predictedCount: Int
    /// 人が確認・修正して確定した個数
    let finalCount: Int
    /// 下書きと確定が一致したか
    let wasCorrect: Bool
    /// マーカーの追加・削除が行われたか
    let markersEdited: Bool
    /// 伝票番号などのメモ
    let memo: String
    /// "exemplar" / "blob"
    let method: String
    let markers: [Marker]
}

/// 記録の永続化。
/// 保存先: Application Support/CountLog/records/<uuid>/
///   - image.jpg   元写真（長辺 2048px 以内、JPEG q=0.85）
///   - marked.jpg  マーカーを描いた写真
///   - record.json 記録本体（ISO8601）
/// アップロード状態は CountLog/uploads.json で別管理する。
final class RecordsRepository: ObservableObject {
    @Published private(set) var records: [CountRecord] = []
    @Published private(set) var uploadStates: [String: String] = [:]

    private let rootDir: URL
    private let uploadsFile: URL
    private let thumbnailCache = NSCache<NSString, UIImage>()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let countLogDir = base.appendingPathComponent("CountLog", isDirectory: true)
        rootDir = countLogDir.appendingPathComponent("records", isDirectory: true)
        uploadsFile = countLogDir.appendingPathComponent("uploads.json")
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Paths

    func recordDir(_ id: UUID) -> URL {
        rootDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func fileURL(for record: CountRecord, name: String) -> URL {
        recordDir(record.id).appendingPathComponent(name)
    }

    func imageURL(for record: CountRecord) -> URL { fileURL(for: record, name: "image.jpg") }
    func markedURL(for record: CountRecord) -> URL { fileURL(for: record, name: "marked.jpg") }

    // MARK: - Save / load / delete

    @discardableResult
    func saveRecord(image: UIImage,
                    predictedCount: Int,
                    markers: [CGPoint],
                    markersEdited: Bool,
                    memo: String,
                    method: CountMethod) throws -> CountRecord {
        let record = CountRecord(
            id: UUID(),
            createdAt: Date(),
            predictedCount: predictedCount,
            finalCount: markers.count,
            wasCorrect: predictedCount == markers.count,
            markersEdited: markersEdited,
            memo: memo,
            method: method.rawValue,
            markers: markers.map { Marker(x: Double($0.x), y: Double($0.y)) }
        )
        let dir = recordDir(record.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stored = Self.resizedForStorage(image)
        guard let imageData = stored.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "CountLog", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "写真の保存に失敗しました"])
        }
        try imageData.write(to: dir.appendingPathComponent("image.jpg"))

        let marked = ImageMarking.renderMarkedImage(base: stored, markers: markers)
        if let markedData = marked.jpegData(compressionQuality: 0.85) {
            try markedData.write(to: dir.appendingPathComponent("marked.jpg"))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: dir.appendingPathComponent("record.json"))

        records.insert(record, at: 0)
        uploadStates[record.id.uuidString] = "pending"
        persistUploadStates()
        return record
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [CountRecord] = []
        if let dirs = try? FileManager.default.contentsOfDirectory(at: rootDir, includingPropertiesForKeys: nil) {
            for dir in dirs {
                let jsonURL = dir.appendingPathComponent("record.json")
                if let data = try? Data(contentsOf: jsonURL),
                   let record = try? decoder.decode(CountRecord.self, from: data) {
                    loaded.append(record)
                }
            }
        }
        records = loaded.sorted { $0.createdAt > $1.createdAt }

        if let data = try? Data(contentsOf: uploadsFile),
           let states = try? JSONDecoder().decode([String: String].self, from: data) {
            uploadStates = states
        }
    }

    func delete(_ record: CountRecord) {
        try? FileManager.default.removeItem(at: recordDir(record.id))
        records.removeAll { $0.id == record.id }
        uploadStates.removeValue(forKey: record.id.uuidString)
        thumbnailCache.removeObject(forKey: record.id.uuidString as NSString)
        persistUploadStates()
    }

    // MARK: - Upload state

    /// "pending" | "uploading" | "done" | "failed"
    func uploadState(for record: CountRecord) -> String {
        uploadStates[record.id.uuidString] ?? "pending"
    }

    func setUploadState(_ state: String, for id: UUID) {
        let apply = {
            self.uploadStates[id.uuidString] = state
            self.persistUploadStates()
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func persistUploadStates() {
        guard let data = try? JSONEncoder().encode(uploadStates) else { return }
        try? data.write(to: uploadsFile, options: .atomic)
    }

    // MARK: - Images

    func thumbnail(for record: CountRecord) -> UIImage? {
        let key = record.id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = imageURL(for: record)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 240
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    func fullImage(for record: CountRecord) -> UIImage? {
        UIImage(contentsOfFile: imageURL(for: record).path)
    }

    func markedImage(for record: CountRecord) -> UIImage? {
        UIImage(contentsOfFile: markedURL(for: record).path)
    }

    /// 保存用に長辺 2048px へ縮小する（向きは取り込み時に焼き込み済み）
    static func resizedForStorage(_ image: UIImage) -> UIImage {
        let maxEdge: CGFloat = 2048
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxEdge, longEdge > 0 else { return image }
        let ratio = maxEdge / longEdge
        let newSize = CGSize(width: (size.width * ratio).rounded(),
                             height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// 番号付きマーカーを写真に描き込む（証拠写真 marked.jpg の生成）。
enum ImageMarking {
    static func renderMarkedImage(base: UIImage, markers: [CGPoint]) -> UIImage {
        let size = base.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            let radius = max(16, min(size.width, size.height) * 0.024)
            for (index, point) in markers.enumerated() {
                let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
                let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
                UIColor.systemRed.withAlphaComponent(0.88).setFill()
                UIBezierPath(ovalIn: rect).fill()
                UIColor.white.setStroke()
                let border = UIBezierPath(ovalIn: rect)
                border.lineWidth = max(2, radius * 0.12)
                border.stroke()

                let label = "\(index + 1)" as NSString
                let font = UIFont.boldSystemFont(ofSize: radius * 1.05)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white
                ]
                let textSize = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: center.x - textSize.width / 2,
                                       y: center.y - textSize.height / 2),
                           withAttributes: attributes)
            }
        }
    }
}
