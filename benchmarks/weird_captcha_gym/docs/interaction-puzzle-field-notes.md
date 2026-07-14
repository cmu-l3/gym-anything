# Interaction Puzzle Field Notes

Created: 2026-07-10 · Updated: 2026-07-12

Status: living design record

Scope: the full Weird CAPTCHA Gym exploration, all six interaction-first packs, the historical Incubator builds, and the final 65-folder integration

## The one-sentence principle

Build strange, human-manageable visual puzzles whose real difficulty comes from interacting over time, then use them to evaluate screenshot-driven computer-use agents; CAPTCHA is an idea source, not the objective, and hidden generation/verifier infrastructure is support work rather than the contribution.

## Why this document exists

This is the handoff the next maintainer—or the next Codex instance—must read before changing or adding a puzzle. It records:

- the user's corrections to the benchmark's purpose;
- the source-mined puzzle packs and why they were chosen;
- every material issue discovered during browser and VNC testing;
- the changes made in response;
- the distinction between automatic verification and human validation;
- known gaps that must not be forgotten after context compaction.

The conversation was reconstructed from the complete local Codex rollout at:

```text
~/.codex/sessions/2026/07/09/rollout-2026-07-09T18-26-06-019f48fc-f9d0-7143-a447-9914eb46d171.jsonl
```

The transcript was then checked against the current generators, browser runtime, live server, exported verifiers, task metadata, provenance manifests, browser smoke tools, screenshots, and tests. Chat recollection alone is not treated as proof.

## What the benchmark is—and is not

### It is

- A benchmark for difficult visual puzzles operated through ordinary screenshots, mouse input, and keyboard input.
- An attempt to expose weaknesses in computer-use agents that remain even when their underlying VLM has strong static visual understanding.
- A source-grounded design project: internet CAPTCHAs, puzzle games, videos, papers, blogs, code, and submissions are mined for interaction mechanics.
- A shared runtime with fresh procedural instances, hidden grading state, retry behavior, and outcome verification.
- A human-calibrated research surface that still requires actual computer-use-agent evaluation.

### It is not

- A CAPTCHA security product.
- A benchmark whose novelty is “we procedurally generated hidden ground truth.”
- A collection of static “find the apple,” grid selection, OCR, arithmetic, or ordinary slider tasks.
- A license to make a puzzle hard through broken controls, invisible rules, accidental occlusion, transport latency, or verifier/UI disagreement.
- Proven useful merely because unit tests, schemas, or a scripted solver pass.
- Proven to defeat agents until real agent trajectories demonstrate that claim.

## Repository and benchmark context recovered at the start

The workspace contains the research collection and the Gym-Anything implementation. At the time of the survey, the research corpus contained 74 catalogued source collections, about 19,000 files, 1,788 media artifacts, and 44 normalized mechanic families.

The original Weird CAPTCHA Gym surface had 25 environment families:

- 10 working visual prototypes;
- 13 intentional scaffolds with placeholder verifiers;
- 2 rejected infrastructure pilots;
- 0 tasks on the verified evaluation surface.

The completed tree now contains 65 real environment folders: 63 built/prototype designs, 0 scaffolds, 0 concept-only records, and 2 rejected pilots. Forty-three formerly queued or selected Incubator/Pack III–VI mechanics were promoted only after implementation and evidence. They live inside the existing benchmark contract rather than as standalone demos:

```text
task metadata
  -> seeded public state + hidden ground truth
  -> shared browser renderer and interaction state
  -> live server grading
  -> exported task result
  -> independent Gym-Anything verifier
  -> screenshot and trajectory evidence
```

Every puzzle uses the same normal computer-use surface. No mechanic receives privileged agent actions. For spatial mechanics, the browser receives the geometry needed for honest rendering, hit testing, and local collision, while hidden routes/answers stay private and the server independently replays primitive actions against its own geometry. That is a screenshot/action-agent boundary, not secrecy from browser internals.

## User request and response ledger

This section is chronological. “Implemented” means present in the current tree. “Observed” means learned from a human VNC run. “Open” means it must not be described as solved.

