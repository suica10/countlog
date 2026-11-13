import Foundation
import Vision
import CoreGraphics

/// カウント方式
enum CountMethod: String {
    case exemplar  // 対象を囲んで特徴マッチングで数える
    case blob      // 明暗の二値化＋連結成分で数える
}

enum CounterEngineError: Error {
    case invalidImage
    case exemplarTooSmall
    case featurePrintFailed
}

/// 端末上のカウントエンジン。
/// どちらの方式も「下書き」を返すもので、最終確認は人が行う前提。
/// 返り値の座標はすべて正規化座標 (0...1、原点は左上)。
enum CounterEngine {

    // MARK: - Public async API

    /// 囲んだ1個の特徴に似た物を画像全体から探して数える。
    static func exemplarMatch(cgImage: CGImage, exemplarRectNormalized: CGRect, threshold: Float) async throws -> [CGPoint] {
        try await Task.detached(priority: .userInitiated) {
            try exemplarMatchSync(cgImage: cgImage, exemplarRectNormalized: exemplarRectNormalized, threshold: threshold)
        }.value
    }

    /// 明暗で二値化し、連結成分（かたまり）を数える。
    /// exemplarRectNormalized がある場合はその面積を基準に成分をふるい分ける。
    static func blobCount(cgImage: CGImage, exemplarRectNormalized: CGRect?) async throws -> [CGPoint] {
        try await Task.detached(priority: .userInitiated) {
            try blobCountSync(cgImage: cgImage, exemplarRectNormalized: exemplarRectNormalized)
        }.value
    }

    // MARK: - Exemplar matching (Vision feature print)

    private static func exemplarMatchSync(cgImage: CGImage, exemplarRectNormalized: CGRect, threshold: Float) throws -> [CGPoint] {
        let proc = downscaled(cgImage, maxLongEdge: 1200)
        let W = proc.width
        let H = proc.height
        guard W > 0, H > 0 else { throw CounterEngineError.invalidImage }

        let rawRect = CGRect(x: exemplarRectNormalized.minX * CGFloat(W),
                             y: exemplarRectNormalized.minY * CGFloat(H),
                             width: exemplarRectNormalized.width * CGFloat(W),
                             height: exemplarRectNormalized.height * CGFloat(H))
        let bounds = CGRect(x: 0, y: 0, width: W, height: H)
        let exRect = rawRect.intersection(bounds).integral
        guard !exRect.isNull, exRect.width >= 8, exRect.height >= 8 else {
            throw CounterEngineError.exemplarTooSmall
        }
        guard let exCrop = proc.cropping(to: exRect) else { throw CounterEngineError.invalidImage }
        let exPrint = try featurePrint(of: exCrop)

        // スライディングウィンドウ列挙（総数が上限を超える場合はストライドを広げる）
        let scales: [CGFloat] = [0.85, 1.0, 1.18]
        let maxWindows = 1500
        var strideScale: CGFloat = 1.0
        var windows: [CGRect] = []
        while true {
            windows = buildWindows(imageWidth: W, imageHeight: H,
                                   exemplarSize: exRect.size, scales: scales,
                                   strideScale: strideScale)
            if windows.count <= maxWindows || strideScale > 8 { break }
            strideScale *= 1.3
        }

        struct Hit {
            let center: CGPoint   // 正規化座標
            let distance: Float
            let size: CGFloat     // ウィンドウの短辺 (px)
        }
        var hits: [Hit] = []
        hits.reserveCapacity(windows.count / 4)
        for rect in windows {
            let r = rect.integral
            guard r.minX >= 0, r.minY >= 0, r.width >= 4, r.height >= 4,
                  let crop = proc.cropping(to: r),
                  let print = try? featurePrint(of: crop) else { continue }
            var distance: Float = 0
            do {
                try exPrint.computeDistance(&distance, to: print)
            } catch {
                continue
            }
            if distance <= threshold {
                hits.append(Hit(center: CGPoint(x: r.midX / CGFloat(W), y: r.midY / CGFloat(H)),
                                distance: distance,
                                size: min(r.width, r.height)))
            }
        }

        // Non-maximum suppression: 距離の小さい順に採用し、近い重複を落とす
        hits.sort { $0.distance < $1.distance }
        var accepted: [Hit] = []
        for hit in hits {
            let suppressed = accepted.contains { other in
                let dx = (hit.center.x - other.center.x) * CGFloat(W)
                let dy = (hit.center.y - other.center.y) * CGFloat(H)
                return (dx * dx + dy * dy).squareRoot() < 0.45 * hit.size
            }
            if !suppressed { accepted.append(hit) }
        }
        return accepted.map { $0.center }
    }

