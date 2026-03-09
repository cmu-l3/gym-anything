# Prepare Presentation Clips Task

**Difficulty**: 🟡 Medium  
**Skills**: Advanced playlist creation, XSPF format, start-time configuration  
**Duration**: 3-5 minutes  
**Steps**: ~50

## Objective

Create a presentation-ready VLC playlist where each video is cued to start at a specific timestamp (not from the beginning), allowing precise playback control during talks.

## User Story

Dr. Sarah Chen, a biology professor, is preparing for a conference talk. She has 3 video examples but needs them cued to specific moments—skipping irrelevant intros. During her last presentation, she wasted time scrubbing through videos. Now she wants a playlist where each clip is ready to play from the exact right moment.

## Task Description

The agent must:
1. Create a playlist with 3 provided video files
2. Configure each video to start at a specific timestamp:
   - Video 1 (`animal_foraging.mp4`): Start at 15 seconds
   - Video 2 (`colony_interaction.mp4`): Start at 90 seconds (1:30)
   - Video 3 (`migration_pattern.mp4`): Start at 45 seconds
3. Save the playlist in XSPF format (VLC's advanced format that supports start-time options)
4. Playlist should be saved to `/home/ga/Documents/presentation/talk_clips.xspf`

## Expected Results

- XSPF playlist file created at specified location
- Playlist contains exactly 3 video entries in correct order
- Each video has correct `start-time` parameter set
- Playlist is valid XML and properly formatted

## Verification Criteria

1. ✅ **Playlist Exists**: XSPF file found and valid XML
2. ✅ **Correct Videos**: All 3 videos present in order
3. ✅ **Start Times Set**: Each video has correct start-time (±2s tolerance)

**Pass Threshold**: 80%

## Skills Tested

- Advanced playlist creation (XSPF format)
- Understanding of start-time parameters
- VLC's "Advanced Open" or playlist editing
- File management and saving
- Understanding workflow preparation needs

## Controls

**Method 1: Advanced Open (Recommended)**
- Media → Open File (Advanced)
- Add each file
- Click "Show more options"
- Set "Start time" for each file
- Use "Enqueue" to add to playlist
- Save playlist: Media → Save Playlist to File → Choose XSPF format

**Method 2: Manual XSPF Editing**
- Create basic playlist first
- Save as XSPF
- Edit XML file to add start-time options

## Notes

- XSPF format supports VLC-specific extensions including start-time
- Start times are specified in seconds
- The playlist will load but not auto-play, giving presenter control
- This workflow is common for conference talks, lectures, and training sessions