| Phase | User insight or request | Result | Status |
|---|---|---|---|
| Repository exploration | Deeply inspect the repository and separate its principle, components, completed work, and gaps. | Mapped the research corpus, Gym-Anything runtime, benchmark architecture, 25 original families, shared app/server/verifier flow, evidence system, and empty verified surface. | Documented; initial infrastructure review complete. |
| Principle correction | The goal is difficult visual puzzles for evaluating computer-use agents—not CAPTCHA generation and not hidden ground truth. Modern VLMs already understand basic static objects; interaction is the weakness. | Reframed all later selection and implementation around motion, cursor exploration, temporal state, repeated screenshots, motor control, timing, recovery, and changing interfaces. | Permanent design doctrine. |
| Source mining | Inspect the full mined corpus, reject generic grids/OCR/text entry, and select five of the strangest, most annoying, fun, interaction-heavy ideas. | Selected five mechanics spanning motion-only perception, active cursor vision, parallel time control, a moving coordinate frame, and transient timed input. | Implemented as pack one. |
| Build pack one | Build all five; collect screenshots; iterate until automatically verified; only then spawn VNC tasks one by one for human tests. | Added full generator/UI/server/export/verifier/task/split/provenance surfaces and randomized Playwright solves with failure regeneration and screenshots. | Implemented and automatically verified. |
| Live access | Built-in VNC keyboard/mouse control was flaky; provide a stable external-viewer endpoint. | Preserved the running guest when changing viewers and used the runner-published VNC endpoint rather than guessing a port. | Operational lesson for this host; no viewer brand is itself evidence. Ports are ephemeral. |
| Human test: Ghost Jigsaw | The puzzle was compelling enough that an agent solving it would feel AGI-level. | Confirmed motion-only perception is aligned with the benchmark goal and is fun despite being demanding. | Human-positive signal; no agent evaluation yet. |
| Human test: Constellation | Asked for the source and then how to solve it; the yellow selection circle appeared at different final locations. | Explained the CAPTCHaStar source and that the circle records cursor coordinates, not the visual object's position. Different locations across regenerated challenges are expected. Found that visual convergence is broader than the 28 px accepted radius. | Human passed it; visual/verifier calibration remains open. |
| Human test: Grillmaster | Positive reaction and request to continue. | Reinforced that parallel monitoring with visual doneness cues is legible and fun. | Human-positive signal. |
| Human test: Rotating Keyboard | Even more positive reaction and request to continue. | Reinforced moving-coordinate-frame tasks as a strong screenshot/action-loop stressor. | Human-positive signal. |
| Human test: Slot Reels | A visually complete five-character board failed. User preferred visible strikes. | Found two hidden mistimed keypresses. Replaced zero-tolerance hidden rejection with visible `STRIKES 0/3`; ignored key-repeat; strikes one and two are recoverable; strike three immediately regenerates; a correct sequence below three strikes passes. | Implemented and automatically tested on fail and recovery paths. |
| Source mining pack two | Select five more creative tasks that are not character/OCR/reel variations—something completely different, mind-bending, and fun. | Selected physical experimentation, long-horizon consequences, popup/window chaos, an implicit ritual, and continuous arcade navigation. | Implemented as pack two. |
| Build pack two | Build all five and verify/iterate before VNC. | Added five complete benchmark families and end-to-end browser solves. Fresh-seed visual and hit-testing bugs were fixed before handoff. | Implemented and automatically verified. |
| Live pack-two testing | Start spawning the second pack. | Began with Domino Autopsy over VNC. The repeated human run became a deep audit of interaction integrity. | Domino human-tested; the other four still await VNC human tests. |
| Domino: visible red/white contact | Red appeared to touch a white domino but did not transfer the chain. | Found animation/verifier geometry based on crude center-distance thresholds. Tried aligning both with a shared geometric contact rule. | The patch was insufficient and was later superseded. |
| Domino: still broken in VNC | The threshold adjustment did not fix the actual behavior. | Stopped assuming the automated solve represented the user's placement; attempted exact reproduction instead of blind threshold widening. | Important debugging lesson. |
| Domino: orientation symmetry | A domino worked from one side, but a 180° flip failed even though a real domino is equivalent after that flip. | Changed upright-axis handling to modulo 180° and made the automated solve deliberately flip one loose domino by 180°. | Implemented; remains covered in smoke. |
| Domino: pass-through screenshot | Dominoes visibly passed through one another; user correctly inferred that only a strange hack could cause it. | Admitted the implementation was independent CSS rectangles rotated on timers with distance checks—not physics. Deleted the fake fall path and rebuilt with Matter.js. | Superseded architecture; fake animation must never return. |
| Domino: real collisions | Require actual physical behavior, not tuned approximations. | Vendored Matter.js 0.20.0; added finite-mass rigid bodies, gravity, tabletop collision, impulses, contact events, drag/rotate editor, real rest states, and collision-graph grading. | Implemented and browser-verified. |
| Domino: bell did not ring | Asked whether the bell also lacked physics. | Found a second shortcut: a CSS bell over an invisible static sensor. Replaced it with a finite-mass bell body, world pivot constraint, constrained physical clapper, and optional audible chime. Removed the sensor and CSS shake. | Implemented; human confirmed the bell rings. |
| Domino: no visible result | Bell rang, but no obvious pass/fail appeared. | Added a prominent forensic-style `PHYSICS PASS`/`PHYSICS FAIL` stamp, colored footer state, resolution about 1.2 s after a valid strike, and an enabled `CERTIFY PASS →` action. Removed positional motion from the pulsing button after Playwright exposed it as perpetually unstable. | Implemented; screenshot and browser solve verified. |
| Domino: why ring plus fail? | Asked whether falling order was required and explicitly said not to jump into edits. | Explained only. Order is not checked. The current grader requires an undirected connected contact graph containing the designated first domino, every expected domino, and the bell, plus at least 0.03 rad of bell swing. A direct ring can occur despite a skipped domino or weak swing. | No edit requested or made. Preserve this authorization boundary. |
| Durable handoff | Recover pre-compaction history and record every insight/change for the future. | This document. | Implemented. |
| Visual control plane | Build a beautiful, screenshot-rich environment hub inspired by Prime Intellect, with one-click real VNC launch and a future evaluation surface. | Added the Observatory, catalog/dossiers, real session lifecycle, evaluation command preview/run flow, stable polling, responsive views, and screenshot evidence. | Implemented and browser-tested; launches still exercise the real external runner. |
| Full survey browser | Let the user browse the broader mined survey with text, images, videos, artifacts, and source context rather than only seeing Codex's shortlist. | Added a four-layer Survey Atlas: 44 normalized designs, 250 source variants, 1,043 concrete records, and 74 source dossiers—1,411 browseable records backed by 19,168 files. | Implemented; unit and browser smoke coverage present. |
| Harder selection doctrine | Assume a high-IQ, visually sharp, knowledgeable model. Do not rely on logic twists, OCR, classification, or static question answering; beat it with interaction load, active 3D/spatial state, hidden/transient state, and causal probing. | Used this doctrine to select ten Incubator designs with distinct motor, temporal, physics, and navigation bottlenecks. | Permanent design doctrine. |
| Build all Incubator puzzles | Implement all ten Incubator designs in parallel batches of five, give subagents sufficient architecture rules, and verify every batch before accepting it. | Added isolated generator/grader/renderer/solver plugins and full environment folders for all ten, then ran combined fail/regenerate/physical-solve browser gates with server and exported-verifier agreement. | Automatically verified; broad VNC human testing remains pending. |
| Batch-one adversarial review | Do not accept a scripted pass if a structural shortcut, stale challenge, or weak outcome UX remains. | Randomized Wrong Number's true caller away from a fixed final slot, bound Dead Man's Switch and Blind Dice Courier to the current challenge in independent verification, and added prominent persistent verdicts. | Fixed and covered by central tests/evidence. |
| Batch-two adversarial review | Real mechanics need varied worlds and must expose implementation boundaries honestly. | Added four seeded transforms to Tiny FPS after a fixed-map review; found and fixed stale candy/time-wheel failure overlays; documented that the market quote stream is hidden from rendered UI but currently present in browser state. | Fixed where possible; quote transport remains an explicit boundary. |
| Promote historical selections | Finish every queued design rather than leaving increasingly polished concept cards. | Completed historical batches three through five and all twenty Pack III–VI selections, bringing the promotion total to 43 and the dashboard concept/scaffold counts to zero. | All have local browser/server/exported-verifier evidence; human and agent gates remain separate. |
| Build Interaction V | Implement photograph geometry, recorded ghost workers, recursive scale, frozen camera topology, and forced-perspective physical scaling. | Added five ordinary-input spatial worlds and batch-eight evidence, including independent projection/collision replay. | Automatically verified; VNC human calibration pending. |
| Build Interaction VI | Implement active LIDAR, tomography, three-camera teleoperation, deformable cable physics, and portal-frame freight. | Added five geometry-heavy worlds and batch-nine evidence with browser-visible geometry bound to independent server replay. | Automatically verified; VNC human calibration pending. |
| Human acceptance ledger | Add an environment-level approval/revision desk, then audit the early catalog by hand. | The dashboard now stores atomic notes and decision history. Twelve environments were reviewed: six approved and six explicitly rejected for revision. The decisions were preserved as human evidence rather than overwritten by later automation. | Implemented; ledger is authoritative. |
| Quality failure in the newer builds | The newer puzzles ignored the benchmark doctrine: labeled answers, simple OCR/classification, one-click solutions, toy collision checks, and tutorial-like text survived because scripted solvers passed. | Re-read the full transcript and all twelve saved reviews. Classified green automation as wiring evidence only and wrote a binding replacement contract for every rejected mechanic plus three adjacent unreviewed early-catalog mechanics with the same failure pattern. | Root-cause documented in `reviewed-overhaul-v1.md`. |
| Reviewed overhaul v1 | Fix the bad designs from their interaction thesis, including complete replacement where necessary, before asking for another human judgment. | Rebuilt Consequences, Popup, Slime, Semantic Drag-Drop, Reload, and Rotate from the six revision notes; also replaced Signature, Wonky Text, and First Change before they reached the same audit. Added independent replay graders, real failure/regeneration paths, fresh generation, and canonical evidence. | Three full seeds passed 27 negative/solve/server/verifier runs; all nine remain human-review pending. |
| Next-ten principle audit v1 | Audit the next ten personally before asking the human to review, and rebuild anything that is still recognition, logical QA, or arbitrary hidden state. | Rebuilt Apple Grid, Cursor Lens, Modifier Stack, Board Game, and Occlusion Shell around parallax, active polarization, transient physical transforms, continuous tilt physics, and physically inferable peephole tracking; repaired the five retained mechanics and captured three cohorts. | Documented in `next-ten-audit-v1.md`; human later approved seven and judged the other three genuinely difficult rather than broken. |
| Next-ten principle audit v2 | Apply the same recipe to the following ten: isolate clean accepted transcripts, reject VNC/input-density gates, replace weak concepts rather than polishing them, and self-audit before handoff. | Replaced OCR-memory Wrong Number with a drifting analog phase-lock task and text-manual Bomb with three-layer acetate registration; repaired Panorama, Flat-Pack, Hovercar, Art Critic, Dead Man, Blind Dice, and Forklift; retained the delayed market with its browser-state boundary. Expanded Forklift from four physical boards to eight topologies × four transforms and task/geometry-bound the graders. | Three post-repair cohorts passed 30/30; 800 generator seeds, all eight Forklift layouts, and accepted-result tamper checks passed. Documented in `next-ten-audit-v2.md`; human VNC review remains pending. |
| Next-ten difficulty upgrade v3 | Strong concepts are still inadequate when their generators produce tutorial-scale instances: a periodic market, a handful of drawing strokes, short routes, and tiny object counts do not create meaningful interaction debt. | Increased the physical, temporal, and spatial scale of all ten without adding tiny targets or hidden quotas: 32-sector panorama search, seven-part assembly, five moving hover checks, 10–14-stroke art classes, seven drifting carriers, five acetate layers, moving-pad dual control, five hidden-orientation gates, two-crate delayed Sokoban, and a causal-policy-calibrated nonperiodic market. | Canonical and multi-seed browser replay, 80-seed-per-mechanic generator gates, forged-terminal rejection, and visual evidence are documented in `next-ten-difficulty-v3.md`; human VNC difficulty calibration remains pending. |
| Robot Art Critic fidelity boundary | Asked what happens when a model produces a legitimate locomotive with a substantially different design. | Recorded that the current critic is closed-world and prototype-bound: it measures closeness to eight generated structural families, not open-world artistic or semantic validity. A valid alternate design can therefore fail. The task was frozen and was not changed while solution films were being produced. | Known benchmark limitation, now visible in the dashboard dossier and review note. Do not describe this grader as a faithful general art critic. |

