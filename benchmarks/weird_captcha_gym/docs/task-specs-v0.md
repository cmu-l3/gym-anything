# Task Specs v0

Date: 2026-07-08

This expands the 25 frozen mechanics into implementation-facing task specs under `architecture-v0.md`.

These specs assume one shared environment, one shared computer-use action surface, screenshot observations, runtime puzzle generation, hidden ground truth, and outcome-first verification. They are not claims about current CUA failure rates.

## Common Spec Rules

- Each mechanic is a task setup inside `weird_captcha_gym@v0`.
- A normal benchmark run should receive a fresh generated episode. Developer seeds may exist for debugging, but fixed repeated questions should not be the default evaluation mode.
- The agent sees only the screen and public instruction.
- The verifier sees private generated ground truth.
- The score should normally be binary pass/fail. Partial fields can be logged for analysis but should not become the headline benchmark metric without a later design decision.
- Timing constraints must be generous enough that failures reflect puzzle solving and interaction, not arbitrary runner latency.

## 1. `reverse_identity_gate`

### Source Anchors

`willardpeng-im-not-a-robot`, `josi-jami-i-am-not-a-robot`, `zachshirikjian-are-you-human`

### Instruction Templates

- "Prove you are a robot."
- "Only robots may continue. Select the evidence that you are automated."
- "This gate rejects humans. Complete the robot identity check."

### Generator Contract

Generate an identity-check panel with deliberately inverted copy. Variants include mutually exclusive identity buttons, fake reCAPTCHA-style checkbox labels, behavioral proof questions, timing traps, and small binary forms where the normal "human" answer is wrong.

Difficulty knobs: number of decoys, wording ambiguity, trap-button count, delayed reveal of the accepted option, and whether the accepted answer is a single click or short form submission.

### Public State

A verification widget with labels, buttons, checkboxes, and optional short input field. The UI should look familiar enough to trigger CAPTCHA priors, but the visible text must contain enough information to solve the inversion.

### Private Ground Truth

Accepted identity mode, accepted widget id, rejected widget ids, accepted typed string if present, and final success state id.

### Verifier Contract

Pass if the final widget state is accepted. Reject states caused by selecting a human-labelled option, submitting contradictory evidence, or timing out. Do not require a particular sequence if multiple UI paths reach the same accepted state.

### Timeouts

20-40 steps, 30-60 seconds.

### Failure Modes Targeted

Default CAPTCHA priors, superficial label matching, failure to read negation, and premature clicking.

### Evidence Required

`start.png`, `ground_truth.json`, `final.png` for at least one solved generated instance, plus a screenshot showing at least one rejected trap state during audit.

## 2. `moving_checkbox_evasive_button`

### Source Anchors

`github-nicholasdejesse-captcha-game`, `neal-im-not-a-robot`, `captcha-hell`

### Instruction Templates

- "Check the box."
- "Click verify without touching the decoys."
- "Confirm the moving checkbox."

### Generator Contract

Generate a checkbox or verify button with deterministic movement. Variants include hover-evasion, sinusoidal drift, snap-away zones, shrinking targets, delayed target activation, and decoy boxes that look plausible but never verify.

Difficulty knobs: target size, speed, avoidance radius, number of decoys, safe-window duration, and whether the target pauses periodically.

### Public State

A compact verification panel with one active target and optional decoys. Animation should be smooth and deterministic from seed.

### Private Ground Truth

Target element id, active hitboxes as a function of time, movement parameters, decoy ids, and success transition.

### Verifier Contract

Pass if the target element reaches checked or verified state. A click on a decoy may either do nothing or trigger a visible failure state, but scoring is still based on final accepted state.

### Timeouts

40-80 steps, 45-90 seconds.

### Failure Modes Targeted

Dynamic localization, cursor movement planning, reacting to hover state changes, and distinguishing active from decorative controls.

### Evidence Required

`start.png`, sampled trajectory JSON for the target path, `video.mp4` or frame sequence, `ground_truth.json`, and solved final state.

## 3. `code_to_diagram_captcha`

### Source Anchors

`2020-cfgcaptcha`, `kitboga-codejam25`

### Instruction Templates

- "Select the diagram that matches this code."
- "Which control-flow graph is produced by the program?"
- "Pick the output trace for the snippet."

### Generator Contract

