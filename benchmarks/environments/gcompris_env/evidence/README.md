# GCompris Environment — Evidence Documentation

**Date**: 2026-02-18
**GCompris version**: 2.3 (Ubuntu 22.04 `gcompris-qt` package)
**Base image**: `ubuntu-gnome-systemd_highres`
**Resolution**: 1920×1080

---

## Checklist

- [x] Environment boots successfully (pre_start installs gcompris-qt)
- [x] post_start warm-up launch completes without errors
- [x] All 5 task setup scripts execute correctly
- [x] All 5 task start states confirmed via independent screenshots
- [x] navigate_activity end-state (Learn additions running) confirmed via screenshot
- [x] Audio mute flag `-m` used throughout (no PulseAudio in VM)
- [x] First-run dialogs suppressed via config file

---

## Task Start States — Screenshots

### Task 1: navigate_activity
**File**: `ev_t1_navigate.png`
**End-state file**: `ev_t1_navigate_endstate.png`
**Start state**: GCompris showing Math/Numbers category, Numeration tab active. Tabs visible: Numeration, Arithmetic, Measures.
**Expected agent path**: click Arithmetic tab → find "Learn additions" tile → click to open.
**Confirmed**: Screenshot shows Math category with Numeration tab active and 7+ activity tiles visible (Baby keyboard, Draw numbers, Count the items, Guess a number, Learn digits, Learn quantities, Enumeration memory game). This is a non-empty, well-populated start state.
**End-state confirmed**: `ev_t1_navigate_endstate.png` shows the Learn additions activity open with addition problem "1 + 2" displayed and answer circles.

### Task 2: complete_maze
**File**: `ev_t2_maze.png`
**MD5**: `41f43f822aa06809d7328db6c62116f1`
**Expected**: GCompris showing the Dino/Sports category with Maze activity tile visible.
**Confirmed**: Screenshot shows Dino category with tiles: The football game, Maze, Memory game with images against Tux, Memory game with images, Programming maze, A simple drawing activity, Hexagon.

### Task 3: type_letters
**File**: `ev_t3_letters.png`
**Expected**: GCompris showing the ABC/Reading category > Letters tab, with "Alphabet sequence" tile visible.
**Confirmed**: Screenshot shows ABC category > Letters tab with: Baby keyboard, A baby word processor, Draw letters, Alphabet sequence, Click on a lowercase letter, Click on an uppercase letter, Simple letters.

### Task 4: color_mix
**File**: `ev_t4_color.png`
**Expected**: GCompris showing the Science/Experiment category with "Mixing paint colors" tile visible.
**Confirmed**: Screenshot shows Experiment tab with: Operate a canal lock, Explore farm animals, Binary bulbs, Gravity, Watercycle, Mixing paint colors, Mixing light colors.

### Task 5: memory_game
**File**: `ev_t5_memory.png`
**MD5**: `2c91e405b33632b344902a2826e28596`
**Expected**: GCompris showing the Dino/Sports category with "Memory game with images" tile visible (distinct from ev_t2_maze.png).
**Confirmed**: Screenshot independently taken after fresh GCompris launch. Shows Dino category with same tiles as task 2 but both memory game variants visible: "Memory game with images against Tux" and "Memory game with images". File hash is different from ev_t2_maze.png — confirmed independent capture.

