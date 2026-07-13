# Mechanic Shortlist v0

Date: 2026-07-08

This is the first design shortlist after freezing collection v0. It is intentionally creative and benchmark-facing: these are not claims that current CUAs fail them. They are candidates that look fun, visually distinctive, and likely to stress different parts of computer-use behavior.

## Selection Bias

I selected mechanics that are:

- Visually or interactively funny, not just "hard."
- Grounded in collection v0 sources.
- Outcome-gradable without needing to grade the agent's process.
- Likely to require actual computer-use behavior: clicking, dragging, tracing, waiting, reading UI state, handling motion, or recovering from misleading interface state.
- Varied across perception, motor control, temporal evidence, logic/domain reasoning, and hostile UI.

## Architecture Constraint

All mechanics use the same computer-use action surface. Individual mechanics do not define their own allowed actions; they define generated puzzle state, instructions, ground truth, and outcome verification only.

The benchmark is one Gym-Anything-style environment with many task setups, not a grouped collection of separate per-mechanic harnesses.

## The 25

### 1. `reverse_identity_gate` - Reverse Identity Gate

The verifier asks the user to prove they are a robot, not a human, or punishes normal "human" behavior.

- Source anchors: `willardpeng-im-not-a-robot`, `josi-jami-i-am-not-a-robot`, `zachshirikjian-are-you-human`
- Why it is fun for CUAs: the agent must invert the usual CAPTCHA ritual and notice that obvious "I'm not a robot" behavior may be wrong.
- Outcome grader: final verifier state is accepted.
- Generator sketch: prompt templates with inverted wording, trap buttons, and accepted action maps.

### 2. `moving_checkbox_evasive_button` - Moving Checkbox / Evasive Button

The familiar checkbox or verify button moves, dodges the cursor, changes size, or appears only under certain cursor positions.

- Source anchors: `github-nicholasdejesse-captcha-game`, `neal-im-not-a-robot`, `captcha-hell`
- Why it is fun for CUAs: turns a trivial checkbox into a motor-control/localization task.
- Outcome grader: checkbox state becomes checked or verification completes.
- Generator sketch: randomized movement pattern, target size, avoidance radius, and decoy boxes.

### 3. `code_to_diagram_captcha` - Code-To-Diagram CAPTCHA

The user sees code or pseudo-code and must select the matching control-flow diagram, execution trace, or output panel.

- Source anchors: `2020-cfgcaptcha`, `kitboga-codejam25`
- Why it is fun for CUAs: combines visual UI operation with symbolic/code reasoning.
- Outcome grader: selected diagram/output id matches generated program semantics.
- Generator sketch: small generated programs, rendered diagrams, and distractors with one structural mutation.

### 4. `wonky_text_hostile_rendering` - Wonky Text Under Hostile Rendering

A text CAPTCHA where OCR alone is not enough because characters are obscured, layered, split, reflected, or embedded in UI clutter.

- Source anchors: `modrinth-evil-captcha`, `perceptual-gaps-ascii-audio`, `captcha-hell`
- Why it is fun for CUAs: classic CAPTCHA nostalgia, but with UI-level traps and noisy fields.
- Outcome grader: submitted string matches generated answer.
- Generator sketch: distorted font sprites, partial occluders, fake caret positions, and irrelevant visible text.

### 5. `relation_prompt_grounding` - Relation Prompt Grounding

The prompt describes a relation, not a class: "click the red object in front of the object that appears once."

- Source anchors: `logic-captcha-media-examples-2024`, `visual-reasoning-captcha-vtt`, `arkose-funcaptcha-internals-crawlex`
- Why it is fun for CUAs: requires language-conditioned scene grounding and exact prompt reading.
- Outcome grader: click coordinate hits the object satisfying the generated relation.
- Generator sketch: 2D scenes with object colors, counts, front/behind/left/right/inside relations, and near-miss distractors.

### 6. `impossible_ecology` - Impossible Ecology

Select the only object/animal that violates a commonsense environment rule, such as "the one that cannot live underwater."

- Source anchors: `logic-captcha-media-examples-2024`, `arkose-dice-complaint-corpus`, `xkcd-2228-machine-learning-captcha`
- Why it is fun for CUAs: visually simple but semantically sharp; models may over-focus on labels or scene priors.
- Outcome grader: selected panel id matches the generated rule.
- Generator sketch: generated panels with aquatic/non-aquatic, edible/non-edible, tool/place mismatches.

### 7. `surreal_apple_on_tree_grid` - Surreal Apple-On-Tree Grid

Select images containing a target concept in a physically odd configuration, such as an apple on a tree inside a bowl-like scene.

- Source anchors: `logic-captcha-media-examples-2024`, `wired-bizarre-disappearing-captcha`
- Why it is fun for CUAs: intentionally uncanny images make category membership less clean.
- Outcome grader: selected target panels match labels.
- Generator sketch: synthetic/illustrated scenes with plausible and impossible variants; no need to reuse source media.

### 8. `top_face_dice_arithmetic` - Top-Face Dice Arithmetic

Add only the top faces of dice-like objects, ignoring side faces, printed distractors, and perspective tricks.