Generate a small pseudo-code program from templates: if/else, bounded loops, boolean branches, variable updates, and early exits. Render the code plus 3-5 diagram or trace choices. Distractors should contain one semantic mutation, such as swapped branch direction, missing loop edge, wrong terminal output, or off-by-one iteration.

Difficulty knobs: number of branches, loop depth, variable naming, diagram density, and whether answer choices are diagrams, traces, or outputs.

### Public State

A code panel and selectable answer panels. Text must be legible in screenshots at the target viewport size.

### Private Ground Truth

Program AST, evaluated trace, correct choice id, distractor mutation metadata, and answer panel bounding boxes.

### Verifier Contract

Pass if the selected choice id equals the generated semantic answer. For drag/drop variants, pass if the chosen diagram is placed into the answer slot.

### Timeouts

60-140 steps, 2-4 minutes.

### Failure Modes Targeted

Reading code from images, symbolic execution, diagram comparison, and exact answer selection.

### Evidence Required

Rendered code screenshot, `ground_truth.json` with AST and evaluated trace, all answer panel images, and one known-solved example.

## 4. `wonky_text_hostile_rendering`

### Source Anchors

`modrinth-evil-captcha`, `perceptual-gaps-ascii-audio`, `captcha-hell`

### Instruction Templates

- "Enter the warped word."
- "Type only the characters hidden in the noisy strip."
- "Ignore the decoys and submit the verification token."

### Generator Contract

Generate a short answer token and render it with layered text effects: split glyphs, occluders, offset shadows, mirrored fragments, fake carets, background labels, and irrelevant visible words. The token should remain human-readable in audit screenshots.

Difficulty knobs: token length, character set, font distortion, occlusion strength, decoy word count, and input-field hostility.

### Public State

A noisy text image, a text field, and submit button. The input field may visually mislead with fake cursor placement, but typing must be functional and deterministic.

### Private Ground Truth

Canonical token, accepted normalized variants if any, decoy strings, render parameters, and submit field id.

### Verifier Contract

Pass if submitted text matches the canonical token after configured normalization. Reject if the submitted value matches a decoy or omits required characters.

### Timeouts

40-80 steps, 60-120 seconds.

### Failure Modes Targeted

OCR under clutter, distinguishing answer text from UI text, field focus, and precise typing.

### Evidence Required

Token render image, `ground_truth.json`, start and solved screenshots, and an audit note confirming the token is visually recoverable.

## 5. `relation_prompt_grounding`

### Source Anchors

`logic-captcha-media-examples-2024`, `visual-reasoning-captcha-vtt`, `arkose-funcaptcha-internals-crawlex`

### Instruction Templates

- "Click the red object in front of the object that appears once."
- "Select the small shape left of the only blue item."
- "Choose the object inside the container nearest to the triangle."

### Generator Contract

Generate a 2D scene with typed objects, colors, sizes, counts, containers, occlusion layers, and spatial relations. The prompt is generated from the relation graph and must resolve to exactly one object.

Difficulty knobs: relation depth, object count, visual similarity, occlusion, distractor closeness, and whether the relation uses count, position, containment, or ordering.

### Public State

A scene canvas and concise instruction. The answer should be clickable directly on the scene.

### Private Ground Truth

Scene graph, object masks, relation query, target object id, target mask, and acceptable click polygon.

### Verifier Contract

Pass if the final click or selected object id intersects the target acceptance mask. Near misses and clicks on relation distractors fail.

### Timeouts

30-80 steps, 60-120 seconds.

### Failure Modes Targeted

Language-conditioned grounding, count reasoning, relation composition, and coordinate precision.

### Evidence Required

`start.png`, scene graph JSON, target mask preview for audit only, and solved final state.

## 6. `impossible_ecology`

### Source Anchors

`logic-captcha-media-examples-2024`, `arkose-dice-complaint-corpus`, `xkcd-2228-machine-learning-captcha`

### Instruction Templates

- "Select the item that cannot belong in this environment."
- "Which animal cannot live here?"
- "Pick the object that violates the scene rule."

### Generator Contract

Generate a small panel set where each panel contains an environment and one candidate object. A private ontology marks one candidate as incompatible: land animal underwater, office tool in a forest food chain, edible item in a machine-part set, etc.

Difficulty knobs: ontology category, number of panels, visual similarity, plausibility of distractors, and whether the rule is habitat, material, use, scale, or causality.

### Public State

Four to nine selectable panels with simple illustrated scenes and a rule prompt. Labels should not reveal the answer unless the variant is intentionally text-heavy.