    private static func buildWindows(imageWidth W: Int, imageHeight H: Int,
                                     exemplarSize: CGSize, scales: [CGFloat],
                                     strideScale: CGFloat) -> [CGRect] {
        var result: [CGRect] = []
        for s in scales {
            let ww = exemplarSize.width * s
            let wh = exemplarSize.height * s
            guard ww >= 8, wh >= 8, ww <= CGFloat(W), wh <= CGFloat(H) else { continue }
            let strideX = max(4, 0.4 * ww * strideScale)
            let strideY = max(4, 0.4 * wh * strideScale)
            let xs = axisPositions(length: CGFloat(W), window: ww, stride: strideX)
            let ys = axisPositions(length: CGFloat(H), window: wh, stride: strideY)
            for y in ys {
                for x in xs {
                    result.append(CGRect(x: x, y: y, width: ww, height: wh))
                }
            }
        }
        return result
    }

    private static func axisPositions(length: CGFloat, window: CGFloat, stride: CGFloat) -> [CGFloat] {
        let maxStart = length - window
        guard maxStart >= 0 else { return [] }
        var result: [CGFloat] = []
        var v: CGFloat = 0
        while v < maxStart {
            result.append(v)
            v += stride
        }
        result.append(maxStart)
        return result
    }

    /// 切り抜き画像の特徴プリントを返す。小さい切り抜きは拡大してから計算する。
    private static func featurePrint(of cgImage: CGImage) throws -> VNFeaturePrintObservation {
        let image = scaledUpIfSmall(cgImage)
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw CounterEngineError.featurePrintFailed
        }
        return observation
    }

    private static func scaledUpIfSmall(_ image: CGImage) -> CGImage {
        let minDim = min(image.width, image.height)
        guard minDim > 0, minDim < 48 else { return image }
        let factor = 96.0 / Double(minDim)
        let nw = max(1, Int((Double(image.width) * factor).rounded()))
        let nh = max(1, Int((Double(image.height) * factor).rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? image
    }

    // MARK: - Blob counting (Otsu + connected components)

    private static func blobCountSync(cgImage: CGImage, exemplarRectNormalized: CGRect?) throws -> [CGPoint] {
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0, srcH > 0 else { throw CounterEngineError.invalidImage }
        let scale = min(1.0, 800.0 / Double(srcW))
        let W = max(1, Int((Double(srcW) * scale).rounded()))
        let H = max(1, Int((Double(srcH) * scale).rounded()))

        // グレースケール化（バッファの先頭行が画像の上端になるよう反転して描く）
        var pixels = [UInt8](repeating: 0, count: W * H)
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: W, height: H,
                                      bitsPerComponent: 8, bytesPerRow: W,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.translateBy(x: 0, y: CGFloat(H))
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: W, height: H))
        }

        let threshold = otsuThreshold(pixels)
        let exemplarArea: Double? = exemplarRectNormalized.map {
            Double($0.width) * Double(W) * Double($0.height) * Double(H)
        }

        func evaluate(foregroundIsDark: Bool) -> (fraction: Double, centers: [CGPoint]) {
            let foreground: [Bool] = pixels.map { foregroundIsDark ? ($0 < threshold) : ($0 >= threshold) }
            var fgCount = 0
            for f in foreground where f { fgCount += 1 }
            let fraction = Double(fgCount) / Double(W * H)
            let components = connectedComponents(foreground: foreground, width: W, height: H)
            let kept = filterComponents(components, exemplarArea: exemplarArea, imageArea: W * H)
            let centers = kept.map { CGPoint(x: $0.cx / Double(W), y: $0.cy / Double(H)) }
            return (fraction, centers)
        }

        let dark = evaluate(foregroundIsDark: true)
        let bright = evaluate(foregroundIsDark: false)
        let darkPlausible = dark.fraction > 0.02 && dark.fraction < 0.6
        let brightPlausible = bright.fraction > 0.02 && bright.fraction < 0.6
        switch (darkPlausible, brightPlausible) {
        case (true, true):
            return dark.centers.count >= bright.centers.count ? dark.centers : bright.centers
        case (true, false):
            return dark.centers
        case (false, true):
            return bright.centers
        case (false, false):
            return dark.centers.count >= bright.centers.count ? dark.centers : bright.centers
        }
    }

    private static func otsuThreshold(_ pixels: [UInt8]) -> UInt8 {
        var hist = [Double](repeating: 0, count: 256)
        for p in pixels { hist[Int(p)] += 1 }
        let total = Double(pixels.count)
        guard total > 0 else { return 127 }
        var sum: Double = 0
        for i in 0..<256 { sum += Double(i) * hist[i] }
        var sumBackground: Double = 0
        var weightBackground: Double = 0
        var maxBetween: Double = -1
        var threshold = 127
        for i in 0..<256 {
            weightBackground += hist[i]
            if weightBackground == 0 { continue }
            let weightForeground = total - weightBackground
            if weightForeground == 0 { break }
            sumBackground += Double(i) * hist[i]
            let meanBackground = sumBackground / weightBackground
            let meanForeground = (sum - sumBackground) / weightForeground
            let diff = meanBackground - meanForeground
            let between = weightBackground * weightForeground * diff * diff
            if between > maxBetween {
                maxBetween = between
                threshold = i
            }
        }
        return UInt8(clamping: threshold)
    }

    private struct Component {
        let area: Int
        let cx: Double  // 重心 (px)
        let cy: Double
    }

    /// 2パス連結成分ラベリング（union-find）
    private static func connectedComponents(foreground: [Bool], width W: Int, height H: Int) -> [Component] {
        var labels = [Int32](repeating: -1, count: W * H)
        var parent: [Int] = []

        func newLabel() -> Int {
            parent.append(parent.count)
            return parent.count - 1
        }
        func root(_ a: Int) -> Int {
            var r = a
            while parent[r] != r { r = parent[r] }
            var c = a
            while parent[c] != c {
                let next = parent[c]
                parent[c] = r
                c = next
            }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let ra = root(a)
            let rb = root(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }

        for y in 0..<H {
            for x in 0..<W {
                let i = y * W + x
                guard foreground[i] else { continue }
                var neighbors: [Int] = []
                if x > 0, labels[i - 1] >= 0 { neighbors.append(Int(labels[i - 1])) }
                if y > 0, labels[i - W] >= 0 { neighbors.append(Int(labels[i - W])) }
                if neighbors.isEmpty {
                    labels[i] = Int32(newLabel())
                } else {
                    let m = neighbors.min()!
                    labels[i] = Int32(m)
                    for n in neighbors where n != m { union(m, n) }
                }
            }
        }

        var stats: [Int: (area: Int, sumX: Double, sumY: Double)] = [:]
        for y in 0..<H {
            for x in 0..<W {
                let i = y * W + x
                let label = labels[i]
                guard label >= 0 else { continue }
                let r = root(Int(label))
                var s = stats[r] ?? (area: 0, sumX: 0, sumY: 0)
                s.area += 1
                s.sumX += Double(x)
                s.sumY += Double(y)
                stats[r] = s
            }
        }
        return stats.values.map {
            Component(area: $0.area, cx: $0.sumX / Double($0.area), cy: $0.sumY / Double($0.area))
        }
    }

    private static func filterComponents(_ components: [Component], exemplarArea: Double?, imageArea: Int) -> [Component] {
        let minArea = max(8.0, Double(imageArea) * 0.0002)  // 画像面積の 0.02%
        let base = components.filter { Double($0.area) >= minArea }
        guard !base.isEmpty else { return [] }
        if let exemplarArea {
            return base.filter {
                let a = Double($0.area)
                return a >= exemplarArea * 0.35 && a <= exemplarArea * 2.8
            }
        } else {
            let areas = base.map { Double($0.area) }.sorted()
            let median = areas[areas.count / 2]
            guard median > 0 else { return [] }
            return base.filter {
                let a = Double($0.area)
                return a >= median * 0.3 && a <= median * 3.5
            }
        }
    }

    // MARK: - Helpers

    private static func downscaled(_ cgImage: CGImage, maxLongEdge: Int) -> CGImage {
        let w = cgImage.width
        let h = cgImage.height
        let longEdge = max(w, h)
        guard longEdge > maxLongEdge, longEdge > 0 else { return cgImage }
        let scale = Double(maxLongEdge) / Double(longEdge)
        let nw = max(1, Int((Double(w) * scale).rounded()))
        let nh = max(1, Int((Double(h) * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cgImage }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? cgImage
    }
}