- Source anchors: `arkose-dice-complaint-corpus`, `arkose-funcaptcha-complaints`, `arkose-funcaptcha-internals-crawlex`
- Why it is fun for CUAs: small visual arithmetic with strong distractors and perspective ambiguity.
- Outcome grader: selected panel sum equals target.
- Generator sketch: render dice/cubes with labeled faces, occlusion, distractor numerals, and target sums.

### 9. `rotate_wrong_thing_upright` - Rotate The Wrong Thing Upright

The user must rotate an object upright, but the prompt may refer to a sub-object, shadow, label, or icon on the object.

- Source anchors: `whats-up-image-orientation`, `sketcha-3d-orientation`, `arkose-funcaptcha-internals-crawlex`
- Why it is fun for CUAs: rotation tasks are easy to describe and surprisingly annoying to operate precisely.
- Outcome grader: final angle is within tolerance.
- Generator sketch: 2D/3D rendered objects with multiple orientation cues and prompt-specific target cue.

### 10. `jigsaw_slider_alignment` - Jigsaw / Slider Alignment

Drag a piece or slider until the gap, silhouette, or visual discontinuity aligns.

- Source anchors: `jigsaw-captcha`, `geetest-funny-captcha`, `modrinth-evil-captcha`, `not-a-bot-steam`
- Why it is fun for CUAs: combines vision and continuous drag control.
- Outcome grader: final x/y/rotation is within tolerance.
- Generator sketch: random cutouts, backgrounds, parallax distractors, and snap/no-snap variants.

### 11. `cursor_lens_reveal` - Cursor-Lens Reveal

The answer is only visible through a moving lens, flashlight, scratch-off region, hover state, or viewport.

- Source anchors: `captchastar-interactive-shape`, `kitboga-codejam25`, `cursed-captchas-computer-vision`
- Why it is fun for CUAs: a static screenshot is insufficient; the agent must explore with the cursor.
- Outcome grader: final selected answer or revealed target id is correct.
- Generator sketch: masked canvas with hidden target, decoys, and a lens radius/path budget.

### 12. `trace_shape_without_walls` - Trace The Shape Without Touching The Walls

The user must draw a path, trace a symbol, or navigate a cursor through a constrained route.

- Source anchors: `motioncaptcha`, `modrinth-evil-captcha`, `captcha-hell`
- Why it is fun for CUAs: stresses pointer path planning and execution, not just click prediction.
- Outcome grader: path similarity or collision-free completion.
- Generator sketch: generated paths, width/tolerance controls, decoy branches, and mild drift.

### 13. `single_scene_split_boxes` - Single Scene Split Into Boxes

A coherent scene is divided into grid tiles; the user must click all tiles containing part of a target object.

- Source anchors: `modrinth-evil-captcha`, `github-ttuples-simplecaptcha`, `user-inyerface`
- Why it is fun for CUAs: unlike normal image grids, the target crosses boundaries and partial visibility matters.
- Outcome grader: selected tile set matches generated mask above threshold.
- Generator sketch: render one scene, segment target mask, tile into grid, grade tile overlap.

### 14. `modifier_stack_image_grid` - Modifier-Stack Image Grid

Classic "select all X" grids, but with stacked modifiers: skew, negative colors, rotation, movement, blur, and split panels.

- Source anchors: `github-henryamatsu-im-not-a-robot`, `captcha-chaos-live-game`, `captcha-hell`
- Why it is fun for CUAs: familiar task becomes chaotic without needing a complex premise.
- Outcome grader: selected target images match generated labels.
- Generator sketch: image categories plus composable visual CSS/canvas mutators.

### 15. `minecraft_block_grid` - Minecraft Block Grid

Select grid cells containing a Minecraft-like object, block, creature, or environmental feature.

- Source anchors: `github-ttuples-simplecaptcha`, `modrinth-evil-captcha`, `modrinth-minecaptcha`
- Why it is fun for CUAs: game-specific visual vocabulary, small tiles, and embedded-game framing.
- Outcome grader: selected 4x4 cells match answer map.
- Generator sketch: blocky rendered scenes or recreated sprites; answer masks generated from object placement.

### 16. `wizard_critter_capture` - Wizard / Critter Capture

A tiny target moves around a bounded area and must be clicked or captured before time expires.

- Source anchors: `modrinth-evil-captcha`, `captcha-runner-ios`, `captchaware`
- Why it is fun for CUAs: fast visual tracking plus click timing.
- Outcome grader: target captured before timer expires.
- Generator sketch: sprite movement patterns, target scale, decoy sprites, and time limit.

### 17. `microgame_gauntlet` - Microgame Gauntlet

A WarioWare-style sequence of tiny CAPTCHA tasks, each with a different rule and short timer.

- Source anchors: `captchaware`, `captcha-royale`, `not-a-bot-steam`, `captcha-chaos-live-game`
- Why it is fun for CUAs: tests adaptation to changing UI rules and rapid prompt reading.
- Outcome grader: complete N of M rounds or final success state.
- Generator sketch: compose from smaller mechanics with randomized order and round modifiers.