### Private Ground Truth

Ontology rule, candidate labels, compatibility flags, target panel id, and rationale for audit.

### Verifier Contract

Pass if the selected panel id equals the unique incompatible candidate. If generation produces more than one incompatible object, the seed must be rejected before benchmark use.

### Timeouts

30-70 steps, 60-120 seconds.

### Failure Modes Targeted

Commonsense visual reasoning, prompt interpretation, and resisting literal category shortcuts.

### Evidence Required

Panel contact sheet, ontology entry, `ground_truth.json`, and a generation sanity report proving uniqueness.

## 7. `surreal_apple_on_tree_grid`

### Source Anchors

`logic-captcha-media-examples-2024`, `wired-bizarre-disappearing-captcha`

### Instruction Templates

- "Select every image with an apple on a tree."
- "Choose the panels where the target object appears in the described impossible arrangement."
- "Mark all scenes that satisfy the surreal prompt."

### Generator Contract

Generate 3x3 or 4x4 image grids with synthetic scenes. Target scenes contain a concept in a physically odd configuration, while distractors contain either the concept, the context, or the spatial relation but not all required properties.

Difficulty knobs: target count, prompt strangeness, distractor closeness, scene style, object scale, and partial occlusion.

### Public State

An image grid with multi-select behavior and a verify button. Scenes should be original generated or procedural assets, not copied source media.

### Private Ground Truth

Panel labels, target set, per-panel object masks, generated prompt decomposition, and selected-state requirements.

### Verifier Contract

Pass if selected panel set exactly matches the generated target set. Optional tolerance can ignore accidental double-click toggles only if the final selected set is correct.

### Timeouts

50-120 steps, 90-180 seconds.

### Failure Modes Targeted

Uncanny category membership, compositional prompt reading, multi-select state tracking, and distractor rejection.

### Evidence Required

Grid image, per-panel labels, target mask previews for audit, `ground_truth.json`, and final selected-grid screenshot.

## 8. `top_face_dice_arithmetic`

### Source Anchors

`arkose-dice-complaint-corpus`, `arkose-funcaptcha-complaints`, `arkose-funcaptcha-internals-crawlex`

### Instruction Templates

- "Pick the image where the top faces add up to 14."
- "Add only the top dice faces. Ignore side faces."
- "Select the panel whose visible top numbers match the target sum."

### Generator Contract

Render dice-like solids in perspective. Top faces carry pips, numerals, or icons with values. Side faces and background labels contain distractor values. One panel matches the target sum.

Difficulty knobs: dice count, perspective angle, occlusion, side-face distractors, numeric vs pip rendering, and target-sum closeness.

### Public State

Selectable panels with 3D-looking dice/cubes and a target sum prompt.

### Private Ground Truth

Per-panel top-face values, side-face distractors, target sum, correct panel id, and render camera parameters.

### Verifier Contract

Pass if the selected panel id has top-face sum equal to the target. Reject if multiple panels match; generation must guarantee uniqueness.

### Timeouts

40-100 steps, 90-180 seconds.

### Failure Modes Targeted

Perspective reading, ignoring distractor numerals, visual arithmetic, and panel selection.

### Evidence Required

Contact sheet, per-panel value table, `ground_truth.json`, and solved final state.

## 9. `rotate_wrong_thing_upright`

### Source Anchors

`whats-up-image-orientation`, `sketcha-3d-orientation`, `arkose-funcaptcha-internals-crawlex`

### Instruction Templates

- "Rotate the label upright."
- "Turn the shadow's object upright, not the object itself."
- "Make the small icon on the cube face point upward."

### Generator Contract

Generate a rotatable object with multiple orientation cues: main body, label, face, shadow, embedded icon, arrow, or text strip. The prompt selects which cue defines "upright."

Difficulty knobs: cue count, initial angle, rotation granularity, visual conflict between cues, 2D vs pseudo-3D rendering, and tolerance.

### Public State

A rotatable object with buttons, knob, drag rotation, or slider. The target cue must be visible.

### Private Ground Truth

Initial angle, target cue id, target upright angle, accepted angle interval, and distractor cue angles.

### Verifier Contract

Pass if the final rotation is within the accepted interval for the prompted cue. Do not pass merely because the dominant object body is upright when the prompt names another cue.

### Timeouts

40-90 steps, 60-150 seconds.

### Failure Modes Targeted

