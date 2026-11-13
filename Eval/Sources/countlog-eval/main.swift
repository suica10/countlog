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

struct Fixture: Decodable {
    struct Rect: Decodable { let x: Double; let y: Double; let width: Double; let height: Double }
    struct Pocket: Decodable { let row: Int; let col: Int; let center: [Double]; let state: String }
    let exemplarRect: Rect
    let pockets: [Pocket]
}

func loadCGImage(path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

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

        print("fixture: \(imagePath)  image \(cgImage.width)x\(cgImage.height)  groundTruth=\(truth.count) pockets (\(fixture.pockets.filter { $0.state == "full" }.count) full / \(fixture.pockets.filter { $0.state == "empty" }.count) empty)")
        print("exemplarRect: x=\(fmt(exemplar.minX)) y=\(fmt(exemplar.minY)) w=\(fmt(Double(exemplar.width))) h=\(fmt(Double(exemplar.height)))  hitRadius=\(hitRadius)")
        print("")
        print("method                  threshold  count  hits  false")
        print("----------------------  ---------  -----  ----  -----")

        func row(_ method: String, _ threshold: String, _ points: [CGPoint]) {
            let s = score(points)
            print(String(format: "%-22s  %9s  %5d  %4d  %5d", method, threshold, points.count, s.hits, s.false))
            let list = points.map { "(\(fmt(Double($0.x))),\(fmt(Double($0.y))))" }.joined(separator: " ")
            print("  points: \(list.isEmpty ? "(none)" : list)")
        }

        let thresholds: [Float] = [0.5, 0.6, 0.7, 0.78, 0.85]
        for t in thresholds {
            do {
                let pts = try await CounterEngine.exemplarMatch(
                    cgImage: cgImage, exemplarRectNormalized: exemplar, threshold: t)
                row("exemplarMatch", String(format: "%.2f", t), pts)
            } catch {
                print(String(format: "%-22s  %9s  ERROR %@", "exemplarMatch", String(format: "%.2f", t), String(describing: error)))
            }
        }

        do {
            let pts = try await CounterEngine.blobCount(cgImage: cgImage, exemplarRectNormalized: exemplar)
            row("blobCount+exemplarArea", "-", pts)
        } catch {
            print("blobCount+exemplarArea  ERROR \(error)")
        }
        do {
            let pts = try await CounterEngine.blobCount(cgImage: cgImage, exemplarRectNormalized: nil)
            row("blobCount", "-", pts)
        } catch {
            print("blobCount  ERROR \(error)")
        }
    }
}