## Interaction-first pack one

The source and transformation record is [interaction_first_five_v0.json](../shared_runtime/assets/provenance/interaction_first_five_v0.json). Automated evidence is in [interaction_first_five_v1](../evidence/interaction_first_five_v1/).

| Mechanic | Interaction stressor | Source-grounded transformation | Human evidence and learning |
|---|---|---|---|
| Motion-Only Ghost Jigsaw | Motion-defined perception, temporal correspondence, working memory, repeated dragging. A still frame is deliberately insufficient. | Inspired by NextGen-CAPTCHAs `Spooky_Jigsaw`; rebuilt as procedural opposite-motion grayscale fields with nine shuffled draggable tiles. | Human reaction was exceptionally positive. This is the clearest expression of the benchmark thesis. |
| Cursor Constellation Hunt | Cursor-driven active perception and two-dimensional search with decoy basins. | Inspired by the CAPTCHaStar paper; adds six procedural shape families, false convergence regions, and persistent noise stars. | Human passed after clarification. The yellow ring represents the selected cursor coordinate, not the key's position. Current 28 px acceptance is likely tighter than the visually crisp region and needs calibration. |
| Parallel Grillmaster | Parallel deadlines, monitoring, timed drag/drop, planning, and recovery. | Inspired by Kitboga Code Jam `captcha-cook`; original art and a human-sized timing model use browning/glow/smoke rather than explicit countdowns. | Human found it fun. Preserve visual doneness; do not turn it into timer reading or raw latency measurement. |
| Rotating On-Screen Keyboard | Continuously changing coordinates after every screenshot, visual tracking, and predictive clicking. | Inspired by `RotatingEmail`; rebuilt with a generated five-character target and 3D moving key plane. | Human found it even more fun. Motion must remain smooth enough to track rather than becoming random click failure. |
| Slot-Reel Character Capture | Transient perception coupled to timed keyboard action and persistent sequence state. | Inspired by Not a Robot level 40; rebuilt with five independently timed reels, ordered freezing, and visible recovery. | Human exposed hidden-rejection UX. The visible three-strike contract is now part of the mechanic, and key-repeat events must remain ignored. |

Pack-one automatic verification originally reached three consecutive randomized full browser runs, deliberate failure/regeneration for every task, server pass, exported-verifier score 100, and the then-current project suite. The current evidence summary is [summary.json](../evidence/interaction_first_five_v1/summary.json), and the solve tool is [smoke_interaction_first_five_ui.py](../tools/smoke_interaction_first_five_ui.py).

## Interaction-first pack two

The source and transformation record is [interaction_second_five_v0.json](../shared_runtime/assets/provenance/interaction_second_five_v0.json). Automated evidence is in [interaction_second_five_v1](../evidence/interaction_second_five_v1/).