Prompt-specific orientation, continuous manipulation, sub-object attention, and tolerance control.

### Evidence Required

Start and final screenshots, cue map, target angle metadata, and audit overlay showing accepted interval.

## 10. `jigsaw_slider_alignment`

### Source Anchors

`jigsaw-captcha`, `geetest-funny-captcha`, `modrinth-evil-captcha`, `not-a-bot-steam`

### Instruction Templates

- "Slide the piece into the missing gap."
- "Align the cutout with the background."
- "Drag until the image discontinuity disappears."

### Generator Contract

Generate a background image or procedural pattern, cut out a piece, and place the draggable piece or slider offset from the true position. Variants include horizontal slider, free 2D drag, rotation plus translation, parallax distractors, and false gaps.

Difficulty knobs: gap contrast, piece shape, distractor gaps, movement axis, snap strength, and tolerance.

### Public State

A jigsaw/slider UI with visible draggable element and verification button or auto-submit on release.

### Private Ground Truth

True x/y/angle, piece mask, accepted tolerance, distractor gap locations, and final transform.

### Verifier Contract

Pass if final piece transform is within tolerance and the UI enters accepted state. For snap variants, verify the snapped position equals the true gap.

### Timeouts

50-120 steps, 90-180 seconds.

### Failure Modes Targeted

Visual alignment, drag control, continuous adjustment, and resisting false gaps.

### Evidence Required

Background, piece mask, accepted-transform JSON, start/final screenshots, and optional alignment overlay for audit.

## 11. `cursor_lens_reveal`

### Source Anchors

`captchastar-interactive-shape`, `kitboga-codejam25`, `cursed-captchas-computer-vision`

### Instruction Templates

- "Find the hidden symbol and select its name."
- "Use the cursor lens to reveal the target, then click it."
- "Scratch the panel until the answer is clear."

### Generator Contract

Generate a hidden layer containing a target object, codeword, or shape. The public layer conceals it except through a cursor-centered lens, scratch-off mask, flashlight cone, hover viewport, or moving reveal aperture.

Difficulty knobs: lens radius, target size, decoy count, reveal persistence, scan area, and whether the target moves.

### Public State

A masked canvas plus answer choices or direct target-click region. The visible state changes in response to pointer movement.

### Private Ground Truth

Hidden target id, target mask, decoy masks, reveal parameters, and correct answer choice or click region.

### Verifier Contract

Pass if the final selected answer or clicked hidden target matches the generated target. The verifier does not require a particular exploration path.

### Timeouts

60-150 steps, 90-240 seconds.

### Failure Modes Targeted

Active visual exploration, memory from partial reveals, pointer control, and avoiding static-screenshot assumptions.

### Evidence Required

Start screenshot, hidden-layer audit image, reveal-parameter JSON, frame sequence or video, and solved final state.

## 12. `trace_shape_without_walls`

### Source Anchors

`motioncaptcha`, `modrinth-evil-captcha`, `captcha-hell`

### Instruction Templates

- "Trace the shape without touching the walls."
- "Draw the shown symbol inside the corridor."
- "Guide the cursor from start to finish without leaving the path."

### Generator Contract

Generate a path, symbol, maze corridor, or trace target. The runtime records the drawn stroke or cursor path after pointer-down. Variants include one-stroke tracing, corridor navigation, branch avoidance, and mild moving obstacles.

Difficulty knobs: path length, corridor width, curvature, branch count, required stroke order, obstacle motion, and tolerance.

### Public State

A canvas with a start marker, target path or corridor, and visible progress state.

### Private Ground Truth

Target path polyline, corridor polygon, start/end regions, obstacle trajectories, collision rules, and completion threshold.

### Verifier Contract

Pass if the final submitted path reaches the endpoint, stays within the acceptance corridor, and satisfies configured path similarity. Collisions can visibly reset the UI, but scoring is final outcome.

### Timeouts

80-180 steps, 2-4 minutes.

### Failure Modes Targeted

Pointer path planning, continuous motor execution, route following, and recovery from resets.

### Evidence Required

Target path JSON, corridor mask, sampled drawn path in `summary.json`, start/final screenshots, and one known-solved stroke trace.

## 13. `single_scene_split_boxes`

### Source Anchors

`modrinth-evil-captcha`, `github-ttuples-simplecaptcha`, `user-inyerface`

### Instruction Templates

