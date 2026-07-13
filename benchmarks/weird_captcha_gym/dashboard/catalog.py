from __future__ import annotations

import json
from pathlib import Path
from typing import Any


DASHBOARD_ROOT = Path(__file__).resolve().parent
BENCHMARK_ROOT = DASHBOARD_ROOT.parent
REPO_ROOT = BENCHMARK_ROOT.parents[1]
ENVIRONMENTS_ROOT = BENCHMARK_ROOT / "environments"
EVIDENCE_ROOT = BENCHMARK_ROOT / "evidence"
DIRECT_HUMAN_STATUSES = {"human-tested", "feedback-integrated", "human-iterated"}


PROFILES: dict[str, dict[str, Any]] = {
    "motion_only_ghost_jigsaw": {
        "title": "Motion-Only Ghost Jigsaw",
        "group": "Interaction I",
        "summary": "Nine pictures exist only as opposing motion inside visual noise. Remember the reference, then rebuild it while every tile keeps moving.",
        "axes": ["motion-only", "temporal vision", "dragging"],
        "difficulty": "extreme",
        "accent": "#c8ff55",
        "human": "human-tested",
        "order": 10,
    },
    "cursor_constellation_hunt": {
        "title": "Cursor Constellation Hunt",
        "group": "Interaction I",
        "summary": "The cursor is a lens into the answer space: search for the one coordinate where drifting stars resolve into a coherent object.",
        "axes": ["active vision", "cursor search", "decoys"],
        "difficulty": "hard",
        "accent": "#68e7ff",
        "human": "human-tested",
        "order": 11,
    },
    "parallel_grillmaster": {
        "title": "Parallel Grillmaster",
        "group": "Interaction I",
        "summary": "Cook six foods with different visual timing windows, move each at peak doneness, and keep every deadline alive at once.",
        "axes": ["parallel timing", "monitoring", "dragging"],
        "difficulty": "hard",
        "accent": "#ff9b54",
        "human": "human-tested",
        "order": 12,
    },
    "rotating_keyboard": {
        "title": "Rotating On-Screen Keyboard",
        "group": "Interaction I",
        "summary": "Enter a code on a keyboard whose entire coordinate frame begins tumbling after the first click.",
        "axes": ["moving targets", "visual tracking", "precision"],
        "difficulty": "hard",
        "accent": "#f47cff",
        "human": "human-tested",
        "order": 13,
    },
    "slot_reel_capture": {
        "title": "Slot-Reel Character Capture",
        "group": "Interaction I",
        "summary": "Catch transient symbols at the center line, freeze five independently moving reels, and recover within a visible three-strike budget.",
        "axes": ["transient input", "timing", "recovery"],
        "difficulty": "hard",
        "accent": "#ffd45e",
        "human": "feedback-integrated",
        "order": 14,
    },
    "domino_autopsy": {
        "title": "Domino Autopsy",
        "group": "Interaction II",
        "summary": "Repair a broken rigid-body chain, run real physics, inspect where impulse dies, and make a suspended bell physically swing.",
        "axes": ["rigid-body physics", "iteration", "diagnosis"],
        "difficulty": "hard",
        "accent": "#ff6a4f",
        "human": "human-iterated",
        "order": 20,
    },
    "consequences_boss": {
        "title": "Consequences Boss",
        "group": "Interaction II",
        "summary": "Create five socket-and-seal covenants, lose the ledger to a storm, then physically reconstruct your own hidden history in judgment order.",
        "axes": ["created state", "occluded memory", "physical reconstruction"],
        "difficulty": "hard",
        "accent": "#e69bff",
        "human": "revision-rebuilt-pending-human",
        "order": 21,
    },
    "popup_exorcist": {
        "title": "Popup Exorcist",
        "group": "Interaction II",
        "summary": "Close anonymous overlapping windows until one retaliates, then contain a live infected echo while the replicated desktop fights back.",
        "axes": ["occlusion", "runtime discovery", "containment drag"],
        "difficulty": "hard",
        "accent": "#64f6b4",
        "human": "revision-rebuilt-pending-human",
        "order": 22,
    },
    "funeral_ritual": {
        "title": "Funeral With No Instructions",
        "group": "Interaction II",
        "summary": "The prompt says only “Grieve.” Discover a five-stage memorial ritual through affordances, tools, persistent state, and story.",
        "axes": ["implicit ritual", "affordances", "coverage drag"],
        "difficulty": "hard",
        "accent": "#aab8ff",
        "human": "browser-verified",
        "order": 23,
    },
    "slime_commute": {
        "title": "Slime Commute",
        "group": "Interaction II",
        "summary": "Cross a fixed-step collision world of traffic, rails, water, and moving support logs that physically carry the player between inputs.",
        "axes": ["continuous collision", "realtime control", "moving support"],
        "difficulty": "hard",
        "accent": "#8cff62",
        "human": "revision-rebuilt-pending-human",
        "order": 24,
    },
    "semantic_drag_drop_absurdity": {
        "title": "Semantic Drag-Drop Absurdity",
        "group": "Source-Grounded",
        "summary": "Hold two physical probes over unlabeled specimens, remember their transient responses, and route each one to a causally matching receiver.",
        "axes": ["active experimentation", "transient response", "causal routing"],
        "difficulty": "hard",
        "accent": "#ff8fb1",
        "human": "revision-rebuilt-pending-human",
        "order": 31,
    },
    "reload_interruption": {
        "title": "Reload Interruption",
        "group": "Source-Grounded",
        "summary": "Memorize a once-only seven-gesture reel, execute it physically, and continuously track moving overload sparks through two interruptions.",
        "axes": ["once-only memory", "continuous tracking", "interruption recovery"],
        "difficulty": "hard",
        "accent": "#ffc857",
        "human": "revision-rebuilt-pending-human",
        "order": 32,
    },
    "rotate_wrong_thing_upright": {
        "title": "Rotate the Wrong Thing Upright",
        "group": "Source-Grounded",
        "summary": "Manipulate a coupled tri-axis gimbal whose controls perturb one another, using front, side, and top projections to recover world plumb.",
        "axes": ["3D orientation", "coupled control", "multi-view inspection"],
        "difficulty": "hard",
        "accent": "#66d6ff",
        "human": "revision-rebuilt-pending-human",
        "order": 33,
    },
    "bureaucratic_signature_trap": {
        "title": "Bureaucratic Signature Trap",
        "group": "Source-Grounded",
        "summary": "Slide three translucent carbon sheets until their apertures coincide, then draw one dense closed countersignature without lifting.",
        "axes": ["layer alignment", "continuous drawing", "motor precision"],
        "difficulty": "hard",
        "accent": "#e5dfc5",
        "human": "revision-rebuilt-pending-human",
        "order": 34,
    },
    "wonky_text_hostile_rendering": {
        "title": "Anamorphic Registration Press",
        "group": "Source-Grounded",
        "summary": "Continuously register three nonlinear color plates, lock each impression, and press the resolved image—without OCR input.",
        "axes": ["optical registration", "continuous manipulation", "state locking"],
        "difficulty": "hard",
        "accent": "#ff7f63",
        "human": "revision-rebuilt-pending-human",
        "order": 35,
    },
    "temporal_memory_first_change": {
        "title": "First Change Memory",
        "group": "Source-Grounded",
        "summary": "Track a brief reverting change through an active cursor lens, survive occlusion and later decoys, then recover its carrier after a shuffle.",
        "axes": ["active tracking", "transient memory", "identity persistence"],
        "difficulty": "hard",
        "accent": "#9b8cff",
        "human": "revision-rebuilt-pending-human",
        "order": 36,
    },
    "surreal_apple_on_tree_grid": {
        "title": "Parallax Orchard",
        "group": "Visual Core",
        "summary": "Orbit an analytic 3D orchard where every stem appears attached head-on, then physically harvest only the contacts that remain joined under parallax.",
        "axes": ["3D parallax", "continuous orbit", "physical drag"],
        "difficulty": "hard",
        "accent": "#f05b4f",
        "human": "next-ten-audit-pending-human",
        "order": 41,
    },
    "cursor_lens_reveal": {
        "title": "Polarized Palimpsest",
        "group": "Visual Core",
        "summary": "Tune a local lens, scan a live plate, and keep five sequential moving echoes inside the glass long enough to fix them before their trails decay.",
        "axes": ["active vision", "polarizer control", "moving hold"],
        "difficulty": "hard",
        "accent": "#f2b84b",
        "human": "next-ten-audit-pending-human",
        "order": 42,
    },
    "modifier_stack_image_grid": {
        "title": "Kinetic Restoration Press",
        "group": "Visual Core",
        "summary": "Watch transient corruption films, assemble each inverse stack in reverse order, and maintain contact while pulling three artifacts through a restoration rail.",
        "axes": ["transient memory", "ordered manipulation", "continuous tracing"],
        "difficulty": "hard",
        "accent": "#66c6a4",
        "human": "next-ten-audit-pending-human",
        "order": 43,
    },
    "board_game_captcha": {
        "title": "Gyroscopic Tilt Board",
        "group": "Visual Core",
        "summary": "Continuously tilt a deterministic physical board, manage inertia and collisions, light three ordered gates, avoid wells, and settle the ball in its cup.",
        "axes": ["closed-loop control", "collision physics", "inertial navigation"],
        "difficulty": "extreme",
        "accent": "#e0c274",
        "human": "next-ten-audit-pending-human",
        "order": 44,
    },
}