| Mechanic | Interaction stressor | Implemented form | Validation state |
|---|---|---|---|
| Domino Autopsy | Iterative spatial reasoning, physical prediction, simulation observation, diagnosis, and repair. | Arrange three loose pieces between two fixed runs, start a real Matter.js rigid-body simulation, and create a continuous contact path into a suspended bell. | Extensively human-tested; repeated failures drove the full physics rebuild. Current automatic grade: 12/12 graph nodes, 11 contacts, about 0.63 rad peak swing. |
| Consequences Boss | Long-horizon episodic memory and action conditioned on earlier choices rather than a universal visual answer. | Four visual moral scenes followed later by four boss judgments in a randomized order. | Browser, server, and exported verifier pass 100; no VNC human run recorded yet. |
| Popup Exorcist | Dynamic occlusion, window management, tiny targets, exploration, and discovery of a shortcut. | Randomized overlapping popup stack with one blocker/kill-switch that exposes a purge interaction. | Browser, server, and exported verifier pass 100; no VNC human run recorded yet. |
| Funeral With No Instructions | Affordance discovery, implicit sequence, persistent state, brush coverage, collection, and drag/drop storytelling. | The terse prompt “Grieve” leads through tombstone inspection, moss brushing, candle lighting, flower gathering, and bouquet offering. | Browser, server, and exported verifier pass 100; no VNC human run recorded yet. |
| Slime Commute | Continuous moving-world control while observation and reasoning consume time. | WASD navigation across 11 rows of safe ground, minecarts, water, and moving logs, with four visible wipeouts. | Browser, server, and exported verifier pass 100; no VNC human run recorded yet. |

The current pack-two summary is [summary.json](../evidence/interaction_second_five_v1/summary.json), the solve tool is [smoke_interaction_second_five_ui.py](../tools/smoke_interaction_second_five_ui.py), and the current Domino collision sequence is [domino-physics-contact-sheet.png](../evidence/interaction_second_five_v1/domino-physics-contact-sheet.png).

## Incubator batches one and two

The dashboard's ten explicit Incubator candidates are now real benchmark folders. Their shared source/transformation record is [incubator_puzzles_v1.json](../shared_runtime/assets/provenance/incubator_puzzles_v1.json). No third-party presentation media was copied into these mechanics; the sources seed interaction ideas and all shipped interfaces/art are local transformations.

The implementation uses a deliberately narrow plugin seam rather than adding ten more monolithic branches to the shared runtime:

```text
task mechanic_id
  -> shared_scripts/incubator_generators/<mechanic>.py
  -> shared_runtime/app/mechanics/<mechanic>.js + .css
  -> shared_runtime/server/incubator_graders/<mechanic>.py
  -> exported result + task verifier replay
```

Each generator returns public state and challenge-bound private truth. Each grader reconstructs the outcome from an event/action transcript rather than trusting a client-side `completed` flag. The browser solve tools use normal Playwright mouse/keyboard input and then exercise the live HTTP grade, direct grader, and exported task verifier as separate calls.

### Incubator batch one

Automated evidence is in [incubator_batch_one_v1](../evidence/incubator_batch_one_v1/); the combined runner is [smoke_incubator_batch_one_ui.py](../tools/smoke_incubator_batch_one_ui.py).

| Mechanic | Interaction stressor | Implemented contract | Review lesson |
|---|---|---|---|
| Wrong Number | Live analog comparison, two-axis tuning, and sustained closed-loop correction. | Seven caller carriers can be patched into an oscilloscope. Only one can be phase/shape aligned with the reference and continuously corrected through a drifting 4.8-second trial and final lock window. | The old disappearing-number OCR/memory task violated the benchmark thesis. The replacement grades the live signal replay, not caller text or an exploration quota. |
| Bomb Manual From Hell | Multi-layer spatial registration, transparency reasoning, and irreversible selection. | Five physical acetate plates must be dragged, rotated in 45° steps, flipped, and seated on asymmetric pins. Their 25 apertures intersect at exactly one of nine cuttable wires. | The old text-manual arithmetic task was question answering. The replacement binds rendered, hit-tested, and independently replayed plate geometry, and normal sparse drag delivery is never rejected. |
| Dead Man's Switch | Genuine simultaneous moving-pointer tracking and ordered keyboard navigation. | A deterministic moving pressure pad must remain tracked while the other hand executes a 45–57 move route through five alternating checkpoint barriers. Stale or out-of-pad samples reset progress. | Continuous-state mechanics need explicit challenge binding and a large verdict. A tiny footer can make a correct human run look unresolved. |
| Blind Dice Courier | Hidden 3D orientation, sequential state transitions, sparse observation, and route planning. | Every move rolls a labelled die across an 18×11 warehouse; only four scanner tiles reveal orientation, and five barriers test top faces over a 53–68 roll solution. | Replay the orientation algebra and route against current challenge truth. Do not trust reported faces or a terminal `delivered` bit. |
| Input-Lag Forklift | Delayed control, queue-state reasoning, collision, and Sokoban planning. | Every direction executes the previously queued direction; a final EXECUTE QUEUE flushes the last command while a real grid engine handles two crates and two docks across twelve layouts and four spatial transforms. | The delay must wrap a coherent world model with visible input/execution telemetry; arbitrary dropped inputs or palette-only “variation” would only test flakiness or leak a reusable route. |

### Incubator batch two

Automated evidence is in [incubator_batch_two_v1](../evidence/incubator_batch_two_v1/); the combined runner is [smoke_incubator_batch_two_ui.py](../tools/smoke_incubator_batch_two_ui.py).

| Mechanic | Interaction stressor | Implemented contract | Review lesson |
|---|---|---|---|
| Insider Trading CAPTCHA | Live observation, delayed action consequences, inventory management, and closing a position under time pressure. | A nonperiodic 34–38 tick regime tape settles every order three ticks later, charges a fixed fee, enforces a four-lot limit, and admits only causal-policy-solvable targets of at least 1,100¢. | The ledger must be exactly replayable. Future prices are not rendered before their ticks, but the current static plugin seam still places them in browser state; see the boundary below. |
| Polyrhythm Customs | One-at-a-time temporal inspection, working memory, chord timing, and real key holds/releases. | Three A/S/D lanes are previewed separately and then hidden for one combined performance containing taps, a hold, and a chord with humane timing tolerances. | A timing puzzle should verify keydown and keyup duration, tolerate VNC-scale latency, and avoid confusing audio transport with authoritative state. |
| Exact-Change Candy Cascade | Causal simulation, two-step planning, deterministic cascades, and exact-score control. | A real 5×5 adjacent-swap match-three engine performs simultaneous removal, gravity/refill, wave multipliers, and exactly two swaps; moving black licorice is immediately terminal. | The generator searches solver-audited boards with a two-swap target and a multi-wave cascade. Invalid swaps restore the board, and retry must clear stale FAIL state. |
| Tiny FPS Customs | Active 3D navigation, visual identity matching, collision-aware aiming, and irreversible protected-target avoidance. | A ray-cast maze has real circle-wall collision and nearest-unobstructed ray hits; three warrants must be shot while three close visual decoys survive. | A fixed maze would leak a reusable action script. Four seeded transforms—identity, both mirrors, and 180° rotation—are now required and centrally tested. |
| Thirty-Year Time Wheel | Angular dragging, calendar arithmetic, release velocity, inertia, braking, and coordinated multi-ring state. | Three concentric rings control day/month/year with real month lengths, leap years, clamping, detents, decaying momentum, an effective brake, and an exact final lock. | The grader requires all three rings, at least one coast detent, and a brake that actually catches motion. Static value assignment is not a physical solve. |

