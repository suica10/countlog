# CountLog detector evaluation harness

Offline, reproducible scoring for the counting engine, so detector changes
(v0.2 and later) are judged by numbers instead of one-off device trials.

The tool runs the app's real detector — `App/CounterEngine.swift`, symlinked
into the tool target, never copied/forked — against fixture photos with
known ground truth, on macOS (locally or in GitHub Actions).

## Fixtures

### blister10 (flagship case)

`fixtures/blister10.jpg` + `fixtures/blister10.json` — a PTP blister sheet
of 10 tablets (2 columns x 5 rows), the primary form factor for the
pharmacist-first direction of CountLog. Every pocket is labelled `full`
(all 10 contain tablets); the phase-2 grid-based detector will be scored
against these per-pocket labels.

The image was cropped from the user's iPhone screenshot of the app's review
screen after the failed v0.1 on-device trial (crop rect in the 1206x2622
screenshot: x=348, y=366, w=810, h=1080; the original screenshot is not
committed). The crop therefore still contains the app's red numbered marker
overlays from that run — some sit on pockets, others are the false hits on
the foil print and the desk. Ground truth is the tablets, not the markers.
Pocket centers were estimated by visual grounding on the crop and
cross-checked with an independent smoothness/brightness mask analysis;
the two agreed within ~0.02 normalized units per pocket.

## Scoring

- `count` — number of points the detector returned.
- `hits` — returned points within 0.05 normalized units (Euclidean in
  0..1 x 0..1 space) of a ground-truth pocket center.
- `false` — returned points not within that radius of any pocket center.

Runs: `exemplarMatch` at feature-print thresholds 0.5 / 0.6 / 0.7 / 0.78 /
0.85 (exemplar = the row 1 / column 1 tablet box from the JSON), and
`blobCount` with and without the exemplar area reference (blob has no
threshold parameter).

## Run it

Locally (macOS):

```sh
cd Eval
swift run -c release countlog-eval fixtures/blister10.jpg fixtures/blister10.json
```

In CI: dispatch the **Eval** workflow (`.github/workflows/eval.yml`); the
printed table is in the job log and in the `eval-results` artifact.

## Baseline results (v0.1 detector, 2026-11-13)

_PENDING — filled in from the first CI run._