### 18. `reload_interruption` - Reload Interruption

The user is performing one task, but a CAPTCHA interrupts at inconvenient moments and must be cleared to continue.

- Source anchors: `captcha-the-flag`, `modrinth-evil-captcha`, `github-ttuples-simplecaptcha`
- Why it is fun for CUAs: stresses task switching and state recovery.
- Outcome grader: original task reaches completion after clearing interruptions.
- Generator sketch: base task plus stochastic verifier overlays; grade only final base-task success.

### 19. `fake_desktop_automation_inversion` - Fake Desktop / Automation Inversion

A simulated desktop asks the user to automate something while proving they are not automated, or punishes machine-like behavior.

- Source anchors: `ho-games-studio-not-a-bot`, `captcha-hell`, `user-inyerface`
- Why it is fun for CUAs: meta-computer-use: operate a computer inside a computer with hostile verification.
- Outcome grader: simulated app objective completed.
- Generator sketch: fake OS windows, shopping/clicker/email tasks, and verifier popups.

### 20. `exit_vim_terminal_escape` - Exit Vim / Terminal Escape

The CAPTCHA is a terminal-like interface where the user must type the right command or key sequence to escape.

- Source anchors: `github-nicholasdejesse-captcha-game`, `kitboga-codejam25`
- Why it is fun for CUAs: domain knowledge is allowed; exact key input matters.
- Outcome grader: terminal state transitions to accepted.
- Generator sketch: terminal mini-simulators for Vim, shell prompts, pager exits, and command-line traps.

### 21. `board_game_captcha` - Board-Game CAPTCHA

Solve a small board position: chess mate-in-one, tic-tac-toe win/block, connect-style move, or tiny pathfinding board.

- Source anchors: `lichess-chess-captcha`, `github-nicholasdejesse-captcha-game`, `captchad-boardgame`
- Why it is fun for CUAs: domain logic plus visual board manipulation.
- Outcome grader: final move is legal and solves the generated board objective.
- Generator sketch: use existing engines where possible for board logic; render boards with draggable/clickable pieces.

### 22. `semantic_drag_drop_absurdity` - Semantic Drag-And-Drop Absurdity

Drag objects to semantically correct places, with distractors that are plausible but wrong.

- Source anchors: `playthru-are-you-a-human`, `sweetcaptcha-action-captcha`, `captcha-hell`
- Why it is fun for CUAs: requires understanding object affordances and performing drag/drop accurately.
- Outcome grader: object-target assignments match generated relation graph.
- Generator sketch: small object sets, target containers, and relations like belongs-in, used-for, eaten-by, fixes.

### 23. `bureaucratic_signature_trap` - Bureaucratic Signature Trap

The user must sign, stamp, initial, or fill a form, but the instruction changes the expected style, location, or order.

- Source anchors: `hummushustler-please-sign-here`, `hawke-gaming-voluntary-collaboration`, `user-inyerface`
- Why it is fun for CUAs: mundane form-filling becomes a visual/motor puzzle.
- Outcome grader: correct field/signature region accepted.
- Generator sketch: forms with randomized instruction clauses, signature boxes, stamps, and decoy fields.

### 24. `rorschach_fixed_rubric` - Rorschach / Subjective Prompt With A Fixed Rubric

Ask for an interpretation of an ambiguous image, but benchmark generation defines the accepted answer.

- Source anchors: `modrinth-evil-captcha`, `hotcaptcha`, `xkcd-2228-machine-learning-captcha`
- Why it is fun for CUAs: exposes the comedy of "subjective" verification while staying outcome-gradable.
- Outcome grader: chosen label/text matches the hidden generated rubric.
- Generator sketch: generated inkblots or abstract shapes paired with a fixed multiple-choice label set.

### 25. `temporal_memory_first_change` - Temporal Memory / First-Change Evidence

The answer depends on watching a sequence: remember a moving codeword, click the first object that changed, or mark a transition frame.

- Source anchors: `nucaptcha-video`, `video-tag-captcha-youtube`, `bountcha-video-boundary`, `prove-youre-human`
- Why it is fun for CUAs: cannot be solved from a single static screenshot.
- Outcome grader: entered code, selected object, or marked frame matches generated temporal ground truth.
- Generator sketch: canvas animations with logged ground truth for object identity, position, and change time.

## Near-Misses For Later

- Pure dense traffic-light/bus grids: too familiar unless combined with modifiers.
- Pure OCR CAPTCHAs: useful as nostalgia, but less interesting unless embedded in hostile UI.
- Pure benchmark-suite families from OpenCaptchaWorld/NextGen-CAPTCHAs: useful source material, but we should wrap them in more playful interfaces.
- Pure social-media meme screenshots: useful inspiration, but not enough by themselves unless recreated with controlled assets.

## Scope Lock

All 25 mechanics are in scope for the benchmark design. Implementation can still be staged for engineering reasons, but the design target is the full set, not a smaller prototype pack.

The next step is to expand every mechanic into a full task spec under `architecture-v0.md`: generator contract, UI state, hidden ground truth, outcome verifier, difficulty knobs, and evidence requirements.