ROADMAP_CONCEPTS: tuple[dict[str, Any], ...] = (
    {
        "mechanic_id": "shadow_crime_lab",
        "title": "Shadow Crime Lab",
        "group": "Interaction III",
        "summary": "Move a real light through a room. Every honest shadow responds to the probe; one forged shadow refuses to obey the scene.",
        "instruction": "Move the light. Identify the shadow that cannot be physically true.",
        "axes": ["causal probing", "dynamic light", "visual physics"],
        "difficulty": "hard",
        "accent": "#ff735c",
        "order": 50,
        "concept_index": "03.01",
        "motif": "◒",
        "source_anchors": ["arkose-dice-complaint-corpus/wrong-shadow", "nextgen-captchas/Shadow_Plausible"],
    },
    {
        "mechanic_id": "craftcha_alchemy_bench",
        "title": "CRAFTCHA: Alchemy Bench",
        "group": "Interaction III",
        "summary": "Remember a briefly shown recipe, transform raw materials through several intermediate states, and assemble the final machine without exhausting the bench.",
        "instruction": "Study the recipe. Craft the requested device from the materials provided.",
        "axes": ["long-horizon state", "visual recipe", "dragging"],
        "difficulty": "hard",
        "accent": "#f0ba54",
        "order": 51,
        "concept_index": "03.02",
        "motif": "⬡",
        "source_anchors": ["neal-im-not-a-robot/level-21-craftcha"],
    },
    {
        "mechanic_id": "occlusion_shell_swindle",
        "title": "Occlusion Shell Swindle",
        "group": "Interaction III",
        "summary": "Track a marked carrier through three shuffles and actively inspect a timed peephole whose physical shuttle makes every under-cover transfer human-observable.",
        "instruction": "Track the token and hold the cursor over each pulsing peephole to read the shuttle before selecting the final carrier.",
        "axes": ["object permanence", "timed local inspection", "temporal tracking"],
        "difficulty": "extreme",
        "accent": "#a58cff",
        "order": 52,
        "concept_index": "03.03",
        "motif": "◉",
        "source_anchors": ["neal-im-not-a-robot/level-35-shuffle", "nextgen-captchas/Temporal_Object_Continuity"],
    },
    {
        "mechanic_id": "ribbon_switchboard",
        "title": "Ribbon Switchboard",
        "group": "Interaction III",
        "summary": "Guide the cursor along one woven ribbon through dense over-under crossings until it reaches the ribbon's real terminal.",
        "instruction": "Follow the marked ribbon from its source to the correct terminal without leaving it.",
        "axes": ["hover tracing", "local depth", "fine motor"],
        "difficulty": "extreme",
        "accent": "#5fe0d0",
        "order": 53,
        "concept_index": "03.04",
        "motif": "∿",
        "source_anchors": ["nextgen-captchas/Illusory_Ribbons", "captcha-royale/pathtracing"],
    },
    {
        "mechanic_id": "magnetic_stripe_purgatory",
        "title": "Magnetic-Stripe Purgatory",
        "group": "Interaction III",
        "summary": "Insert and swipe several cards through temperamental readers, calibrating each drag from only TOO FAST, TOO SLOW, and BAD READ feedback.",
        "instruction": "Insert each card, then swipe it through its reader at an accepted speed.",
        "axes": ["timed drag", "motor calibration", "feedback loop"],
        "difficulty": "hard",
        "accent": "#65d8ff",
        "order": 54,
        "concept_index": "03.05",
        "motif": "▰",
        "source_anchors": ["captchaware/cardSwipe"],
    },
    {
        "mechanic_id": "trajectory_catcher",
        "title": "Trajectory Catcher",
        "group": "Interaction IV",
        "summary": "Observe an irregular moving path, then place and orient a catcher before the object emerges from behind a wall.",
        "instruction": "Watch the flight. Position the catcher where the object will reappear.",
        "axes": ["trajectory memory", "prediction", "timed placement"],
        "difficulty": "hard",
        "accent": "#ff7ba8",
        "order": 60,
        "concept_index": "04.01",
        "motif": "⤷",
        "source_anchors": ["nextgen-captchas/Trajectory_Recovery"],
    },
    {
        "mechanic_id": "impossible_panorama",
        "title": "Impossible Panorama",
        "group": "Interaction IV",
        "summary": "Search a 32-sector, depth-layered panorama, recognize one transient moving event among 108 landmarks, then frame, focus, and hold a stable eight-sample exposure.",
        "instruction": "Search the full panorama for the requested live event, frame it at inspection zoom, focus its true depth, and sustain the shutter hold.",
        "axes": ["active perception", "pan and zoom", "focus control"],
        "difficulty": "hard",
        "accent": "#6cc7ff",
        "order": 61,
        "concept_index": "04.02",
        "motif": "⊕",
        "source_anchors": ["neal-im-not-a-robot/level-23-panorama"],
    },
    {
        "mechanic_id": "flat_pack_compliance",
        "title": "Flat-Pack Compliance Test",
        "group": "Interaction IV",
        "summary": "Drag and rotate seven unfamiliar rigid parts into a six-joint keyed assembly, then keep it intact through a 36-step oscillating compliance test.",
        "instruction": "Build every keyed joint in the seven-part device, clear collisions, and survive the complete compliance waveform.",
        "axes": ["spatial assembly", "real joints", "physical validation"],
        "difficulty": "extreme",
        "accent": "#f3d66a",
        "order": 62,
        "concept_index": "04.03",
        "motif": "◫",
        "source_anchors": ["neal-im-not-a-robot/level-43-ikea"],
    },
    {
        "mechanic_id": "crash_deadline_hovercar",
        "title": "Crash-Deadline Hovercar",
        "group": "Interaction IV",
        "summary": "Steer an inertial vehicle around six collision obstacles while the pointer continuously tracks and dwells on five independently moving inspection sigils before the deadline.",
        "instruction": "Clear all five moving hover checks while continuously driving the obstacle course without a crash.",
        "axes": ["divided attention", "hover dwell", "keyboard control"],
        "difficulty": "extreme",
        "accent": "#b8ff58",
        "order": 63,
        "concept_index": "04.04",
        "motif": "↯",
        "source_anchors": ["hawke-gaming-voluntary-collaboration"],
    },
    {
        "mechanic_id": "robot_art_critic",
        "title": "Robot Art Critic",
        "group": "Interaction IV",
        "summary": "Draw one of eight structured objects in 10–14 meaningful strokes, inspect a real local recognizer's class margins, and revise without exceeding the tight budget.",
        "instruction": "Construct the requested object with the required stroke topology until the critic ranks it above every competing class.",
        "axes": ["iterative drawing", "classifier feedback", "stroke budget"],
        "difficulty": "extreme",
        "accent": "#ff8bf0",
        "order": 64,
        "concept_index": "04.05",
        "motif": "✎",
        "source_anchors": ["captchad-boardgame/yellow-room", "cursed-captchas-computer-vision"],
        "known_limitations": [
            "Closed-world fidelity boundary: the critic compares against a fixed prototype family, so a legitimate locomotive with a substantially different design can be rejected."
        ],
    },
    {
        "mechanic_id": "photograph_eats_the_room",
        "title": "The Photograph Eats the Room",
        "group": "Interaction V",
        "summary": "Capture useful geometry elsewhere, place and rotate the photograph in first-person space, then develop it so the pictured structure overwrites the room and becomes physically traversable.",
        "instruction": "Use photographs to reshape the room and reach the verification terminal.",
        "axes": ["reality editing", "3D placement", "geometry creation"],
        "difficulty": "extreme",
        "accent": "#ff7f66",
        "order": 80,
        "concept_index": "05.01",
        "motif": "▣",
        "source_anchors": ["https://thunderfulgames.com/games/viewfinder/"],
    },
    {
        "mechanic_id": "clockwork_doppelganger_customs",
        "title": "Clockwork Doppelgänger Customs",
        "group": "Interaction V",
        "summary": "Record short action loops that become endlessly repeating ghost operators, then synchronize several past versions of yourself to catch, transfer, stamp, and deliver one passport.",
        "instruction": "Build a working verification line from recordings of your own actions.",
        "axes": ["action recording", "loop synchronization", "self-coordination"],
        "difficulty": "extreme",
        "accent": "#f5ca58",
        "order": 81,
        "concept_index": "05.02",
        "motif": "⧖",
        "source_anchors": ["https://pontoco.com/the-last-clockwinder"],
    },
    {
        "mechanic_id": "recursive_dollhouse_smuggling",
        "title": "Recursive Dollhouse Smuggling",
        "group": "Interaction V",
        "summary": "Manipulate synchronized miniature, human-scale, and giant copies of the same room so that objects transferred or moved at one scale alter obstacles at the others.",
        "instruction": "Move the parcel through the nested rooms and deliver it at the correct scale.",
        "axes": ["recursive worlds", "cross-scale state", "3D manipulation"],
        "difficulty": "extreme",
        "accent": "#a88dff",
        "order": 82,
        "concept_index": "05.03",
        "motif": "▦",
        "source_anchors": ["https://www.vertigo-games.com/games/a-fishermans-tale/"],
    },
    {
        "mechanic_id": "flat_prisoner",
        "title": "The Flat Prisoner",
        "group": "Interaction V",
        "summary": "Move a 3D camera until distant surfaces overlap in screen space, freeze that projection, then guide a 2D prisoner across the temporary level created by the chosen viewpoint.",
        "instruction": "Reshape the projected level with the camera and guide the prisoner to the exit.",
        "axes": ["2D / 3D switching", "camera projection", "spatial traversal"],
        "difficulty": "extreme",
        "accent": "#64d9ff",
        "order": 83,
        "concept_index": "05.04",
        "motif": "▱",
        "source_anchors": ["https://www.digipen.edu/showcase/student-games/perspective"],
    },
    {
        "mechanic_id": "forced_perspective_moving_day",
        "title": "Forced-Perspective Moving Day",
        "group": "Interaction V",
        "summary": "Pick up ordinary objects and release them against surfaces so their physical scale becomes their apparent screen size, turning tiny signs into bridges and huge crates into slot-sized keys.",
        "instruction": "Resize the available objects through perspective and move the shipment through the impossible doorway.",
        "axes": ["forced perspective", "scale manipulation", "rigid-body placement"],
        "difficulty": "extreme",
        "accent": "#8ce67f",
        "order": 84,
        "concept_index": "05.05",
        "motif": "↗",
        "source_anchors": ["https://pillowcastle.org/presskits/superliminal/"],
    },
    {
        "mechanic_id": "lidar_blacksite",
        "title": "LIDAR Blacksite",
        "group": "Interaction VI",
        "summary": "Navigate a lightless 3D facility by spraying temporary point-cloud samples into the world, rescanning occluded surfaces from new positions, and carrying a beacon through geometry that keeps fading away.",
        "instruction": "Scan the blacksite, recover the verification beacon, and escape with it.",
        "axes": ["active sensing", "3D memory", "first-person navigation"],
        "difficulty": "extreme",
        "accent": "#5fe8bd",
        "order": 90,
        "concept_index": "06.01",
        "motif": "⋰",
        "source_anchors": ["https://www.introversion.co.uk/scannersombre/", "nextgen-captchas/Structure_From_Motion"],
    },
    {
        "mechanic_id": "tomographic_baggage_surgery",
        "title": "Tomographic Baggage Surgery",
        "group": "Interaction VI",
        "summary": "Sweep and rotate an X-ray slice through an opaque suitcase, reconstruct the target's volumetric position, then guide an extraction probe from orthogonal views without touching decoys.",
        "instruction": "Locate and extract the marked contraband without damaging any innocent object.",
        "axes": ["volumetric scanning", "cross-view registration", "3D intervention"],
        "difficulty": "extreme",
        "accent": "#ff78a9",
        "order": 91,
        "concept_index": "06.02",
        "motif": "⌁",
        "source_anchors": ["nextgen-captchas/3D_Viewpoint", "nextgen-captchas/Backmost_Layer"],
    },
    {
        "mechanic_id": "three_camera_claw_machine",
        "title": "Three-Camera Claw Machine",
        "group": "Interaction VI",
        "summary": "Operate an inertial six-axis claw using only staggered top, front, and side CCTV feeds, triangulating every correction while threading one marked artifact through an obstacle cage.",
        "instruction": "Retrieve the marked artifact using only the three camera feeds.",
        "axes": ["multi-view control", "teleoperation", "depth triangulation"],
        "difficulty": "extreme",
        "accent": "#f3a447",
        "order": 92,
        "concept_index": "06.03",
        "motif": "⋔",
        "source_anchors": ["nextgen-captchas/3D_Viewpoint", "nextgen-captchas/Trajectory_Recovery"],
    },
    {
        "mechanic_id": "zero_g_cable_autopsy",
        "title": "Zero-G Cable Autopsy",
        "group": "Interaction VI",
        "summary": "Rotate around a real constrained cable and operate two independent grippers to untangle it from pegs and rings without letting the deforming cable touch alarm contacts.",
        "instruction": "Free the cable using both grippers. Do not touch the red contacts.",
        "axes": ["deformable physics", "dual grippers", "topological manipulation"],
        "difficulty": "extreme",
        "accent": "#dc84ff",
        "order": 93,
        "concept_index": "06.04",
        "motif": "∾",
        "source_anchors": ["captcha-rpg/gordian-knot", "https://www.playstation.com/en-gb/games/tentacular/"],
    },
    {
        "mechanic_id": "portal_freight_oversized_parcel",
        "title": "Portal Freight: Oversized Parcel",
        "group": "Interaction VI",
        "summary": "Place linked portals and physically thread a long parcel through both spaces while its position, orientation, velocity, and collisions transform across coordinate frames.",
        "instruction": "Deliver the oversized parcel intact through the portal test chamber.",
        "axes": ["portal geometry", "coordinate transforms", "cross-space physics"],
        "difficulty": "extreme",
        "accent": "#69bfff",
        "order": 94,
        "concept_index": "06.05",
        "motif": "◎",
        "source_anchors": ["https://store.steampowered.com/app/620/Portal_2/"],
    },
)