### Incubator batch verification lessons

- A generated challenge can still leak a cheap strategy through stable ordering or a fixed world layout. Test structural variation, not only different challenge IDs.
- Every result must bind to the current `challenge_id`; stale results are a first-class negative test in both browser and unit gates.
- PASS/FAIL must be visually dominant, persistent long enough to inspect, and cleared when a fresh attempt begins.
- Solvers must drive pointer drags, holds, keydown/keyup, collisions, delayed queues, inertia, and clocks through ordinary input. Direct DOM state mutation would validate only the grader fixture.
- Screenshot sets need initial, active, failure/regeneration, solved/pre-submit, and final verdict frames. Active frames exposed bugs that start/end screenshots hid.
- Visual variation, interaction variation, and answer variation are separate requirements. A new palette is not a new navigation problem.
- The ten mechanics are automated browser candidates, not human-approved VNC tasks and not proven agent discriminators.

### Honest market-stream boundary

The shared browser plugin contract currently loads one static public-state document and has no per-tick server endpoint. Insider Trading therefore receives `runtime_price_stream_cents` in browser JavaScript state so its local clock can reveal quotes over time. The UI never renders or inserts a future quote into the DOM before its tick, so an ordinary screenshot/mouse/keyboard agent cannot observe it. A browser-internals or network-capable agent could inspect it. True secrecy for that threat model requires a central authenticated streaming endpoint and should be implemented before claiming the task resists agents with page-state or network access.

## Historical selections and Interaction III–VI

The 43 completed historical selections comprise Incubator batches one through five plus the twenty Pack III–VI mechanics. Evidence summaries are stored in `evidence/incubator_batch_one_v1/` through `evidence/incubator_batch_nine_v1/`; batch eight is Interaction V and batch nine is Interaction VI. Every summary requires an ordinary-input browser solve, live server grade, direct independent grade, exported task verifier, console-error check, and screenshots. This promotion history does not place any task in the still-empty `verified` split.

| Evidence batch | Built mechanics | Dominant interaction debt |
|---|---|---|
| Three | Code-to-Diagram, Vim Escape, Fake Desktop Inversion, Impossible Ecology, Jigsaw Slider | Tool-state discovery, hostile UI semantics, compositional construction, and sequential manipulation. |
| Four | Microgame Gauntlet, Minecraft Block Grid, Relation Prompt Grounding, Rorschach Rubric, Split Boxes | Rapid mode switching, 3D block placement, relational grounding, fixed-rubric ambiguity, and one-scene spatial partitioning. |
| Five | Top-Face Dice Arithmetic, Trace Without Walls, Wizard Critter Capture | Tracked 3D orientation, continuous pointer trajectories, and lure/freeze/capture timing. |
| Six / Interaction III | Shadow Crime Lab, CRAFTCHA, Occlusion Shell Swindle, Ribbon Switchboard, Magnetic-Stripe Purgatory | Causal probing, long-horizon crafting, object permanence, woven depth tracing, and motor calibration. |
| Seven / Interaction IV | Trajectory Catcher, Impossible Panorama, Flat-Pack Compliance, Crash-Deadline Hovercar, Robot Art Critic | Prediction, pan/zoom/focus, physical assembly, divided attention, and iterative drawing feedback. |
| Eight / Interaction V | Photograph Eats the Room, Clockwork Doppelgänger Customs, Recursive Dollhouse Smuggling, Flat Prisoner, Forced-Perspective Moving Day | Reality editing, concurrent recorded selves, cross-scale transforms, camera topology, and projected physical scale. |
| Nine / Interaction VI | LIDAR Blacksite, Tomographic Baggage Surgery, Three-Camera Claw Machine, Zero-G Cable Autopsy, Portal Freight | Active sensing, volumetric reconstruction, multi-view teleoperation, deformable topology, and portal-frame transforms. |

### Cross-batch implementation lessons

- **Floating-point rules need an explicit contract.** Cross-language graders compare rounded visible measurements with finite checks and small stated tolerances; they do not require impossible bitwise equality. Tolerance must cover representation error, not widen a wrong physical answer into a pass.
- **JavaScript `%` is remainder, not mathematical modulo.** LIDAR Blacksite, Flat-Pack Compliance, and Microgame Gauntlet all needed canonical double-modulo angle normalization: `((x % period) + period) % period`. Negative headings otherwise escaped the browser's canonical range while Python replay wrapped them correctly. All three browser paths were rerun after the fix.
- **Screenshots perturb realtime systems.** Capturing a frame can delay timers, recording loops, animation frames, and key-release scheduling. Never take authoritative timed evidence in the middle of a solve unless the mechanic explicitly tolerates that delay. Clockwork uses a deliberately discarded dense recording for its active screenshot; accepted recordings remain uncontaminated.
- **Sparse pointer delivery and stalls are part of VNC fairness.** Drag/hold mechanics must handle sparse `pointermove` samples by resampling physical segments, retaining pointer capture, and exposing a visible recovery state. A solver or human should release a held movement key after no progress, back out physically, and re-aim—not grind against a wall while a long timeout accumulates fake collision ticks.
- **Collision must be symmetric unless the material says otherwise.** Domino flips, flat-pack joints, cable contacts, crate walls, and portal freight cannot work only from the scripted approach direction. Contact graphs and separating-axis/circle/AABB rules are undirected; front/back symmetry is an adversarial test.
- **Projection math must be real and shared conceptually.** Camera rays, frusta, perspective divide, screen-space overlap, depth order, and portal coordinate transforms must describe what the screenshot shows. The browser and grader implement those equations independently; screenshot coordinates are never accepted as an unexplained answer token.
- **Visible geometry is physics geometry.** A wall, bell, crate, cable, projected platform, portal, or occluder may not be decoration over a different hidden collider. The renderer, pointer hitbox, local collision, and server replay must refer to the same generated object identity and bounds.
- **Coordinate origins are part of visible geometry.** Slime Commute stored a player as a cell index and rendered its center at `x + 0.5`, while both browser collision and independent replay compared hazards against `x`. Their mutual agreement concealed a half-cell/40-pixel phantom-hit bug. Collision now uses the rendered center, the visible 44 px body equals the replay radius, an impact freezes on the exact contact frame, and the browser smoke rejects any recorded road collision whose two rendered bounding boxes do not touch.
- **A perfect solve must not be forced to make mistakes.** Deliberate fail/regenerate evidence is a separate attempt. The passing transcript must not be required to collide, incur a strike, rewind, or trigger a local failure merely because the smoke once did so for coverage. Mistakes may be allowed and tested; they are not proof of human behavior.
- **Failure must dominate, then become genuinely fresh.** Show an unmistakable terminal FAIL scene, generate a new challenge where intended, and clear the stale failure styling/readout before the next action. A fresh room that still says FAIL is not fresh.
- **Sample corridors, not waypoints.** LIDAR originally proved only that exact route points were clear; a chamber crate left exactly one player radius at the point but pinched the next turn after a normal 0.02-unit approach offset. The generator now samples every route segment with a human drift reserve and audits turn rings from both approaches.
- **Bind every visible measurement to replay.** LIDAR scan events record the complete rounded nearest-return fan—ray index, surface identity/kind, distance, and world point—and the server recomputes it. Fabricated far surfaces, dropped returns, wrong IDs, and moved world coordinates are rejected.
- **Public render state is not private truth.** A browser can legitimately receive walls, cameras, meshes, and object volumes it must display. It must not receive hidden routes or solver plans, and the grader must not trust browser-reported completion. If the threat model includes page-state inspection, move time-sensitive secrets to an authenticated streaming endpoint rather than pretending bundled JavaScript is secret.
- **Executable hook bits are part of the benchmark contract.** Magnetic-Stripe Purgatory's four runtime/task shell hooks existed with correct contents but lacked execute permission, so a source-only review missed a real launch seam. All 260 environment/task hook scripts are now asserted executable in the central benchmark tests.

