# Next-ten difficulty upgrade v3

## Why this pass exists

The v2 audit repaired the interaction thesis and verifier integrity of these ten
mechanics, but several generated instances were still toy-sized. A clean
scripted solve proved wiring; it did not prove that the task imposed enough
interaction debt on a capable computer-use agent. The v3 pass therefore raises
the scale and coupling of each mechanic without substituting tiny targets,
hidden quotas, arbitrary latency gates, OCR, or static question answering.

## Upgraded contracts

| Mechanic | Weak scale before v3 | Current interaction contract |
|---|---|---|
| Impossible Panorama | A compact 3600×1800 scene with 18 objects could be swept quickly. | Search a 4800×2400, 8×4-sector scene containing 32 objects, 108 landmarks, and 28 route marks; identify a transient event, reach at least 1.65× zoom, match its focal plane, and sustain a 940 ms/eight-sample shutter hold. |
| Flat-Pack Compliance | Four parts, three joints, and a short load sequence felt like a tutorial. | Place seven rigid parts, register six keyed joints with orientation and collision clearance, then survive every step of a 36-step oscillating load waveform. |
| Crash-Deadline Hovercar | Three checks and three obstacles left long idle stretches. | Drive a 1,400-unit inertial course around six real collision obstacles while the pointer tracks five independently moving sigils for 11–13 consecutive 50 ms ticks each; finish by tick 330 with zero crashes. |
| Robot Art Critic | Several classes reduced to a handful of nearly symbolic lines. | Draw one of eight structured classes—umbrella, sailboat, fish, flower, ladder, bicycle, lighthouse, or locomotive—using 10–14 required strokes under a budget only one stroke larger, with pose/style variation and a real multiclass margin. |
| Wrong Number | Five lines and a short lock could be solved by setting two controls once. | Explore seven carriers, identify the only authentic waveform, and continuously correct phase and skew against seeded drift through a 4.8-second trial, including a separately graded final window. |
| Bomb Manual From Hell | Three plates and seven wires made the aperture intersection quick to read. | Drag, rotate, mirror, and key five acetate plates. Their 25 apertures intersect at exactly one of nine wires; every pose and the irreversible cut are independently replayed. |
| Dead Man's Switch | A static mouse hold plus three short checkpoints mostly tested whether two inputs could coexist. | Track a deterministic moving pressure pad while issuing a 45–57 move keyboard route through five alternating barriers. The grader replays pad geometry, sample freshness, containment, gaps, route order, and at least 5.2 seconds of continuous pressure. |
| Blind Dice Courier | Two gates and a short route placed little pressure on orientation memory. | Track a labelled die for 53–68 physical rolls through an 18×11 maze and five alternating face gates. Only four sparse scanners reveal orientation. |
| Input-Lag Forklift | A single crate and roughly twelve moves exposed the delay but did not demand planning. | Solve two-crate Sokoban routes of 23–34 commands across twelve topology families and four spatial transforms while every direction executes one command late. |
| Insider Trading CAPTCHA | A short, visibly periodic tape and two-tick delay admitted a reusable timing strategy. | Trade a nonperiodic 34–38 tick piecewise-regime tape through a three-tick queue, fees, and a four-lot limit. A tape is admitted only when a causal policy earns at least 1,400¢ through at least ten settlements; the visible target is at least 1,100¢ and normally 75% of that causal reference. The account must close flat with an empty queue. |

## Fairness and integrity constraints

- Visible geometry, input geometry, simulation geometry, and grader geometry use
  the same generated contracts.
- The grader ignores client `PASS`, score, face, lock, ledger, and assembly
  claims. It independently replays the timestamped interaction transcript.
- Difficulty does not depend on pointer event density, a secret search-distance
  quota, subpixel targets, or a perfect run making deliberate mistakes.
- Generator variation changes topology, motion, temporal phase, pose, or causal
  structure—not merely color and labels.
- Market prices are nonperiodic randomized regimes rather than a sine wave. The
  profit target is calibrated against an online causal policy, not only a
  clairvoyant dynamic program.

## Verification record

The canonical browser cohort exercises a real failure/regeneration path and a
clean physical solve for every mechanic, then requires agreement from the live
server grade, a direct independent grader call, and the exported task verifier.
Its screenshots and exact machine-readable results live in
`evidence/next_ten_difficulty_v3/`.

Two additional full generated cohorts were solved after the structural upgrade.
The market threshold was then tightened further and three additional live-market
seeds passed with targets from 1,250¢ to 3,525¢ and 12–16 exact settlements.
The generator gate covers 80 seeds per mechanic and rejects a forged client
`PASS` with an empty transcript for every one of the ten graders.

### Frozen-contract solution videos

Current solution recordings are in
`evidence/next_ten_difficulty_v3/solution_videos/`. Every mechanic has a
1280×720 H.264 MP4 and its original Playwright WebM. The recording manifest
contains media metadata, SHA-256 checksums, server/direct/verifier results, and
before/after hashes for the task JSON, generator, frontend, grader, and solver.
All ten frozen-contract comparisons passed, all ten MP4s decoded end to end,
and all twenty media checksums matched the manifest.

The videos use ordinary browser mouse and keyboard events. Pacing and the
visible title/outro cards exist only in the recorder; no task timing,
acceptance condition, generator, mechanic, or grader was relaxed for capture.

One multi-seed panorama run exposed a test-only defect: the automation held the
shutter for a nominal 900 ms against an unchanged 940 ms task requirement and
had accidentally relied on screenshot latency. The solver now holds for 1,180
ms. The task was not relaxed.

### Known fidelity boundary: Robot Art Critic

Robot Art Critic is a closed-world structural recognizer, not a faithful
open-world judge. It compares a drawing against a seeded prototype family for
eight supported object classes. A genuinely valid locomotive with a different
topology or visual language can therefore be rejected. That limitation is now
explicit in the dashboard dossier and human-review ledger. The frozen task was
not altered to hide or repair this limitation while the solution recordings
were produced.

Automated verification is evidence of reachability, replay integrity, and UI
wiring. It is not a claim that human VNC calibration or agent-evaluation
difficulty has been established; those remain separate review gates.
