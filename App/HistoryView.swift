import SwiftUI

/// 履歴タブ：保存済みの数量検査記録の一覧。
struct HistoryView: View {
    @EnvironmentObject private var repository: RecordsRepository
    @EnvironmentObject private var uploader: WebDAVUploader

    var body: some View {
        NavigationStack {
            List {
                if hasUnuploaded {
                    Button {
                        Task { await uploader.retryPending() }
                    } label: {
                        Label("未送信を再送", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                ForEach(repository.records) { record in
                    NavigationLink {
                        RecordDetailView(record: record)
                    } label: {
                        recordRow(record)
                    }
                }
                .onDelete { offsets in
                    offsets.map { repository.records[$0] }.forEach { repository.delete($0) }
                }
            }
            .navigationTitle("履歴")
            .overlay {
                if repository.records.isEmpty {
                    ContentUnavailableView(
                        "記録がありません",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("撮影タブから数量検査を始めましょう。")
                    )
                }
            }
        }
    }

    private var hasUnuploaded: Bool {
        repository.records.contains {
            let state = repository.uploadState(for: $0)
            return state == "pending" || state == "failed"
        }
    }

    private func recordRow(_ record: CountRecord) -> some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = repository.thumbnail(for: record) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(record.finalCount) 個")
                    .font(.headline)
                if record.finalCount != record.predictedCount {
                    Text("下書き \(record.predictedCount) 個 → 確定 \(record.finalCount) 個")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !record.memo.isEmpty {
                    Text(record.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            uploadStatusIcon(for: record)
        }
    }

    @ViewBuilder
    private func uploadStatusIcon(for record: CountRecord) -> some View {
        switch repository.uploadState(for: record) {
        case "done":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("送信済み")
        case "uploading":
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.blue)
                .accessibilityLabel("送信中")
        case "failed":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("送信失敗")
        default:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityLabel("未送信")
        }
    }
}

/// 記録の詳細：マーカー付き写真を大きく表示する。
struct RecordDetailView: View {
    @EnvironmentObject private var repository: RecordsRepository
    let record: CountRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let marked = repository.markedImage(for: record) {
                    Image(uiImage: marked)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let original = repository.fullImage(for: record) {
                    Image(uiImage: original)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 8) {
                    detailRow("日時", record.createdAt.formatted(date: .complete, time: .shortened))
                    detailRow("確定個数", "\(record.finalCount) 個")
                    detailRow("機械の下書き", "\(record.predictedCount) 個")
                    detailRow("下書きと一致", record.wasCorrect ? "はい" : "いいえ（修正済み）")
                    detailRow("数え方", record.method == "exemplar" ? "対象を指定して計数" : "自動（明暗）")
                    if !record.memo.isEmpty {
                        detailRow("メモ", record.memo)
                    }
                    detailRow("送信状態", uploadStateText)
                }
                .font(.subheadline)
            }
            .padding()
        }
        .navigationTitle("記録の詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var uploadStateText: String {
        switch repository.uploadState(for: record) {
        case "done": return "送信済み"
        case "uploading": return "送信中"
        case "failed": return "送信失敗（履歴の「未送信を再送」から再送できます）"
        default: return "未送信"
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
            Spacer()
        }
    }
}