**Note on tasks 2 and 5**: Both legitimately start in the Dino/Sports category (that's where both Maze and Memory game tiles live). The screenshots look visually similar but are independently captured fresh sessions with different file hashes.

---

## Log Snippets

### pre_start (install_gcompris.sh)
Confirmed via `apt` history log at `/var/log/apt/history.log`:

```
Commandline: apt-get install -y gcompris-qt gcompris-qt-data
Requested-By: ga (1000)
Install: gcompris-qt:amd64 (2.3-1), gcompris-qt-data:amd64 (2.3-1), [qt5 dependencies...]
End-Date: 2026-02-18  05:54:24
```

GCompris 2.3 installed successfully with all Qt5 dependencies.

### post_start (setup_gcompris.sh)
GCompris warm-up launch output:

```
QStandardPaths: XDG_RUNTIME_DIR not set, defaulting to '/tmp/runtime-ga'
exeCount set to:  1
notifyAudioEffects:  false
notifyAudioVoices:  false
PulseAudioService: pa_context_connect() failed   [expected — no PulseAudio]
qml: enter main.qml (run #1, ratio=2.076923..., dpi=100)
Downloading resource file "data2/voices-ogg/voices-en_US.rcc"
Local resource is up-to-date: "voices-en_US.rcc"
Successfully registered resource "/home/ga/.cache/KDE/gcompris-qt/data2/voices-ogg/voices-en_US.rcc"
GCompris window ready
```

### Task pre_task (complete_maze setup — /tmp/maze_setup.log):

```
=== Setting up complete_maze task ===
exeCount set to:  3
qml: enter main.qml (run #3, ratio=2.076923..., dpi=100)
Local resource is up-to-date: "voices-en_US.rcc"
GCompris window ready
=== complete_maze task setup complete ===
GCompris is now showing the Dino/Sports/Misc category.
The Maze activity icon (penguin in brick maze) is visible.
Agent must: click the Maze tile → use arrow keys to navigate penguin to the door.
```

### Task pre_task (type_letters setup — /tmp/tl_setup.log):

```
=== Setting up type_letters task ===
exeCount set to:  4
qml: enter main.qml (run #4, ratio=2.076923..., dpi=100)
GCompris window ready
=== type_letters task setup complete ===
GCompris is now showing the ABC/Reading/Letters category.
Visible activities include: Baby keyboard, A baby word processor, Draw letters,
Alphabet sequence, Click on a lowercase letter, Click on an uppercase letter, Simple letters.
```

---

## Screenshot File Inventory

| File | MD5 | Description |
|------|-----|-------------|
| `ev_t1_navigate.png` | `11199a82eb024314b0930130c03535bf` | Task 1 start: Math category, Numeration tab |
| `ev_t1_navigate_endstate.png` | (end state) | Task 1 end: Learn additions activity running |
| `ev_t2_maze.png` | `41f43f822aa06809d7328db6c62116f1` | Task 2 start: Dino category |
| `ev_t3_letters.png` | (verified) | Task 3 start: ABC/Letters tab |
| `ev_t4_color.png` | (verified) | Task 4 start: Science/Experiment tab |
| `ev_t5_memory.png` | `2c91e405b33632b344902a2826e28596` | Task 5 start: Dino category (independent capture) |

---

## Category Icon Coordinates (verified via visual_grounding)

| Category | Icon | VG Coord (1280×720) | Actual Coord (1920×1080) |
|----------|------|---------------------|--------------------------|
| Math/123 | sheep | (705, 65) | (1057, 97) |
| Science/Logic | penguin | (325, 65) | (487, 97) |
| Science/Experiment | pig | (455, 65) | (682, 97) |
| Dino/Sports | dinosaur | (575, 65) | (862, 97) |
| ABC/Reading | cow | (965, 65) | (1447, 97) |
| Games | frog | (1085, 65) | (1627, 97) |

---

## Key Activity Locations (Verified)

| Task | Category | Navigation | Activity Tile |
|------|----------|------------|---------------|
| navigate_activity | Math | Click sheep (1057,97) → Arithmetic tab (997,249) | Learn additions at VG (455,337) → actual (682,505) |
| complete_maze | Dino | Click dino (862,97) | Maze (2nd tile) |
| type_letters | ABC | Click cow (1447,97) → Letters tab | Alphabet sequence |
| color_mix | Science/Exp | Click pig (682,97) | Mixing paint colors |
| memory_game | Dino | Click dino (862,97) | Memory game with images (NOT "against Tux") |