- "Select every tile containing part of the bicycle."
- "Click all boxes that include the target object."
- "The scene is split into tiles. Mark only the tiles touched by the named object."

### Generator Contract

Render one coherent scene with object segmentation masks, then split the full image into a grid. The target object can cross tile boundaries, appear partially occluded, or occupy tiny fractions of some tiles.

Difficulty knobs: grid size, target mask size, overlap threshold, object fragmentation, distractor objects, and boundary ambiguity.

### Public State

A tiled image grid with multi-select state and verify button. Grid lines should be visible but not obscure target evidence.

### Private Ground Truth

Scene object masks, target object id, per-tile overlap ratios, selected tile set, and threshold rule.

### Verifier Contract

Pass if the final selected tile set equals the generated target tile set. Generation must record whether threshold is "any overlap" or minimum area ratio.

### Timeouts

50-120 steps, 90-180 seconds.

### Failure Modes Targeted

Partial-object recognition, tile-boundary reasoning, multi-select memory, and avoiding object-category shortcuts.

### Evidence Required

Full scene, grid screenshot, target mask overlay for audit, tile-overlap table, and final selected-grid screenshot.

## 14. `modifier_stack_image_grid`

### Source Anchors

`github-henryamatsu-im-not-a-robot`, `captcha-chaos-live-game`, `captcha-hell`

### Instruction Templates

- "Select all images of cats."
- "Verify by removing every target image, even if distorted."
- "Choose every panel matching the prompt after the visual modifiers are applied."

### Generator Contract

Generate a classic image-selection grid, then apply a stack of visual mutators: rotation, skew, inversion, blur, crop, four-panel split, jitter, delayed load, mirror, fake loading overlay, or mild movement. The base category labels are known before mutation.

Difficulty knobs: grid size, category count, target count, mutator count, mutator severity, motion speed, and decoy similarity.

### Public State

A multi-select image grid, prompt, and verify button. Modifiers should be visually obvious enough to be funny without destroying solvability.

### Private Ground Truth

Base asset labels, target category, selected panel set, mutator stack per panel, and generated asset ids.

### Verifier Contract

Pass if final selected set equals the target set. If a mutator moves a panel, selection maps to element id rather than stale coordinate.

### Timeouts

60-150 steps, 90-240 seconds.

### Failure Modes Targeted

Robust category recognition under transformations, multi-select state tracking, and ignoring visual chaos.

### Evidence Required

Unmodified grid contact sheet, modified grid screenshot, mutator metadata, `ground_truth.json`, and solved final state.

## 15. `minecraft_block_grid`

### Source Anchors

`github-ttuples-simplecaptcha`, `modrinth-evil-captcha`, `modrinth-minecaptcha`

### Instruction Templates

- "Select all cells containing diamond ore."
- "Click every tile with a hostile mob."
- "Choose the grid cells that contain the named block or item."

### Generator Contract

Generate blocky Minecraft-like 4x4 or 5x5 grids using recreated/procedural voxel-style assets. Each cell can contain blocks, items, mobs, environmental features, or distractor textures.

Difficulty knobs: grid size, target count, sprite scale, texture similarity, occlusion, lighting, and whether target evidence spans cell edges.

### Public State

A game-themed tiled CAPTCHA with prompt, selected-cell highlights, and verify button.

### Private Ground Truth

Cell labels, target class, target cell set, asset ids, style parameters, and optional cell masks.

### Verifier Contract

Pass if selected cells match the generated target set. For object-spanning variants, use cell masks and the configured overlap threshold.

### Timeouts

50-120 steps, 90-180 seconds.

### Failure Modes Targeted

Game-specific visual vocabulary, tiny sprite recognition, grid selection, and texture-level distractors.

### Evidence Required

Grid screenshot, cell-label table, asset manifest, `ground_truth.json`, and final selected state.

## 16. `wizard_critter_capture`

### Source Anchors

`modrinth-evil-captcha`, `captcha-runner-ios`, `captchaware`

### Instruction Templates

- "Catch the target before time runs out."
- "Click the wizard's marked critter."
- "Capture the only glowing sprite."

### Generator Contract

Generate a bounded arena with a moving target sprite and optional decoys. The target follows deterministic seeded motion: patrol, bounce, easing, flee-from-cursor, hide-behind-obstacle, or short burst movement.

Difficulty knobs: target size, speed, decoy count, arena clutter, movement predictability, capture radius, and timer length.

### Public State

An animated arena, timer, target cue, and capture feedback.

