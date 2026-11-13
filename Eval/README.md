# CountLog detector evaluation harness

Offline, reproducible scoring for the counting engine, so detector changes
(v0.2 and later) are judged by numbers instead of one-off device trials.

The tool runs the app's real detector — `App/CounterEngine.swift`, symlinked
into the tool target, never copied/forked — against fixture photos with
known ground truth, on macOS (locally or in GitHub Actions).

## Fixtures

### blister10 (flagship case)

`fixtures/blister10.jpg` + `fixtures/blister10.json` — a PTP blister sheet
of 10 tablets (2 columns x 5 rows). Note on product direction: CountLog's
first sales market is industrial (manufacturing shipping/receiving)
inspection, with pharmacy deferred to a possible phase 2; the PTP blister
fixture is used here as the tractable training subject for the engine.
Every pocket is labelled `full`
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

From the successful Eval workflow run:
https://github.com/suica10/countlog/actions/runs/43412009803
(macOS 26 runner; full point lists are in that run's `eval-results`
artifact.)

| method | threshold | count | hits | false | pockets covered |
|---|---|---|---|---|---|
| exemplarMatch | 0.50 | 1 | 1 | 0 | 1/10 |
| exemplarMatch | 0.60 | 1 | 1 | 0 | 1/10 |
| exemplarMatch | 0.70 | 8 | 4 | 4 | 2/10 |
| exemplarMatch | 0.78 | 23 | 14 | 9 | 6/10 |
| exemplarMatch | 0.85 | 91 | 27 | 64 | 10/10 |
| blobCount (exemplar area) | – | 2 | 0 | 2 | 0/10 |
| blobCount (no exemplar) | – | 12 | 0 | 12 | 0/10 |

("Pockets covered" = distinct ground-truth pockets with at least one hit.
`hits` counts points, so at loose thresholds several points pile onto the
same pocket — e.g. at 0.78, 14 hits cover only 6 pockets.)

How to read this:

- At strict thresholds (0.5–0.6, around the app's default) exemplarMatch
  finds essentially only the exemplar pocket itself: the feature print of
  one white tablet does not generalize to its nine identical siblings.
  Recall is 1/10 at usable precision.
- Loosening the threshold buys coverage with duplicates and junk: at 0.85
  every pocket is "covered", but by 91 points, 64 of them false — foil
  print, desk, and repeated windows around the same pockets (the NMS radius
  of 0.45 x window size is too small to merge them).
- blobCount is hopeless on this subject in both modes (0 hits): tablets
  and foil have similar brightness, so Otsu binarization never isolates
  the tablets; its points land on desk reflections and the sheet's edge.
- No vertical flip: returned points cluster at the real tablet positions
  in top-left normalized coordinates, so the engine's CGImage cropping
  orientation assumption is consistent (at least on macOS).
- Offline counts differ from the on-device trial (17 at 0.78) because the
  exemplar here is a tight programmatic box and the image is the
  screenshot crop; the failure mode is the same.