ROADMAP_PROFILES = {
    str(concept["mechanic_id"]): concept
    for concept in ROADMAP_CONCEPTS
}


INCUBATOR_CONCEPTS: tuple[dict[str, Any], ...] = (
    {
        "mechanic_id": "wrong_number",
        "title": "Wrong Number",
        "group": "Incubator",
        "summary": "Explore seven live carriers, identify the only authentic waveform, and continuously correct its phase and skew through a drifting 4.8-second lock trial.",
        "instruction": "Find the authentic carrier, then keep correcting phase and skew until it stays locked through both the full trial and final observation window.",
        "axes": ["analog tuning", "closed-loop control", "sustained temporal lock"],
        "difficulty": "extreme",
        "accent": "#ff8066",
        "order": 70,
        "concept_index": "IN.01",
        "motif": "☎",
        "source_anchors": ["captchaware/phoneVerification"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "bomb_manual_from_hell",
        "title": "Bomb Manual From Hell",
        "group": "Incubator",
        "summary": "Drag, rotate, and mirror five transparent manual plates onto asymmetric key pins; their 25 layered apertures leave exactly one of nine wires fully exposed.",
        "instruction": "Register all five acetate plates, inspect their combined apertures, then irreversibly cut the one exposed wire.",
        "axes": ["spatial registration", "layered occlusion", "irreversible action"],
        "difficulty": "extreme",
        "accent": "#ff4f49",
        "order": 71,
        "concept_index": "IN.02",
        "motif": "✂",
        "source_anchors": ["modrinth-evil-captcha/cut-the-wire"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "dead_mans_switch",
        "title": "Dead Man's Switch",
        "group": "Incubator",
        "summary": "Continuously track a moving pressure pad with the mouse while navigating a 45–57 move keyboard route through five alternating barriers; stale tracking resets the run.",
        "instruction": "Follow the moving safety pad without losing pressure while guiding the vehicle through all five checkpoints to the dock.",
        "axes": ["mouse hold", "keyboard control", "dual-channel input"],
        "difficulty": "extreme",
        "accent": "#f4c84f",
        "order": 72,
        "concept_index": "IN.03",
        "motif": "●",
        "source_anchors": ["opencaptchaworld-benchmark/Hold_Button"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "blind_dice_courier",
        "title": "Blind Dice Courier",
        "group": "Incubator",
        "summary": "Track a labelled die's hidden 3D orientation across an 18×11 warehouse and roughly 60 rolls, using only four scanners to satisfy five alternating face gates.",
        "instruction": "Deliver the sealed die through all five face gates, reconstructing its orientation between sparse scanner reveals.",
        "axes": ["3D state tracking", "navigation", "working memory"],
        "difficulty": "hard",
        "accent": "#85d7ff",
        "order": 73,
        "concept_index": "IN.04",
        "motif": "◇",
        "source_anchors": ["nextgen-captchas-benchmark/Dice_Roll_Path"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "input_lag_forklift",
        "title": "Input-Lag Forklift",
        "group": "Incubator",
        "summary": "Solve a two-crate Sokoban route while every direction executes exactly one command late, preserving the queued control across pushes and tight recovery spaces.",
        "instruction": "Plan around the one-cycle control queue and dock both crates without deadlocking either one.",
        "axes": ["delayed controls", "causal inference", "recovery"],
        "difficulty": "extreme",
        "accent": "#f29b45",
        "order": 74,
        "concept_index": "IN.05",
        "motif": "↪",
        "source_anchors": ["captcha-chaos-live-game/delay", "captcha-royale/metamorphic"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "insider_trading_captcha",
        "title": "Insider Trading CAPTCHA",
        "group": "Incubator",
        "summary": "Trade a nonperiodic 34–38 tick market through a three-tick settlement queue, fees, and four-lot inventory while observing prices only as they arrive.",
        "instruction": "Manage delayed orders on the live irregular tape, reach the causal profit target, and finish with no pending orders or position.",
        "axes": ["temporal signal", "delayed consequences", "resource planning"],
        "difficulty": "hard",
        "accent": "#7fe3a1",
        "order": 75,
        "concept_index": "IN.06",
        "motif": "$",
        "source_anchors": ["neal-im-not-a-robot/level-28-day-trader"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "polyrhythm_customs",
        "title": "Polyrhythm Customs",
        "group": "Incubator",
        "summary": "Memorize several visual rhythms separately, then replay their interleaved taps, held notes, and chords across simultaneous lanes with forgiving timing windows.",
        "instruction": "Capture every lane and reproduce the combined rhythm with at least 85% accuracy.",
        "axes": ["temporal memory", "multi-lane timing", "held input"],
        "difficulty": "extreme",
        "accent": "#c99cff",
        "order": 76,
        "concept_index": "IN.07",
        "motif": "♫",
        "source_anchors": ["neal-im-not-a-robot/level-32-simon", "neal-im-not-a-robot/level-47-rhythm", "captchaware/simonSays"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "exact_change_candy_cascade",
        "title": "Exact-Change Candy Cascade",
        "group": "Incubator",
        "summary": "Manipulate a deterministic match-three board to land on an exact score within a move budget while cascades, multipliers, and one forbidden candy punish greedy play.",
        "instruction": "Finish with exactly the requested score before the move counter reaches zero.",
        "axes": ["cascading state", "exact planning", "move budget"],
        "difficulty": "hard",
        "accent": "#ff79ad",
        "order": 77,
        "concept_index": "IN.08",
        "motif": "◆",
        "source_anchors": ["neal-im-not-a-robot/level-36-not-candy-crush"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "tiny_fps_customs",
        "title": "Tiny FPS Customs",
        "group": "Incubator",
        "summary": "Navigate a miniature ray-cast dungeon, find three wanted creatures, aim and fire, and avoid harming nearly identical protected decoys.",
        "instruction": "Eliminate the three creatures on the wanted poster. Protected creatures must survive.",
        "axes": ["3D navigation", "camera aiming", "target tracking"],
        "difficulty": "extreme",
        "accent": "#e9ef75",
        "order": 78,
        "concept_index": "IN.09",
        "motif": "⌖",
        "source_anchors": ["doom-captcha-rauchg", "doomcaptcha-vivirenremoto"],
        "stage": "incubator",
    },
    {
        "mechanic_id": "thirty_year_time_wheel",
        "title": "Thirty-Year Time Wheel",
        "group": "Incubator",
        "summary": "Crank an inertial calendar wheel whose inner, middle, and outer grips advance days, months, or years, then brake and reverse out of inevitable overshoot.",
        "instruction": "Use the wheel to set the calendar to the requested date, then lock it in place.",
        "axes": ["continuous dragging", "inertia", "precision correction"],
        "difficulty": "hard",
        "accent": "#62ddcf",
        "order": 79,
        "concept_index": "IN.10",
        "motif": "⟳",
        "source_anchors": ["captcha-rpg/time-wheel"],
        "stage": "incubator",
    },
)

INCUBATOR_PROFILES = {
    str(concept["mechanic_id"]): concept
    for concept in INCUBATOR_CONCEPTS
}


COVER_FILES = {
    "surreal_apple_on_tree_grid": "evidence/next_ten_audit_v1/surreal_apple_on_tree_grid-active-side-parallax.png",
    "cursor_lens_reveal": "evidence/next_ten_audit_v1/cursor_lens_reveal-tuned-moving-echo.png",
    "modifier_stack_image_grid": "evidence/next_ten_audit_v1/modifier_stack_image_grid-inverse-stack-armed.png",
    "board_game_captcha": "evidence/next_ten_audit_v1/board_game_captcha-three-lamps-and-cup.png",
    "impossible_panorama": "evidence/next_ten_difficulty_v3/impossible_panorama-active-stable-hold.png",
    "flat_pack_compliance": "evidence/next_ten_difficulty_v3/flat_pack_compliance-oscillating-load-live.png",
    "crash_deadline_hovercar": "evidence/next_ten_difficulty_v3/crash_deadline_hovercar-simultaneous-drive-hover-dwell.png",
    "robot_art_critic": "evidence/next_ten_difficulty_v3/robot_art_critic-accepted-drawing-before-review.png",
    "wrong_number": "evidence/next_ten_difficulty_v3/wrong_number-active-drift-correction.png",
    "bomb_manual_from_hell": "evidence/next_ten_difficulty_v3/bomb_manual_from_hell-all-plate-aperture-intersection.png",
    "dead_mans_switch": "evidence/next_ten_difficulty_v3/dead_mans_switch-active-moving-pressure-track.png",
    "blind_dice_courier": "evidence/next_ten_difficulty_v3/blind_dice_courier-active-blind-roll.png",
    "input_lag_forklift": "evidence/next_ten_difficulty_v3/input_lag_forklift-active-delay.png",
    "insider_trading_captcha": "evidence/next_ten_difficulty_v3/insider_trading_captcha-solved-final-settlement.png",
}


def _read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _title(value: str) -> str:
    return " ".join(part.capitalize() for part in value.replace("_env", "").split("_"))


def _media_url(path: Path) -> str:
    relative = path.resolve().relative_to(BENCHMARK_ROOT.resolve())
    return f"/media/{relative.as_posix()}"


def _evidence_paths(mechanic_id: str, environment_dir: Path) -> list[Path]:
    paths = list((EVIDENCE_ROOT / "next_ten_difficulty_v3").glob(f"{mechanic_id}-*.png"))
    if not paths:
        paths = list((EVIDENCE_ROOT / "next_ten_audit_v2").glob(f"{mechanic_id}-*.png"))
    if not paths:
        paths = list((EVIDENCE_ROOT / "next_ten_audit_v1").glob(f"{mechanic_id}-*.png"))
    if not paths:
        paths = list((EVIDENCE_ROOT / "reviewed_overhaul_v1").glob(f"{mechanic_id}-*.png"))
    if paths:
        pass
    elif mechanic_id in {
        "motion_only_ghost_jigsaw",
        "cursor_constellation_hunt",
        "parallel_grillmaster",
        "rotating_keyboard",
        "slot_reel_capture",
    }:
        paths = list((EVIDENCE_ROOT / "interaction_first_five_v1").glob(f"{mechanic_id}-*.png"))
    elif mechanic_id in {"domino_autopsy", "consequences_boss", "popup_exorcist", "funeral_ritual", "slime_commute"}:
        paths = list((EVIDENCE_ROOT / "interaction_second_five_v1").glob(f"{mechanic_id}-*.png"))
    else:
        for batch_dir in sorted(EVIDENCE_ROOT.glob("incubator_batch_*_v1")):
            paths.extend(batch_dir.glob(f"{mechanic_id}-*.png"))

    if not paths and mechanic_id in {
        "semantic_drag_drop_absurdity",
        "reload_interruption",
        "rotate_wrong_thing_upright",
        "bureaucratic_signature_trap",
        "wonky_text_hostile_rendering",
        "temporal_memory_first_change",
    }:
        paths = list((EVIDENCE_ROOT / "source_mechanics_v1").glob(f"{mechanic_id}-*.png"))
    elif not paths:
        folder_map = {
            "surreal_apple_on_tree_grid": "apple_grid_v1",
            "cursor_lens_reveal": "cursor_lens_v1",
            "modifier_stack_image_grid": "modifier_stack_v1",
            "board_game_captcha": "board_game_v1",
        }
        folder = folder_map.get(mechanic_id)
        paths = list((EVIDENCE_ROOT / folder).glob("*.png")) if folder else []
        if not paths and environment_dir.joinpath("artifacts").is_dir():
            paths = list(environment_dir.glob("artifacts/episode_*/frame_00000.png"))

    def evidence_rank(path: Path) -> tuple[int, str]:
        name = path.name.lower()
        if "cheat" in name:
            return (99, name)
        if "initial" in name or "frame_00000" in name:
            return (0, name)
        if any(token in name for token in ("active", "motion-frame", "target-scan", "selected", "revealed", "arrival", "impact")):
            return (1, name)
        if "solved" in name or "ready" in name or "exposed" in name:
            return (2, name)
        if "pass" in name:
            return (3, name)
        if "fail" in name:
            return (4, name)
        return (5, name)

    return [path for path in sorted(set(paths), key=evidence_rank) if "cheat" not in path.name.lower()][:8]


def _cover_path(mechanic_id: str, evidence: list[Path]) -> Path | None:
    explicit = COVER_FILES.get(mechanic_id)
    if explicit:
        candidate = BENCHMARK_ROOT / explicit
        if candidate.exists():
            return candidate
    preferred = ("active", "solved", "impact", "selected", "revealed", "pass", "initial")
    for token in preferred:
        match = next((path for path in evidence if token in path.name.lower()), None)
        if match:
            return match
    return evidence[0] if evidence else None


def _validation_summaries() -> dict[str, dict[str, Any]]:
    output: dict[str, dict[str, Any]] = {}
    summaries = [
        EVIDENCE_ROOT / "interaction_first_five_v1" / "summary.json",
        EVIDENCE_ROOT / "interaction_second_five_v1" / "summary.json",
        *sorted(EVIDENCE_ROOT.glob("incubator_batch_*_v1/summary.json")),
        EVIDENCE_ROOT / "reviewed_overhaul_v1" / "summary.json",
        EVIDENCE_ROOT / "next_ten_audit_v1" / "summary.json",
        EVIDENCE_ROOT / "next_ten_audit_v2" / "summary.json",
        EVIDENCE_ROOT / "next_ten_difficulty_v3" / "summary.json",
    ]
    for summary_path in summaries:
        payload = _read_json(summary_path)
        for mechanic_id, result in (payload.get("mechanics") or {}).items():
            output[str(mechanic_id)] = {
                "ok": bool(result.get("ok")),
                "server_grade": result.get("server_grade"),
                "verifier": result.get("verifier"),
            }
    return output


def _solution_videos() -> dict[str, dict[str, Any]]:
    """Return the newest complete recording for each mechanic.

    Evidence directories are append-only, so older audit recordings can coexist
    with newer frozen-contract captures.  The manifest timestamp—not a hard-coded
    folder name—selects the current recording while preserving that history.
    """
    candidates: dict[str, tuple[tuple[str, int], dict[str, Any]]] = {}
    for manifest_path in EVIDENCE_ROOT.glob("**/solution_videos/manifest.json"):
        payload = _read_json(manifest_path)
        videos = payload.get("videos")
        if not isinstance(videos, dict):
            continue
        generated_at = str(payload.get("generated_at") or "")
        priority = (generated_at, manifest_path.stat().st_mtime_ns)
        for mechanic_id, raw_record in videos.items():
            if not isinstance(raw_record, dict):
                continue
            mp4_name = raw_record.get("mp4")
            webm_name = raw_record.get("webm")
            if not isinstance(mp4_name, str):
                continue
            mp4_path = manifest_path.parent / mp4_name
            webm_path = manifest_path.parent / webm_name if isinstance(webm_name, str) else None
            if not mp4_path.is_file():
                continue
            media = raw_record.get("media") if isinstance(raw_record.get("media"), dict) else {}
            replay_passed = all(
                bool((raw_record.get(key) or {}).get("passed"))
                for key in ("server_grade", "direct_grade", "verifier")
            )
            record = {
                "title": str(raw_record.get("title") or _title(str(mechanic_id))),
                "approach": str(raw_record.get("approach") or "Verified solution replay."),
                "mp4_url": _media_url(mp4_path),
                "webm_url": _media_url(webm_path) if webm_path and webm_path.is_file() else None,
                "duration_seconds": media.get("duration_seconds"),
                "width": media.get("width"),
                "height": media.get("height"),
                "codec": media.get("codec"),
                "generated_at": generated_at,
                "evidence_set": manifest_path.relative_to(EVIDENCE_ROOT).parts[0],
                "manifest_url": _media_url(manifest_path),
                "verified": bool(payload.get("ok") and replay_passed),
                "frozen_contract_verified": bool(payload.get("frozen_contract_verified")),
            }
            existing = candidates.get(str(mechanic_id))
            if existing is None or priority > existing[0]:
                candidates[str(mechanic_id)] = (priority, record)
    return {mechanic_id: record for mechanic_id, (_, record) in candidates.items()}


def build_catalog() -> dict[str, Any]:
    validation = _validation_summaries()
    solution_videos = _solution_videos()
    environments: list[dict[str, Any]] = []
    for environment_dir in sorted(ENVIRONMENTS_ROOT.glob("*_env")):
        env_data = _read_json(environment_dir / "env.json")
        task_dirs = sorted(path for path in environment_dir.joinpath("tasks").glob("*") if path.is_dir())
        tasks: list[dict[str, Any]] = []
        for task_dir in task_dirs:
            task_data = _read_json(task_dir / "task.json")
            tasks.append({
                "id": task_dir.name,
                "spec_id": task_data.get("id", task_dir.name),
                "description": task_data.get("description", ""),
                "instruction": task_data.get("natural_language") or task_data.get("description") or "",
                "timeout": task_data.get("timeout"),
                "metadata": task_data.get("metadata") or {},
            })

        primary = tasks[0] if tasks else {"metadata": {}, "description": "", "instruction": ""}
        metadata = primary.get("metadata") or {}
        mechanic_id = str(metadata.get("mechanic_id") or environment_dir.name.removesuffix("_env"))
        profile = (
            PROFILES.get(mechanic_id)
            or INCUBATOR_PROFILES.get(mechanic_id)
            or ROADMAP_PROFILES.get(mechanic_id, {})
        )
        status = str(metadata.get("status") or "scaffolded")
        evidence = _evidence_paths(mechanic_id, environment_dir)
        cover = _cover_path(mechanic_id, evidence)
        built = status == "prototype_visual_candidate"
        rejected = status == "rejected_infra_pilot"
        group = profile.get("group") or ("Archive" if rejected else "Incubator")
        source_anchors = metadata.get("source_anchors") or []
        if isinstance(source_anchors, str):
            source_anchors = [source_anchors]
        known_limitations = profile.get("known_limitations") or []
        if isinstance(known_limitations, str):
            known_limitations = [known_limitations]

        environments.append({
            "id": environment_dir.name,
            "spec_id": env_data.get("id", environment_dir.name),
            "mechanic_id": mechanic_id,
            "title": profile.get("title") or _title(mechanic_id),
            "summary": profile.get("summary") or primary.get("description") or primary.get("instruction") or "Mechanic definition in the Weird CAPTCHA Gym incubator.",
            "instruction": primary.get("instruction", ""),
            "status": status,
            "stage": "built" if built else ("rejected" if rejected else "scaffold"),
            "group": group,
            "axes": profile.get("axes") or ["incubator"],
            "difficulty": profile.get("difficulty") or "unrated",
            "accent": profile.get("accent") or "#82908c",
            "human_status": profile.get("human") or ("archived" if rejected else "not-tested"),
            "order": int(profile.get("order", 1000)),
            "source_anchors": source_anchors,
            "known_limitations": known_limitations,
            "design_status": metadata.get("design_status"),
            "tasks": tasks,
            "task_count": len(tasks),
            "cover": _media_url(cover) if cover else None,
            "screenshots": [{"url": _media_url(path), "name": path.stem.replace("_", " ").replace("-", " ")} for path in evidence],
            "validation": validation.get(mechanic_id, {"ok": bool(evidence) and built}),
            "solution_video": solution_videos.get(mechanic_id),
            "launchable": bool(tasks),
            "environment_path": str(environment_dir.relative_to(REPO_ROOT)),
        })

    existing_mechanics = {item["mechanic_id"] for item in environments}
    for concept in (*ROADMAP_CONCEPTS, *INCUBATOR_CONCEPTS):
        mechanic_id = str(concept["mechanic_id"])
        if mechanic_id in existing_mechanics:
            continue
        stage = str(concept.get("stage") or "concept")
        roadmap = stage == "concept"
        environments.append({
            "id": f"{mechanic_id}_env",
            "spec_id": f"weird_captcha_gym.{mechanic_id}@{'roadmap' if roadmap else 'incubator'}",
            "mechanic_id": mechanic_id,
            "title": concept["title"],
            "summary": concept["summary"],
            "instruction": concept["instruction"],
            "status": "roadmap_concept" if roadmap else "incubator_concept",
            "stage": stage,
            "group": concept["group"],
            "axes": concept["axes"],
            "difficulty": concept["difficulty"],
            "accent": concept["accent"],
            "human_status": "design-selected" if roadmap else "incubator-candidate",
            "order": int(concept["order"]),
            "source_anchors": concept["source_anchors"],
            "known_limitations": concept.get("known_limitations") or [],
            "design_status": "roadmap_selected_not_implemented" if roadmap else "incubator_candidate_not_implemented",
            "tasks": [],
            "task_count": 0,
            "cover": None,
            "screenshots": [],
            "validation": {"ok": False},
            "solution_video": None,
            "launchable": False,
            "environment_path": None,
            "concept_index": concept["concept_index"],
            "motif": concept["motif"],
        })

    environments.sort(key=lambda item: (item["order"], item["title"].lower()))
    groups: list[dict[str, Any]] = []
    for group_name in ("Interaction I", "Interaction II", "Interaction III", "Interaction IV", "Interaction V", "Interaction VI", "Source-Grounded", "Visual Core", "Incubator", "Archive"):
        members = [item for item in environments if item["group"] == group_name]
        if members:
            groups.append({"name": group_name, "count": len(members)})
    stats = {
        "total": len(environments),
        "built": sum(item["stage"] == "built" for item in environments),
        "browser_verified": sum(bool(item["validation"].get("ok")) for item in environments),
        "human_touched": sum(item["stage"] == "built" and item["human_status"] in DIRECT_HUMAN_STATUSES for item in environments),
        "evidence_frames": sum(len(item["screenshots"]) for item in environments),
        "solution_videos": sum(bool(item["solution_video"]) for item in environments),
        "scaffolds": sum(item["stage"] == "scaffold" for item in environments),
        "concepts": sum(item["stage"] == "concept" for item in environments),
        "incubator_candidates": sum(item["stage"] == "incubator" for item in environments),
    }
    return {
        "benchmark": {
            "id": "weird_captcha_gym",
            "title": "CAPTCHA Bench",
            "tagline": "An observatory for interaction-first visual puzzles.",
            "principle": "A screenshot should not be enough.",
        },
        "stats": stats,
        "groups": groups,
        "environments": environments,
    }


def environment_index() -> dict[str, dict[str, Any]]:
    return {item["id"]: item for item in build_catalog()["environments"]}


__all__ = ["BENCHMARK_ROOT", "REPO_ROOT", "build_catalog", "environment_index"]