### Private Ground Truth

Target id, sprite trajectory over time, hit radius, decoy trajectories, timer, and capture event state.

### Verifier Contract

Pass if a click/capture event hits the target within the timer. Decoy hits can subtract visible UI health, but final success state is the benchmark outcome.

### Timeouts

80-180 steps, 30-90 seconds wall-clock depending on animation speed.

### Failure Modes Targeted

Visual tracking, timing, predictive clicking, target-decoy discrimination, and handling animation.

### Evidence Required

Trajectory JSON, video or sampled frames, start/final screenshots, `ground_truth.json`, and a known-solved capture event.

## 17. `microgame_gauntlet`

### Source Anchors

`captchaware`, `captcha-royale`, `not-a-bot-steam`, `captcha-chaos-live-game`

### Instruction Templates

- "Complete the micro-verification sequence."
- "Clear 6 tiny CAPTCHA rounds."
- "Survive the verification gauntlet."

### Generator Contract

Generate a seeded sequence of short rounds using simple subpuzzles: click target, choose image, type token, drag object, rotate indicator, remember symbol, dodge decoy, or quick arithmetic. The sequence is a single mechanic because the episode objective is adaptation across rapidly changing rules.

Difficulty knobs: round count, timer per round, subpuzzle mix, prompt brevity, carry-over memory, lives, and visual mutators.

### Public State

One microgame viewport with visible round prompt, timer/lives, and transition feedback. Each round reuses the shared runtime but changes rendered content.

### Private Ground Truth

Round list, per-round generated answers, timers, pass threshold, life count, and final success condition.

### Verifier Contract

Pass if the episode reaches the final success state or completes at least the configured number of rounds. The headline score should use a fixed threshold, while per-round outcomes are logged for analysis.

### Timeouts

150-400 steps, 2-6 minutes.

### Failure Modes Targeted

Rapid rule switching, short-term memory, prompt reading under time pressure, and recovery from small mistakes.

### Evidence Required

Round manifest, video, per-round summary, start/final screenshots, and solved or manually verified run.

## 18. `reload_interruption`

### Source Anchors

`captcha-the-flag`, `modrinth-evil-captcha`, `github-ttuples-simplecaptcha`

### Instruction Templates

- "Finish the base task. Clear any verification interruptions."
- "Complete the reload while solving the pop-up CAPTCHA."
- "Continue the task after each verifier overlay."

### Generator Contract

Generate a simple base task, such as filling a progress bar, sorting icons, reloading a tool, or moving objects into a target. At seeded moments, a verification overlay interrupts progress and must be cleared before the base task can continue.

Difficulty knobs: number of interruptions, overlay mechanic, base-task memory burden, interruption timing, overlay obscurity, and whether progress decays.

### Public State

A base task area plus modal CAPTCHA overlays. The overlay must clearly block or pause base-task interaction.

### Private Ground Truth

Base task completion condition, interruption schedule, overlay answers, preserved base state, and final success state.

### Verifier Contract

Pass if the original base task reaches completion after clearing interruptions. Overlay sub-results are logged, but final base objective is the outcome.

### Timeouts

150-350 steps, 3-6 minutes.

### Failure Modes Targeted

Task switching, state recovery after interruption, modal handling, and maintaining the original objective.

### Evidence Required

Interruption schedule, base-state snapshots, overlay ground truth, video, and final completed base-task screenshot.

## 19. `fake_desktop_automation_inversion`

### Source Anchors

`ho-games-studio-not-a-bot`, `captcha-hell`, `user-inyerface`

### Instruction Templates

- "Use the fake desktop to complete the automation check."
- "Finish the simulated app task without failing the verifier."
- "Operate the computer inside the computer."

### Generator Contract

Generate a simulated desktop with windows, fake apps, small files, taskbar icons, and a verification layer that jokes about automation. Variants include autoclicker purchase panels, fake email/file tasks, shopping carts, modal warnings, and "robot-like behavior" inversions.

Difficulty knobs: window count, nested modal depth, decoy apps, fake vs real controls, small text density, and number of objective subgoals.

### Public State

A fake OS inside the puzzle viewport. All interactions are still ordinary pointer/keyboard events into the shared runtime.

### Private Ground Truth

Simulated app state machine, required objective state, fake file/app metadata, trap controls, and accepted final state.

### Verifier Contract

