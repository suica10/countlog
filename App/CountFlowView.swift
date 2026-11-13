import SwiftUI
import PhotosUI
import UIKit

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

/// 撮影タブ：写真を選ぶ → 対象を囲む → 数える → 確認・修正 → 確定保存、の状態機械。
struct CountFlowView: View {
    @EnvironmentObject private var repository: RecordsRepository
    @EnvironmentObject private var uploader: WebDAVUploader

    private enum Step {
        case pick
        case exemplar
        case counting
        case review
    }

    @State private var step: Step = .pick
    @State private var workingImage: UIImage?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?

    @State private var exemplarRect = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
    @State private var method: CountMethod = .exemplar
    @State private var markers: [CGPoint] = []
    @State private var initialMarkers: [CGPoint] = []
    @State private var predictedCount = 0
    @State private var threshold: Double = 0.6
    @State private var memo = ""

    @State private var errorMessage: String?
    @State private var showSavedAlert = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pick:
                    pickView
                case .exemplar:
                    exemplarView
                case .counting:
                    countingView
                case .review:
                    reviewView
                }
            }
            .navigationTitle("撮影")
            .alert("エラー", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("保存しました", isPresented: $showSavedAlert) {
                Button("OK") { resetFlow() }
            } message: {
                Text("記録を保存しました。サーバーへのアップロードは自動で行われます。")
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in setImage(image) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        setImage(image)
                    }
                    pickerItem = nil
                }
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: - Step 1: pick photo

    private var pickView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("撮影の確認", systemImage: "checklist")
                        .font(.headline)
                    Text("・出荷伝票・識別札を品物と一緒に写す\n・品物は広げて一層に、重ねない\n・1枚に1品種だけ、明るい場所で真上から")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    showCamera = true
                } label: {
                    Label("カメラで撮る", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("写真を選ぶ", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
        }
    }

    // MARK: - Step 2: exemplar selection

    private var exemplarView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("数えたい品物を1つ、四角でぴったり囲んでください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let image = workingImage {
                    ExemplarCanvas(image: image, rect: $exemplarRect)
                        .frame(height: 400)
                }

                Button {
                    method = .exemplar
                    runCounting()
                } label: {
                    Label("この対象で数える", systemImage: "hand.tap")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    method = .blob
                    runCounting()
                } label: {
                    Label("自動（明暗）で数える", systemImage: "circle.hexagongrid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("「自動（明暗）」は囲む操作なしで、明暗のかたまりを数えます。背景との明暗差がはっきりしている写真向きです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("写真を選び直す") {
                    step = .pick
                }
                .font(.subheadline)
            }
            .padding()
        }
    }

    // MARK: - Step 3: counting

    private var countingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("数えています…")
                .font(.headline)
            Text("機械の数値は下書きです。この後の画面で必ず目視確認してください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 4: review & correct

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image = workingImage {
                    ReviewCanvas(image: image, markers: markers) { location, fitted in
                        handleReviewTap(location, fitted: fitted)
                    }
                    .frame(height: 360)
                }

                VStack(spacing: 4) {
                    Text("\(markers.count) 個")
                        .font(.system(size: 44, weight: .bold))
                    if markers.count == predictedCount {
                        Text("機械の下書きと一致しています")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("機械の下書き \(predictedCount) 個 → 修正して \(markers.count) 個")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("マーカーの無い場所をタップすると追加、マーカーをタップすると削除できます。漏れや数え過ぎがないか、写真と見比べて確認してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if method == .exemplar {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("感度")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.2f", threshold))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $threshold, in: 0.35...0.9, step: 0.01)
                        Text("小さいほど厳しく（少なく）、大きいほど緩く（多く）数えます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            runCounting()
                        } label: {
                            Label("再計算", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                TextField("伝票番号・メモ（任意）", text: $memo)
                    .textFieldStyle(.roundedBorder)

                Button {
                    saveRecord()
                } label: {
                    Label("確定して保存", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("やめて写真を選び直す", role: .destructive) {
                    resetFlow()
                }
                .font(.subheadline)
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func setImage(_ image: UIImage) {
        workingImage = Self.bakedImage(image)
        exemplarRect = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        markers = []
        initialMarkers = []
        memo = ""
        step = .exemplar
    }

    private func runCounting() {
        guard let image = workingImage, let cgImage = image.cgImage else { return }
        step = .counting
        let currentMethod = method
        let rect = exemplarRect
        let currentThreshold = Float(threshold)
        Task {
            do {
                let points: [CGPoint]
                switch currentMethod {
                case .exemplar:
                    points = try await CounterEngine.exemplarMatch(
                        cgImage: cgImage, exemplarRectNormalized: rect, threshold: currentThreshold)
                case .blob:
                    points = try await CounterEngine.blobCount(
                        cgImage: cgImage, exemplarRectNormalized: nil)
                }
                markers = points
                initialMarkers = points
                predictedCount = points.count
                step = .review
            } catch {
                errorMessage = "うまく数えられませんでした。対象の囲み方を変えるか、「自動（明暗）で数える」をお試しください。"
                step = .exemplar
            }
        }
    }

    private func handleReviewTap(_ location: CGPoint, fitted: CGRect) {
        let nx = (location.x - fitted.minX) / fitted.width
        let ny = (location.y - fitted.minY) / fitted.height
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return }
        let tap = CGPoint(x: nx, y: ny)
        if let nearest = markers.indices.min(by: { markers[$0].distance(to: tap) < markers[$1].distance(to: tap) }),
           markers[nearest].distance(to: tap) < 0.035 {
            markers.remove(at: nearest)
        } else {
            markers.append(tap)
        }
    }

    private func saveRecord() {
        guard let image = workingImage else { return }
        do {
            let record = try repository.saveRecord(
                image: image,
                predictedCount: predictedCount,
                markers: markers,
                markersEdited: markers != initialMarkers,
                memo: memo,
                method: method)
            Task { await uploader.upload(record) }
            showSavedAlert = true
        } catch {
            errorMessage = "保存に失敗しました。もう一度お試しください。"
        }
    }

    private func resetFlow() {
        workingImage = nil
        markers = []
        initialMarkers = []
        memo = ""
        pickerItem = nil
        step = .pick
    }

    /// 向きを焼き込み、長辺 3000px 以内に収めた作業用画像を作る。
    /// これ以降の座標計算はすべてこの画像基準で単純になる。
    static func bakedImage(_ image: UIImage) -> UIImage {
        let maxEdge: CGFloat = 3000
        var size = image.size
        let longEdge = max(size.width, size.height)
        if longEdge > maxEdge, longEdge > 0 {
            let ratio = maxEdge / longEdge
            size = CGSize(width: (size.width * ratio).rounded(),
                          height: (size.height * ratio).rounded())
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// アスペクトフィットで表示される画像の矩形（コンテナ座標）
    static func fittedRect(container: CGSize, imageSize: CGSize) -> CGRect {
        guard container.width > 0, container.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: (container.width - width) / 2,
                      y: (container.height - height) / 2,
                      width: width, height: height)
    }
}

// MARK: - Exemplar selection canvas

/// 写真の上にドラッグ移動・リサイズできる四角を重ねるキャンバス。
private struct ExemplarCanvas: View {
    let image: UIImage
    @Binding var rect: CGRect  // 正規化座標

    @State private var moveStartRect: CGRect?
    @State private var resizeStartRect: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let fitted = CountFlowView.fittedRect(container: geometry.size, imageSize: image.size)
            let boxX = fitted.minX + rect.minX * fitted.width
            let boxY = fitted.minY + rect.minY * fitted.height
            let boxW = rect.width * fitted.width
            let boxH = rect.height * fitted.height

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .offset(x: fitted.minX, y: fitted.minY)

                Rectangle()
                    .fill(Color.yellow.opacity(0.10))
                    .frame(width: boxW, height: boxH)
                    .overlay(Rectangle().stroke(Color.yellow, lineWidth: 2))
                    .offset(x: boxX, y: boxY)
                    .gesture(moveGesture(fitted: fitted))

                Circle()
                    .fill(Color.yellow)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black))
                    .offset(x: boxX + boxW - 15, y: boxY + boxH - 15)
                    .gesture(resizeGesture(fitted: fitted))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func moveGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if moveStartRect == nil { moveStartRect = rect }
                guard let start = moveStartRect, fitted.width > 0, fitted.height > 0 else { return }
                var next = start
                next.origin.x = start.minX + value.translation.width / fitted.width
                next.origin.y = start.minY + value.translation.height / fitted.height
                next.origin.x = min(max(next.origin.x, 0), 1 - next.width)
                next.origin.y = min(max(next.origin.y, 0), 1 - next.height)
                rect = next
            }
            .onEnded { _ in moveStartRect = nil }
    }

    private func resizeGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if resizeStartRect == nil { resizeStartRect = rect }
                guard let start = resizeStartRect, fitted.width > 0, fitted.height > 0 else { return }
                var next = start
                next.size.width = min(max(start.width + value.translation.width / fitted.width, 0.04),
                                      1 - start.minX)
                next.size.height = min(max(start.height + value.translation.height / fitted.height, 0.04),
                                       1 - start.minY)
                rect = next
            }
            .onEnded { _ in resizeStartRect = nil }
    }
}

// MARK: - Review canvas

/// 番号付きマーカーを重ねた写真。タップ位置を正規化座標へ変換して返す。
private struct ReviewCanvas: View {
    let image: UIImage
    let markers: [CGPoint]
    var onTap: (CGPoint, CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            let fitted = CountFlowView.fittedRect(container: geometry.size, imageSize: image.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .offset(x: fitted.minX, y: fitted.minY)

                ForEach(Array(markers.enumerated()), id: \.offset) { index, point in
                    let radius = max(13.0, min(fitted.width, fitted.height) * 0.035)
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.88))
                            .frame(width: radius * 2, height: radius * 2)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        Text("\(index + 1)")
                            .font(.system(size: radius * 1.05, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: fitted.minX + point.x * fitted.width - radius,
                            y: fitted.minY + point.y * fitted.height - radius)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    onTap(value.location, fitted)
                }
            )
        }
    }
}

// MARK: - Camera picker

struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage) -> Void

        init(onPick: @escaping (UIImage) -> Void) {
            self.onPick = onPick
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onPick(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
