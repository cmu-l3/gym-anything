# Bookmark Study Scenes Task

**Difficulty**: 🟡 Medium  
**Skills**: Bookmark creation, menu navigation, timestamp management  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Create custom bookmarks in VLC Media Player at specific timestamps in an educational video, enabling quick navigation between important scenes for study purposes.

## Task Description

The agent must:
1. Open VLC with a 25-minute educational video
2. Navigate to Playback → Custom Bookmarks → Manage
3. Create at least 5 bookmarks at distributed timestamps:
   - Introduction (~5% into video, ~1:15)
   - First Key Concept (~25%, ~6:15)
   - Second Key Concept (~50%, ~12:30)
   - Third Key Concept (~75%, ~18:45)
   - Summary (~90%, ~22:30)
4. Give each bookmark a descriptive name
5. Ensure bookmarks are saved persistently

## Expected Results

- At least 5 bookmarks created
- Each bookmark has a custom descriptive name (not "Bookmark 1", etc.)
- Bookmarks distributed throughout video (spanning 60%+ of duration)
- Bookmarks at reasonable positions (not at very start/end)
- Bookmarks saved in VLC's bookmark storage

## Verification Criteria

1. ✅ **Bookmark Count**: At least 5 bookmarks created
2. ✅ **Descriptive Names**: All bookmarks have custom names (3+ characters, not default)
3. ✅ **Well Distributed**: Bookmarks span at least 60% of video duration
4. ✅ **Reasonable Positions**: Bookmarks between 2% and 98% of video
5. ✅ **Persistent Storage**: Bookmarks saved in VLC storage files

**Pass Threshold**: 70% (3/5 criteria)

## Skills Tested

- Menu navigation (Playback → Custom Bookmarks)
- Timeline seeking and timestamp precision
- Bookmark dialog interaction
- Custom naming and text input
- Understanding of bookmark persistence

## Controls

- **Menu**: Playback → Custom Bookmarks → Manage
- **Timeline**: Click/drag to seek to timestamp
- **Create Button**: Add new bookmark at current position
- **Edit/Rename**: Modify bookmark names
- **Keyboard shortcuts**: 
  - `Ctrl+B`: Bookmarks (if configured)
  - Arrow keys: Seek forward/backward
  - Space: Play/Pause

## Notes

VLC stores bookmarks in the media library database (`~/.local/share/vlc/ml.xspf` or `ml.db`). The task simulates a real student preparing for exam review by bookmarking key concepts in a lecture video.