Pass if the simulated desktop objective reaches the generated completed state. Do not score how the agent navigated as long as it used the public UI.

### Timeouts

250-600 steps, 5-10 minutes.

### Failure Modes Targeted

Nested UI interpretation, fake operating-system affordances, modal recovery, and meta-automation confusion.

### Evidence Required

Initial desktop screenshot, state-machine JSON, solved final screenshot, trajectory video, and objective completion proof in `summary.json`.

## 20. `exit_vim_terminal_escape`

### Source Anchors

`github-nicholasdejesse-captcha-game`, `kitboga-codejam25`

### Instruction Templates

- "Escape the terminal verifier."
- "Exit the editor and submit."
- "Use the terminal to unlock verification."

### Generator Contract

Generate a terminal-like state machine with Vim, shell, pager, REPL, or text adventure modes. The puzzle accepts one or more correct command/key sequences, such as `:q`, `:wq`, `q`, `exit`, `Ctrl+C`, or a generated command printed in the terminal.

Difficulty knobs: terminal mode, visible hints, command alternatives, focus traps, fake prompts, inserted text state, and whether a final submit step is needed.

### Public State

A terminal emulator with text, cursor, mode line, and optional surrounding verifier chrome.

### Private Ground Truth

Terminal state machine, accepted command families, current mode, final accepted state, and rejected trap commands.

### Verifier Contract

Pass if the terminal reaches the accepted state. Accept all semantically valid sequences defined by the state machine; do not require one exact keystroke trace.

### Timeouts

50-160 steps, 90-240 seconds.

### Failure Modes Targeted

Domain knowledge, exact keyboard input, focus management, and interpreting terminal modes from pixels.

### Evidence Required

State-machine JSON, start/final screenshots, accepted command list for audit, and a solved trace.

## 21. `board_game_captcha`

### Source Anchors

`lichess-chess-captcha`, `github-nicholasdejesse-captcha-game`, `captchad-boardgame`

### Instruction Templates

- "Find the mate in one."
- "Play the winning move."
- "Block the immediate threat."
- "Move the piece to solve the board."

### Generator Contract

Generate small board positions using existing game logic libraries where possible. Initial variants: chess mate-in-one, tic-tac-toe win/block, connect-style win, tiny sokoban/pathfinding board, and simple checkers capture. Each generated board must have a unique or explicitly enumerated solution set.

Difficulty knobs: game type, board size, piece count, legal-move ambiguity, distractor threats, coordinate labels, and drag vs click-to-move UI.

### Public State

A rendered board, pieces, and a concise objective prompt.

### Private Ground Truth

Game type, full board state, legal move list, solution move set, final winning state, and engine/library validation output.

### Verifier Contract

Pass if the final submitted move is legal and belongs to the solution set. If multiple winning moves exist, all must be represented in ground truth or the seed rejected.

### Timeouts

80-220 steps, 2-5 minutes.

### Failure Modes Targeted

Domain reasoning, board localization, legal move execution, and exact drag/click manipulation.

### Evidence Required

Board FEN/state JSON, solution proof from engine, start/final screenshots, and rendered answer overlay for audit only.

## 22. `semantic_drag_drop_absurdity`

### Source Anchors

`playthru-are-you-a-human`, `sweetcaptcha-action-captcha`, `captcha-hell`

### Instruction Templates

- "Drag each object where it belongs."
- "Put the absurd items into their correct places."
- "Match every object to the thing it fixes, feeds, opens, or completes."

### Generator Contract

Generate objects, target containers, and a semantic relation graph. Relations include belongs-in, used-for, eaten-by, fixes, unlocks, completes, powers, cools, or absurd pairings defined by a visible rule.

Difficulty knobs: object count, target count, relation type, distractor plausibility, object size, overlap tolerance, and whether all objects or only one object must be placed.

### Public State

Draggable objects and drop zones with a prompt. Drop feedback should be minimal until verify unless the variant intentionally provides training wheels.

### Private Ground Truth

Object ids, target ids, correct assignment graph, accepted drop polygons, distractor relation labels, and final arrangement.

### Verifier Contract

Pass if required object-target assignments match the generated graph. Extra objects may be ignored or must remain unplaced depending on task config, recorded in ground truth.

### Timeouts

80-220 steps, 2-4 minutes.

### Failure Modes Targeted

Semantic affordance reasoning, drag/drop precision, assignment memory, and plausible-distractor rejection.

### Evidence Required

