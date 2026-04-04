# Bookmark Interview Moments Task

**Difficulty**: 🟡 Medium  
**Skills**: Bookmark management, video navigation, annotation workflow  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Create named bookmarks at specific moments in a documentary interview video using VLC's Custom Bookmarks feature to facilitate later analysis.

## Real-World Context

Dr. Sarah Chen, a sociology PhD student, is analyzing hours of interview footage for her dissertation. She needs to mark specific moments where her subject discusses: (1) arrival experience, (2) housing challenges, and (3) community integration. Using VLC's bookmarks saves her from manually noting timestamps and allows instant navigation during writing.

## Task Description

The agent must:
1. Open a 12-minute interview video in VLC
2. Identify three specific discussion moments (marked by visual cues):
   - **~2:15**: "First day arriving in the city" 
   - **~5:40**: "Apartment search difficulties"
   - **~9:20**: "Finding community support"
3. Create custom bookmarks at these timestamps
4. Name bookmarks descriptively (arrival, housing, community)
5. Save bookmarks for persistence

## Expected Results

- Three bookmarks created at target timestamps (±5 seconds tolerance)
- Bookmarks named with relevant keywords
- Bookmarks accessible via VLC's bookmark menu
- Bookmark data persisted in VLC's media library or playlist files

## Verification Criteria

1. ✅ **Bookmark File Exists**: XSPF playlist or bookmark file found
2. ✅ **Three Bookmarks Present**: Correct number of bookmarks created
3. ✅ **Timestamps Accurate**: Bookmarks at ~135s, ~340s, ~560s (±5s)
4. ✅ **Names Descriptive**: Bookmark names contain relevant keywords

**Pass Threshold**: 75% (3/4 criteria)

## Skills Tested

- Video timeline navigation and seeking
- VLC's bookmark/chapter feature discovery
- Precise timestamp identification
- Descriptive naming conventions
- Understanding of annotation workflows
- File persistence verification

## Controls

- **Menu**: Playback → Custom Bookmarks → Manage
- **Keyboard Shortcuts**:
  - `Space`: Play/Pause
  - `Shift+Right/Left`: Jump 5 seconds forward/backward
  - `Ctrl+Right/Left`: Jump 1 minute forward/backward
- **Bookmark Dialog**: 
  - Add bookmark button
  - Edit bookmark name
  - Jump to bookmark

## Notes

VLC bookmarks are stored in XSPF (XML Shareable Playlist Format) files, typically in:
- Media library: `~/.local/share/vlc/ml.xspf`
- Video-specific playlists: `<video_name>.xspf`
- Custom bookmark files: `~/.config/vlc/bookmarks/`

The video contains yellow text overlays at key moments to help identify the correct timestamps.