## Changes found through verification rather than the initial designs

The user requested screenshot evidence, iteration, and high confidence before VNC. Satisfying that request required these additional changes:

- Cleared stale `FAIL` labels on the next meaningful action so a regenerated challenge does not look already failed.
- Tightened the Slot-Reel automated action to operate near the start of a character window rather than at a boundary.
- Fixed Funeral hit testing where a decorative hill stole the bouquet drag.
- Kept the Funeral flower “breathing” glow but stopped moving its clickable hitbox forever.
- Disabled unlit flower hitboxes so a procedurally placed flower could not steal the initial tombstone click.
- Generated flowers in four separated jittered patches so two flowers could not overlap perfectly.
- Added the narrow CLI compatibility fallback needed by older test namespaces that do not contain `args.benchmark`.
- Re-ran complete packs from the beginning after bugs instead of resuming after the failing mechanic.
- Used fresh procedural seeds to expose occlusion bugs hidden by lucky layouts.
- Captured active/mid-action screenshots, not just initial and final frames.

These are not incidental polish items. They define the difference between intentional interaction difficulty and accidental UI failure.

## Domino Autopsy: the full technical lesson

Domino Autopsy is the strongest warning in this history because several automated green runs coexisted with a fundamentally dishonest interaction model.

### Architecture that was rejected

The first implementation used:

- CSS rectangles;
- timer-driven rotations;
- center-distance contact thresholds;
- separate animation and verifier geometry;
- a directed angle check that treated 0° and 180° as different upright states;
- a visual CSS bell layered over an invisible sensor.

This produced every failure the human tester reported: visible contact without transfer, one-sided behavior, intersections, pass-through, and a bell that did not visibly respond.

Threshold widening and modulo-angle fixes could make tests pass, but they could not make the underlying simulation real. The correct response was architectural replacement, not another tolerance.

### Current rigid-body implementation

The current runtime in [app.js](../shared_runtime/app/app.js) uses vendored Matter.js 0.20.0:

- Each domino is a finite-mass `14 × 72` rigid rectangle.
- Bodies are created dynamic first so mass and inertia are finite, then frozen with `Body.setStatic(true)` only during editing.
- Starting with permanently static bodies was rejected because later activation retained infinite mass/inertia and produced `NaN` after an impulse.
- The 14:72 aspect ratio replaced chunky 24:72 blocks that jammed and dissipated momentum.
- Gravity, friction, contact impulses, a physical tabletop, velocity, and angular velocity are engine state—not animation guesses.
- The editor supports drag, ±15° rotation, 180° flip, rewind, and rerun.
- The smoke solve deliberately flips one colored piece 180° to preserve physical symmetry coverage.
- Contact events create the submitted collision graph.
- The bell is a finite-mass trapezoid attached to a world pivot.
- The clapper is a separate finite-mass circle attached by a constraint.
- The visual bell is drawn from those bodies' actual positions and angles.
- No `bell-sensor`, CSS bell, or CSS fall animation remains.
- An optional Web Audio chime is triggered by physical bell contact, but visible motion—not VNC audio—is the reliable evidence.

### Current pass semantics

The generator, live server, and exported verifier agree on these conditions:

1. Every loose piece has a valid recorded pre-run placement.
2. The run identifies `matter-js@0.20.0` as its engine.
3. The simulation completes.
4. A domino physically contacts the bell body.
5. The peak bell swing is at least `0.03` radians.
6. The undirected graph of recorded domino/domino and domino/bell contacts connects the designated first domino, all 11 domino bodies, and the bell.

Fall order is not checked. Direction is not checked. A bizarre but physically valid cascade can pass. A ring alone is insufficient because it proves only a bell contact, not participation by every expected domino.

### Current result feedback

After a connected bell strike, the simulation waits about 1.2 seconds to measure swing, then shows a prominent `PHYSICS PASS` or `PHYSICS FAIL` stamp. A passing run enables `CERTIFY PASS →`, which performs the server submission. The button's emphasis changes brightness/shadow but does not move; a one-pixel positional pulse was removed because it made the target perpetually unstable to Playwright and potentially annoying to humans.

## What future self must remember when inventing puzzles

### 1. Optimize for interaction debt, not recognition difficulty

A modern VLM can often solve static object recognition, OCR, ordinary grids, and semantic selection. Stronger candidates force the agent to pay for interaction:

- information exists only across frames;
- the cursor changes what can be perceived;
- action coordinates become stale;
- several deadlines run simultaneously;
- previous decisions matter much later;
- the world continues moving during observation/reasoning;
- success requires revising a state after seeing a failed simulation;
- a tool must be manipulated over a region rather than clicked once;
- the visible interface becomes occluded or reordered;
- a task's affordances must be discovered from sparse narrative context.

The most valuable puzzle is not necessarily visually obscure. It may be visually obvious but operationally expensive for a screenshot/action loop.

### 2. Weird, annoying, and fun must still be fair

Legitimate difficulty comes from the mechanic. Illegitimate difficulty comes from implementation defects.

Required fairness rules:

- Human timing windows must tolerate VNC and ordinary input latency.
- If a mistake matters later, surface it now or fail immediately. Never silently reject a board that looks solved.
- The visually successful region and verifier acceptance region must agree.
- Visible geometry, clickable geometry, collision geometry, and grading geometry must describe the same object.
- Decorative motion must not move a hitbox unless tracking that motion is the intended task.
- Procedural variation must not introduce impossible overlap, z-order theft, or occlusion.
- Recovery should be possible when diagnosis and retry are part of the intended skill.
- An instruction can be terse or implicit, but the scene must expose coherent affordances.