Object/target manifest, relation graph, start/final screenshots, `ground_truth.json`, and solved arrangement screenshot.

## 23. `bureaucratic_signature_trap`

### Source Anchors

`hummushustler-please-sign-here`, `hawke-gaming-voluntary-collaboration`, `user-inyerface`

### Instruction Templates

- "Sign exactly where requested."
- "Initial the box that is not for signatures."
- "Stamp the form in the order described."

### Generator Contract

Generate a hostile form with signature boxes, initials fields, stamps, date fields, checkboxes, labels, and contradictory-looking instructions. The prompt defines the correct target field, mark style, and order.

Difficulty knobs: number of fields, instruction clauses, decoy labels, required mark type, drawing tolerance, field size, and whether the form scrolls.

### Public State

A form-like UI with pen/stamp/typing affordances and submit button.

### Private Ground Truth

Required field ids, accepted mark type, accepted region polygons, required text if any, order constraints, and final accepted form state.

### Verifier Contract

Pass if the submitted form contains the correct marks in the correct fields and omits disallowed marks. Drawing shape is evaluated against a broad region/style rubric, not exact pen path.

### Timeouts

80-220 steps, 2-5 minutes.

### Failure Modes Targeted

Instruction parsing, form-field localization, drawing or stamping control, and resisting misleading labels.

### Evidence Required

Form screenshot, field geometry JSON, `ground_truth.json`, final form screenshot, and audit overlay of accepted regions.

## 24. `rorschach_fixed_rubric`

### Source Anchors

`modrinth-evil-captcha`, `hotcaptcha`, `xkcd-2228-machine-learning-captcha`

### Instruction Templates

- "What does this image most resemble?"
- "Select the official interpretation."
- "Choose the answer that the verifier expects for this ambiguous blot."

### Generator Contract

Generate an abstract image, inkblot, blob silhouette, noisy collage, or pareidolia-like shape. Pair it with a fixed hidden label from a controlled multiple-choice set. The joke is subjective appearance with an objective benchmark rubric.

Difficulty knobs: label set size, image ambiguity, number of near labels, prompt framing, and whether there is a small visual clue tying the blot to the hidden label.

### Public State

An ambiguous image plus multiple-choice answers. Avoid free-text as the default because programmatic grading should remain reliable.

### Private Ground Truth

Generated image seed, accepted label id, distractor labels, optional clue metadata, and answer button ids.

### Verifier Contract

Pass if selected label id equals the generated accepted label. The verifier must not infer a better subjective answer than the generated rubric.

### Timeouts

30-80 steps, 60-120 seconds.

### Failure Modes Targeted

Handling subjective-looking prompts, reading answer choices, resisting over-explanation, and accepting fixed hidden rubrics.

### Evidence Required

Generated blot image, label set, `ground_truth.json`, final selected state, and an audit note that the accepted label is visible only through the public choices, not leaked elsewhere.

## 25. `temporal_memory_first_change`

### Source Anchors

`nucaptcha-video`, `video-tag-captcha-youtube`, `bountcha-video-boundary`, `prove-youre-human`

### Instruction Templates

- "Click the first object that changed."
- "Enter the codeword that moved across the screen."
- "Mark the frame where the scene becomes impossible."
- "Select the tag that describes the short clip."

### Generator Contract

Generate a deterministic short animation. Variants include moving codeword, first-change object, disappearing target, one-frame color swap, object crossing a boundary, or synthetic video segment with a transition frame. The answer depends on watching over time.

Difficulty knobs: clip length, object count, change subtlety, codeword speed, distractor changes, replay availability, and answer mode.

### Public State

An animated canvas/video panel with answer field, clickable objects, or timeline marker. Replay controls can be enabled or disabled by difficulty, but the policy must be recorded.

### Private Ground Truth

Timeline events, target object id, codeword, transition frame/time, answer mode, object trajectories, and accepted tolerance.

### Verifier Contract

Pass if the submitted codeword, selected object, chosen tag, or marked frame matches ground truth within configured tolerance. The verifier uses generated timeline metadata, not video interpretation.

### Timeouts

80-240 steps, 2-5 minutes, plus clip duration.

### Failure Modes Targeted

Temporal evidence gathering, memory across observations, animation tracking, replay planning, and answer entry.

### Evidence Required

Timeline JSON, generated clip or frame sequence, `video.mp4`, `ground_truth.json`, start/final screenshots, and one manually checked solved example.
