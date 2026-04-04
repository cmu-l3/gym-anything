# Study Dialogue Delivery Task

**Difficulty**: 🟡 Medium  
**Skills**: A-B repeat loop, snapshot management, time display, workflow setup  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Configure VLC for voice acting reference study by setting up an A-B repeat loop, enabling time display, configuring snapshot settings, and capturing reference snapshots of key emotional moments.

## Task Description

A voice actor needs to study a specific 8-second dialogue segment repeatedly while taking snapshots of facial expressions. The agent must:

1. Load reference video (`dialogue_reference.mp4`)
2. Set up A-B repeat loop for segment 10.5s to 18.5s
3. Enable time display for precise timing notation
4. Configure snapshots to save to `/home/ga/Pictures/voice_acting_reference/`
5. Take at least 3 reference snapshots at different emotional moments

## Expected Results

- A-B loop configured (10.5s - 18.5s)
- Time display visible during playback
- Snapshot directory: `/home/ga/Pictures/voice_acting_reference/`
- Snapshot format: PNG
- At least 3 valid snapshot files created

## Verification Criteria

1. ✅ **Snapshot Configuration**: Directory and format set correctly in VLC config
2. ✅ **Time Display**: OSD or time display enabled
3. ✅ **Snapshots Created**: At least 3 snapshot files exist
4. ✅ **Snapshot Validity**: Images are valid PNG format with reasonable size

**Pass Threshold**: 75%

## Skills Tested

- A-B repeat loop setup (Advanced Controls or keyboard shortcuts)
- Snapshot directory configuration
- Time display/OSD configuration
- Precise timestamp seeking
- Workflow coordination (multiple features working together)

## Controls

### A-B Repeat:
- **Advanced Controls**: View → Advanced Controls (shows A-B loop button)
- **Keyboard**: Press `Shift+L` at point A, seek to point B, press `Shift+L` again
- **Alternative**: Playback → Custom Bookmarks (version dependent)

### Snapshots:
- **Keyboard**: `Shift+S` to capture
- **Menu**: Video → Take Snapshot
- **Config**: Tools → Preferences → Video → snapshot settings

### Time Display:
- **OSD**: Tools → Preferences → Video → On Screen Display
- **Keyboard**: `T` to toggle time display (version dependent)

### Seeking:
- **Precise**: Ctrl+T for "Go to Time" dialog
- **Keyboard**: `Shift+Right` (jump +5s), `Shift+Left` (jump -5s)
- **Click**: Progress bar

## Notes

This task simulates a real professional workflow where voice actors study reference footage. The combination of loop, timing, and snapshots requires coordinating multiple VLC features.