### 3. Never simulate a mechanic with presentation hacks

If the task claims physics, use physics. If it claims continuous motion, drive the state continuously. If it claims memory, preserve real earlier state. If it claims occlusion, use the same windows the user manipulates.

Specific prohibited shortcuts learned here:

- CSS timers presented as collision physics;
- distance thresholds presented as contact impulses;
- invisible sensors underneath unrelated visible objects;
- separate geometry for rendering and grading;
- special-casing the scripted solver's coordinates;
- hidden state injection in the success playthrough;
- acceptance thresholds widened until a fake interaction happens to pass.

The automated solver may know the generated truth for testing, but it must perform the same ordinary browser inputs as a real user.

### 4. Respect physical and semantic invariants

Before grading an orientation, ordering, direction, or transformation, ask whether the real object makes that distinction.

Examples:

- A rectangular domino's standing axis is modulo 180°.
- A physical collision works from either face unless material properties genuinely differ.
- The current Domino contact graph is undirected and does not enforce fall order.
- A selection marker may be spatially separate from the object it causes to emerge, but that relationship must be legible.
- A moral-memory task must condition later answers on the user's actual earlier choices; it must not have one universal answer.

### 5. Use diverse failure modes across a pack

Do not ship five skins of the same interaction. The first two packs deliberately span:

- motion-only perception;
- cursor-mediated active vision;
- parallel timing;
- moving coordinate frames;
- transient timed typing;
- physical experimentation;
- long-horizon episodic memory;
- dynamic occlusion and window management;
- implicit ritual discovery;
- realtime navigation in a moving world.

When proposing another pack, first name its interaction bottleneck. Reject it if that bottleneck already dominates an existing task without a substantial new control loop.

### 6. Source mechanics, not copyrighted presentation

The collection is an idea mine. Preserve exact provenance, but recreate the benchmark version from first principles with original procedural visuals and an independently designed interaction contract. Record:

- the source artifact;
- the mechanic taken from it;
- the new transformation;
- the assets used or generated;
- any third-party runtime and its license.

The current manifests are [pack one provenance](../shared_runtime/assets/provenance/interaction_first_five_v0.json) and [pack two provenance](../shared_runtime/assets/provenance/interaction_second_five_v0.json). Matter.js's MIT license is stored beside the vendored runtime.

## What future self must remember when implementing puzzles

### Shared contract

Each real mechanic needs all of the following, wired through the benchmark rather than left as a demo:

- an environment and task entry;
- a deterministic seeded generator with meaningful variation;
- public render state and separate hidden grading state;
- a shared browser renderer using normal mouse/keyboard input;
- failure and fresh-challenge behavior;
- live server grading;
- result export;
- an independent task verifier returning `passed`, `score`, and `feedback`;
- provenance;
- automated browser evidence;
- eventual real-runner and human/agent evidence.

Generator, UI, server, and verifier semantics must be changed together. A test that exercises only one copy of a rule is not enough.

### State and feedback

- Clear stale result labels when a new attempt begins.
- Ignore operating-system key-repeat when one physical press should count once.
- Keep state transitions visible enough for humans to understand whether an action registered.
- Show a clear terminal `PASS` or `FAIL` during development and human calibration.
- Keep final certification distinct when the live server still needs a submission.
- Do not let a decorative effect make the next action target unstable.
- Do not expose hidden answers, semantic IDs, masks, or developer telemetry on the normal agent surface.

### Procedural layout

Test more than one lucky seed. For every movable or clickable object, audit:

- overlap;
- clipping;
- z-index and pointer-event ownership;
- minimum target size;
- reachable drag path;
- state-dependent actionability;
- motion during the click window;
- correspondence between visible and actual bounds.

## What future self must remember when verifying puzzles

### Automated checks are necessary but not sufficient

The minimum automatic loop is:

1. Syntax/schema/static checks.
2. A deliberate invalid attempt.
3. Proof that failure regenerates a fresh challenge where intended.
4. A success playthrough through real Playwright mouse/keyboard actions.
5. Live server pass.
6. Independent exported-verifier score 100.
7. Browser console/page-error check.
8. Screenshots at initial, active, failure-refresh, pre-submit solved, and pass states.
9. Repetition across fresh seeds.
10. The canonical project suite: `python -m pytest tests -q`.

Do not preserve an old pass count as if it described the final 65-folder tree. Run and report the repository-prescribed `python -m pytest tests -q` scope after all environment and evidence files are present. A bare repository-wide `pytest` also collects an unrelated CUA-World script that calls `sys.exit(0)` during collection.

### Live testing is a separate gate

The human repeatedly found defects after all automatic checks passed. Therefore:

- Boot the actual AVF environment.
- Use a stable external VNC viewer when the built-in client has flaky input; viewer choice is not evidence.
- Report the runner-published forwarded address and password rather than guessing ports.
- Confirm the browser is rendered before handoff.
- Preserve guest state when merely switching VNC clients.
- Restart the guest after runtime code changes; do not assume a live VM picked up host edits.
- Shut down old guests, SSH tunnels, and viewers narrowly so stale sessions are not mistaken for the new build.
- Ask the human what felt confusing, unfair, flaky, or unexpectedly delightful.
- Treat screenshots of pass-through, occlusion, or mismatch as architectural evidence.

### Test adversarial invariants, not just the intended solution

Examples from this execution:

- Flip one domino by 180°.
- Start with one visible Slot-Reel strike and still pass.
- Trigger three strikes and require immediate regeneration.
- Exercise false constellation basins before the real basin.
- Capture motion across several frames, not one still.
- Run fresh Funeral seeds until z-order and overlap edge cases appear.
- Capture a Domino mid-run frame that can reveal intersections.
- Assert the bell is dynamic, finite-mass, non-sensor, and constrained.
- Require measurable bell swing rather than trusting a CSS class or sound.

### Keep a shared dashboard local-execution only

The collaboration surface may be hosted, but the environments must not silently become hosted demos. The durable boundary is:

- publish the built catalog and its dashboard media as static files;
- exclude the mined Survey archive from the product export rather than deleting the source research;
- run every built puzzle, review write, evaluation, and VNC session through an authenticated companion bound to loopback on the collaborator's own computer;
- make the real localhost browser task the one-click default, while retaining VNC for runner-faithful inspection;
- keep review, evaluation, password, path, and administrative controls visible to paired collaborators, as explicitly requested;
- pair by exact dashboard origin plus a persistent local token, account for the browser's Local Network Access permission prompt, and retain legacy private-network preflight compatibility rather than assuming localhost fetches work;
- verify the whole static-host → pairing UI → companion → generated task → local browser → teardown chain with ordinary browser actions.

