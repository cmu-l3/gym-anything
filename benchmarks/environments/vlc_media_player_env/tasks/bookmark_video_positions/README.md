# Bookmark Video Positions Task

**Difficulty**: 🟡 Medium  
**Skills**: Bookmark management, media library, timestamp navigation  
**Duration**: 90-120 seconds  
**Steps**: ~35

## Objective

Create multiple custom bookmarks at specific timestamps in a long video to enable quick navigation to important sections across viewing sessions.

## Task Description

**Scenario:** You are watching a 90-minute documentary but need to pause your viewing session. Create bookmarks at specific timestamps so you can quickly return to important sections later, including your current "resume point" and three key moments you'll want to revisit.

The agent must:
1. Open a 90-minute documentary video in VLC
2. Create bookmarks at four specific timestamps:
   - "Resume Point" - 35:20 (where you stopped watching)
   - "Mars Landing" - 12:30 (interesting segment)
   - "Voyager Mission" - 58:00 (key content)
   - "Conclusion" - 82:15 (summary section)
3. Ensure bookmarks persist for future sessions

## Expected Results

- Bookmarks created at timestamps: 35:20, 12:30, 58:00, 82:15
- Bookmarks saved to VLC's media library or playlist files
- Bookmarks accessible for quick navigation

## Verification Criteria

1. ✅ **Bookmark Files Exist**: Media library or playlist files found
2. ✅ **Correct Timestamps**: At least 4 bookmarks at expected positions (±10s tolerance)
3. ✅ **Persistence**: Bookmarks saved to disk, not just in memory

**Pass Threshold**: 70%

## Skills Tested

- Timestamp navigation and seeking
- VLC bookmark/media library features
- Playlist management with time markers
- Understanding of bookmark persistence
- File management and saving

## Controls

**METHOD 1 (Recommended - Playlist with Start Times):**
1. Open playlist view (`Ctrl+L`)
2. Add the same video multiple times
3. Right-click each entry → Set Start Time to create bookmarks
4. Save playlist to file

**METHOD 2 (Media Library Bookmarks - if available):**
1. Seek to each timestamp
2. Use Playback → Custom Bookmarks → Manage
3. Create bookmark at current position
4. VLC automatically saves to media library

**METHOD 3 (Manual Playlist File):**
1. Create M3U or XSPF playlist file
2. Add entries with start-time options for each bookmark

## Notes

Long-form content like documentaries and lectures often require multiple viewing sessions. Without bookmarks, users must manually scrub through content to find their position, wasting time and causing frustration.