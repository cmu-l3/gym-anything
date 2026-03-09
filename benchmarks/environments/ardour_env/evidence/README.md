# Ardour Environment Evidence

## Verification Checklist

### Installation (pre_start hook)
- [x] `apt-get install ardour` completes successfully
- [x] Supporting packages installed: jackd2, alsa-utils, pulseaudio, ffmpeg, sox, xdotool, wmctrl, scrot
- [x] Real audio data downloaded: Moonlight Sonata from Internet Archive, Art of War narration from LibriVox/Internet Archive
- [x] Audio samples stored at `/home/ga/Audio/samples/moonlight_sonata.wav`

**Install log excerpt:**
```
=== Ardour installation complete ===
Audio samples in /home/ga/Audio/samples/:
total 5180
-rw-r--r-- 1 ga ga 5292092 Mar  4 03:07 moonlight_sonata.wav
```

### Setup (post_start hook)
- [x] Ardour binary detected: `ardour` (version 6.9)
- [x] Session created via CLI: `ardour6-new_session -s 44100 /home/ga/Audio/sessions/MyProject MyProject`
- [x] First-run wizard completed via UI automation (click Forward 10 times)
- [x] Audio engine configured: Dummy backend via config file injection (EngineStates XML)
- [x] Verification launch: session loads in 4s with no Audio/MIDI Setup dialog
- [x] Default audio track "Audio 1" added via Add Track/Bus/VCA dialog
- [x] Session saved (Ctrl+S) and closed cleanly (Ctrl+Q)
- [x] Desktop launcher created

**Setup log (full):**
```
=== Setting up Ardour DAW ===
Detected Ardour: ardour (version 6)
=== Creating Ardour session ===
Session created at /home/ga/Audio/sessions/MyProject
=== Warm-up launch of Ardour (step 1: complete wizard) ===
Waiting for Ardour window...
Ardour window found: 35651585
Clicking through wizard...
=== Configuring audio engine (Dummy backend) ===
EngineStates configured for Dummy backend
Config updated with Dummy backend engine state
=== Verification launch (indexing plugins, saving config) ===
Waiting for session to load...
Session loaded after 4s
Adding default audio track...
Clicking Add and Close at (1230,1049)...
Audio track added
Saving session...
Closing Ardour cleanly...
=== Warm-up complete ===
=== Ardour setup complete ===
```

---

## Task Verification (All 3 Tasks)

### Task 1: rename_track
**Goal:** Rename the "Audio 1" track to "Lead Vocals"

**Start state verified via visual_grounding:**
- [x] Ardour open with "MyProject - Ardour" title
- [x] "Audio 1" track visible in track list
- [x] Master bus visible
- [x] No dialogs blocking the UI
- [x] Audio engine running (44.1 kHz, Dummy backend)

**Completability evidence:**
- [x] Double-clicking "Audio 1" enters edit mode (track name highlighted in blue)
- [x] Typing "Lead Vocals" + Enter successfully renames the track
- [x] Full rename flow demonstrated end-to-end

**Task setup log:**
```
=== Setting up rename_track task ===
Launching Ardour with session: /home/ga/Audio/sessions/MyProject/MyProject.ardour
Waiting for Ardour window... Ardour window appeared after 4s
No Audio/MIDI Setup dialog found
Session loaded after 2s
=== Task setup complete ===
Agent should rename track 'Audio 1' to 'Lead Vocals'
```

**Screenshots:**
- `rename_track_start_state.png` - Ardour session with Audio 1 track visible
- `rename_track_edit_mode.png` - Track name in edit mode (highlighted blue)
- `rename_track_completed.png` - Track renamed to "Lead Vocals"

---

### Task 2: import_audio_track
**Goal:** Import `/home/ga/Audio/import_me.wav` into the session

**Start state verified via visual_grounding:**
- [x] Ardour open with session loaded
- [x] "Audio 1" track visible
- [x] Session menu accessible
- [x] No blocking dialogs
- [x] Import file exists: `/home/ga/Audio/import_me.wav` (5.3MB real Moonlight Sonata WAV)

**Completability evidence:**
- [x] Session menu opens with "Import (Ctrl+I)" option visible
- [x] Import dialog is accessible from Session > Import
- [x] Agent can navigate file browser to `/home/ga/Audio/import_me.wav`

**Task setup log:**
```
=== Setting up import_audio_track task ===
Tracks before import: 2
Launching Ardour with session: /home/ga/Audio/sessions/MyProject/MyProject.ardour
Waiting for Ardour window... Ardour window appeared after 4s
No Audio/MIDI Setup dialog found
Session loaded after 2s
=== Task setup complete ===
Agent should import /home/ga/Audio/import_me.wav into the session
```

**Screenshots:**
- `import_audio_start_state.png` - Ardour session ready for import
- `import_audio_session_menu.png` - Session menu showing Import option

---

### Task 3: export_session
**Goal:** Export the session to WAV format at `/home/ga/Audio/export/`

**Start state verified via visual_grounding:**
- [x] Ardour open with session loaded
- [x] "Audio 1" track visible
- [x] Session menu accessible with Export submenu
- [x] No blocking dialogs
- [x] Export directory exists and is empty: `/home/ga/Audio/export/`

**Completability evidence:**
- [x] Session menu opens with "Export" option visible (with submenu arrow)
- [x] Export submenu accessible from Session > Export
- [x] Agent can configure WAV output format and target directory

**Task setup log:**
```
=== Setting up export_session task ===
Launching Ardour with session: /home/ga/Audio/sessions/MyProject/MyProject.ardour
Waiting for Ardour window... Ardour window appeared after 4s
No Audio/MIDI Setup dialog found
Session loaded after 2s
=== Task setup complete ===
Agent should export the session to /home/ga/Audio/export/ as WAV
```

**Screenshots:**
- `export_session_start_state.png` - Ardour session ready for export
- `export_session_menu.png` - Session menu showing Export option

---

## Key Bugs Found and Fixed

1. **`pkill -f "ardour"` kills setup script**: `pkill -f` matches full command line, which includes "setup_**ardour**.sh". Fix: use `pkill -f "/usr/lib/ardour"` to match only the Ardour binary.

2. **Audio backend selection**: Ardour 6.9 on Ubuntu 22.04 has ALSA, JACK, Dummy, and PulseAudio backends. The Dummy backend ("None (Dummy)") works without any audio hardware or daemon, and is the most reliable choice.

3. **Audio/MIDI Setup dialog has variable position**: Dialog coordinates change between launches. Fix: use `xdotool getwindowgeometry` for window-relative coordinates.

4. **EngineStates must be in Extra > AudioMIDISetup section**: Writing EngineStates at the root level of the config doesn't work. Must be nested under `<Extra><AudioMIDISetup>`.

5. **Ctrl+Q doesn't save**: Must use Ctrl+S before Ctrl+Q to persist session changes (like added tracks).

## Timing

| Phase | Duration |
|-------|----------|
| pre_start (install) | ~90s (first run with download) |
| post_start (setup) | ~110s (wizard + config + verification) |
| pre_task (task setup) | ~15s (launch + wait for session) |
| Total | ~215s |