A static “Try now” button that executes on the host violates this boundary. A button that asks the paired local companion to launch the actual task satisfies it.

## Human validation status as of this record

| Mechanic | Automated end-to-end | Human VNC evidence in this thread | Important note |
|---|---:|---:|---|
| Motion-Only Ghost Jigsaw | Yes | Yes | Strong positive reaction; no agent trial yet. |
| Cursor Constellation Hunt | Yes | Yes | Passed, but marker meaning and tolerance alignment were confusing. |
| Parallel Grillmaster | Yes | Yes | Positive reaction. |
| Rotating On-Screen Keyboard | Yes | Yes | Very positive reaction. |
| Slot-Reel Character Capture | Yes | Yes, pre-fix issue found | Three-strike fix automatically verified; no explicit post-fix user verdict is preserved. |
| Domino Autopsy | Yes | Yes, extensively | User drove contact, symmetry, real-physics, physical-bell, and result-feedback corrections. |
| Consequences Boss | Yes | No | Still needs VNC human testing. |
| Popup Exorcist | Yes | No | Still needs VNC human testing. |
| Funeral With No Instructions | Yes | No | Still needs VNC human testing. |
| Slime Commute | Yes | No | Still needs VNC human testing. |
| Wrong Number | Yes | No | Batch-wide browser evidence passed; VNC human calibration is pending. |
| Bomb Manual From Hell | Yes | No | Batch-wide browser evidence passed; manual legibility over VNC is pending. |
| Dead Man's Switch | Yes | No | Physical pointer-hold/keyboard solve passed locally; VNC simultaneous-input behavior is pending. |
| Blind Dice Courier | Yes | No | Orientation and gate replay passed locally; human spatial legibility is pending. |
| Input-Lag Forklift | Yes | No | Queue/collision replay passed locally; human delay-model legibility is pending. |
| Insider Trading CAPTCHA | Yes | No | Delayed-order browser solve passed; human timing calibration and the stream-secrecy boundary remain. |
| Polyrhythm Customs | Yes | No | Real keydown/keyup solve passed; VNC timing and optional audio experience are pending. |
| Exact-Change Candy Cascade | Yes | No | Real drag/cascade solve passed; human exact-score planning is pending. |
| Tiny FPS Customs | Yes | No | Collision/navigation/shooting passed across four layouts; VNC control feel is pending. |
| Thirty-Year Time Wheel | Yes | No | Physical drag/coast/brake/lock passed locally; VNC inertia feel is pending. |
| Historical batches three through five (13 mechanics) | Yes | No aggregate claim | Batch summaries prove scripted browser/server/verifier paths; individual human calibration remains to be recorded. |
| Interaction III (5 mechanics) | Yes | No aggregate claim | Batch-six evidence is complete; causal probing and motor-calibration fairness still need human runs. |
| Interaction IV (5 mechanics) | Yes | No aggregate claim | Batch-seven evidence is complete; realtime prediction/assembly controls still need human runs. |
| Interaction V (5 mechanics) | Yes | No aggregate claim | Batch-eight evidence is complete; spatial projection and concurrent-loop legibility still need human runs. |
| Interaction VI (5 mechanics) | Yes | No aggregate claim | Batch-nine evidence is complete; 3D sensing, multi-camera, cable, and portal controls still need human runs. |

“Automated end-to-end” here means local browser interaction plus server and exported-verifier success. It does not mean benchmark-ready and does not predict agent failure.

## Open issues and honest boundaries

1. **No actual computer-use-agent evaluation has been completed for the final built corpus.** Human delight and scripted difficulty are hypotheses, not benchmark results.
2. **The verified surface must remain empty until the documented quality gate is met.** Do not promote tasks based on local Playwright success.
3. **Constellation calibration remains suspect.** Its shape can look complete over a broader region than the 28 px acceptance radius. Align perception and grading before promotion.
4. **Human VNC coverage remains sparse.** Twelve environments now have explicit human decisions in the review ledger: six approved and six revision-requested. The six rejected designs were rebuilt but remain rejected until the user retests them; automation cannot clear that status. The other 51 built designs still need calibration through the real runner. Automated AVF screenshots do not count as direct human evidence.
5. **Development feedback and benchmark feedback are in tension.** The current Domino UI shows swing degrees and “rewind and repair,” while [benchmark-quality-gate-v0.md](benchmark-quality-gate-v0.md) requires terse final surfaces without explanations or next-step hints. Keep the clarity during human calibration, then decide what belongs behind a development mode before promotion.
6. **A bell ring is not synonymous with a Domino pass.** The current contract intentionally requires every expected domino in one connected graph and sufficient swing. If that contract feels unintuitive in more human tests, revisit the task specification first; do not silently loosen the verifier.
7. **VNC audio is not reliable evidence.** The physical bell's visible body motion and engine telemetry are authoritative; audio transport may be absent.
8. **The benchmark is still a candidate corpus.** It has strong mechanics and evidence, but it has not yet shown comparative failure rates, human solve rates, completion times, or model-discriminating power.
9. **The market tape is UI-hidden, not browser-state secret.** Future quotes remain inaccessible to screenshot-only agents but are present in the loaded browser state until a streaming server contract is added.

## Definition of done for the next puzzle

Do not call another mechanic ready until all boxes are true:

- [ ] Its answer cannot be cheaply recovered from one good screenshot.
- [ ] Its interaction bottleneck is distinct from the existing built corpus.
- [ ] A human can infer the intended affordances without tutorial prose.
- [ ] Difficulty comes from the mechanic, not latency, tiny targets, occlusion bugs, hidden mistakes, or mismatched geometry.
- [ ] The source and transformation are recorded.
- [ ] The generator produces varied, reachable, non-overlapping instances.
- [ ] UI, live server, and exported verifier implement one coherent contract.
- [ ] The invalid/retry path works and clears stale state.
- [ ] A browser solves it using ordinary inputs across multiple fresh seeds.
- [ ] Mid-interaction screenshots make cheating, intersections, and misleading state visible.
- [ ] The canonical `tests/` suite passes.
- [ ] The real runner/VNC task has been manually tried.
- [ ] At least one edge-case strategy—not just the golden path—has been tried.
- [ ] The task remains outside `verified` until real-runner evidence and the strict audit pass.
- [ ] Claims about agent difficulty wait for actual agent evaluations.

## The message to future self

> Do not build another polished recognition toy. Start from an interaction weakness. Make the strange behavior real, not animated theater. Keep every visible affordance aligned with its hitbox, physics, and verifier. Calibrate for humans through the actual VNC surface. Treat every hidden rejection and every “but I can see them touching” report as a design failure until proven otherwise. A green test suite proves the harness; a human run proves usability; only real computer-use-agent experiments prove benchmark value.
