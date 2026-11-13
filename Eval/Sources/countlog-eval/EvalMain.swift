import Foundation
import CoreGraphics
import ImageIO

// Offline evaluation harness for CountLog's CounterEngine.
//
// Runs the app's actual detector (App/CounterEngine.swift, symlinked into
// this target - not a copy) against a fixture image + ground-truth JSON and
// prints a compact results table.
//
// Usage:
//   swift run -c release countlog-eval [image.jpg] [groundtruth.json]
// Defaults: fixtures/blister10.jpg, fixtures/blister10.json (relative to CWD).
//
// A returned point is a "hit" when it lies within 0.05 normalized units
// (Euclidean, in 0..1 x 0..1 space) of any ground-truth pocket center;
// otherwise it is "false". Ground truth for this fixture is 10 pockets.
//
// Output goes through FileHandle writes so progress lines survive even if
// a detector call crashes (stdout print() is block-buffered when piped).

struct Fixture: Decodable {
    struct Rect: Decodable { let x: Double; let y: Double; let width: Double; let height: Double }
    struct Pocket: Decodable { let row: Int; let col: Int; let center: [Double]; let state: String }
    let exemplarRect: Rect
    let pockets: [Pocket]
}

func out(_ line: String) {
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
}

func loadCGImage(path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}
func padL(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

@main
struct EvalMain {
    static func main() async {
        let args = CommandLine.arguments
        let imagePath = args.count > 1 ? args[1] : "fixtures/blister10.jpg"
        let jsonPath = args.count > 2 ? args[2] : "fixtures/blister10.json"

        guard let cgImage = loadCGImage(path: imagePath) else {
            FileHandle.standardError.write("error: cannot load image \(imagePath)\n".data(using: .utf8)!)
            exit(1)
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
              let fixture = try? JSONDecoder().decode(Fixture.self, from: data) else {
            FileHandle.standardError.write("error: cannot parse ground truth \(jsonPath)\n".data(using: .utf8)!)
            exit(1)
        }

        let truth: [CGPoint] = fixture.pockets.map { CGPoint(x: $0.center[0], y: $0.center[1]) }
        let exemplar = CGRect(x: fixture.exemplarRect.x, y: fixture.exemplarRect.y,
                              width: fixture.exemplarRect.width, height: fixture.exemplarRect.height)
        let hitRadius: CGFloat = 0.05

        func score(_ points: [CGPoint]) -> (hits: Int, false: Int) {
            var hits = 0
            for p in points {
                let d = truth.map { hypot(p.x - $0.x, p.y - $0.y) }.min() ?? .greatestFiniteMagnitude
                if d <= hitRadius { hits += 1 }
            }
            return (hits, points.count - hits)
        }

        out("fixture: \(imagePath)  image \(cgImage.width)x\(cgImage.height)  groundTruth=\(truth.count) pockets (\(fixture.pockets.filter { $0.state == "full" }.count) full / \(fixture.pockets.filter { $0.state == "empty" }.count) empty)")
        out("exemplarRect: x=\(fmt(exemplar.minX)) y=\(fmt(exemplar.minY)) w=\(fmt(Double(exemplar.width))) h=\(fmt(Double(exemplar.height)))  hitRadius=\(hitRadius)")
        out("")
        out(pad("method", 22) + "  " + padL("threshold", 9) + "  " + padL("count", 5) + "  " + padL("hits", 4) + "  " + padL("false", 5))
        out(String(repeating: "-", count: 22) + "  " + String(repeating: "-", count: 9) + "  " + String(repeating: "-", count: 5) + "  " + String(repeating: "-", count: 4) + "  " + String(repeating: "-", count: 5))

        func row(_ method: String, _ threshold: String, _ points: [CGPoint]) {
            let s = score(points)
            out(pad(method, 22) + "  " + padL(threshold, 9) + "  " + padL(String(points.count), 5) + "  " + padL(String(s.hits), 4) + "  " + padL(String(s.false), 5))
            let list = points.map { "(\(fmt(Double($0.x))),\(fmt(Double($0.y))))" }.joined(separator: " ")
            out("  points: \(list.isEmpty ? "(none)" : list)")
        }

        let thresholds: [Float] = [0.5, 0.6, 0.7, 0.78, 0.85]
        for t in thresholds {
            let tLabel = String(format: "%.2f", t)
            out("running exemplarMatch threshold=\(tLabel) ...")
            do {
                let pts = try await CounterEngine.exemplarMatch(
                    cgImage: cgImage, exemplarRectNormalized: exemplar, threshold: t)
                out("  exemplarMatch \(tLabel) returned \(pts.count) points")
                row("exemplarMatch", tLabel, pts)
            } catch {
                out(pad("exemplarMatch", 22) + "  " + padL(tLabel, 9) + "  ERROR \(error)")
            }
        }

        out("running blobCount with exemplar area ...")
        do {
            let pts = try await CounterEngine.blobCount(cgImage: cgImage, exemplarRectNormalized: exemplar)
            out("  blobCount+exemplarArea returned \(pts.count) points")
            row("blobCount+exemplarArea", "-", pts)
        } catch {
            out("blobCount+exemplarArea  ERROR \(error)")
        }
        out("running blobCount without exemplar area ...")
        do {
            let pts = try await CounterEngine.blobCount(cgImage: cgImage, exemplarRectNormalized: nil)
            out("  blobCount returned \(pts.count) points")
            row("blobCount", "-", pts)
        } catch {
            out("blobCount  ERROR \(error)")
        }
        out("done")
    }
}
