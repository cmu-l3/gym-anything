# 🎧 Remove Audio Noise Task (`remove_audio_noise@1`)

## Overview
**Difficulty:** 🟡 Medium  
**Estimated Time:** 5-8 minutes  
**Category:** Audio Processing

## Scenario
You're helping a local historical society clean up a 1987 community meeting recording that was recently digitized from cassette tape. The audio has severe 60Hz electrical hum and tape hiss that makes speech difficult to understand. Using VLC's built-in audio filters, you need to clean up the recording enough to be usable for their oral history archive.

## Task Objectives
1. Open the noisy audio file in VLC (`/home/ga/Music/historical_meeting.mp3`)
2. Apply audio filters to reduce 60Hz hum and background noise
3. Use parametric equalizer to notch out problematic frequencies
4. Save the cleaned audio to `/home/ga/Music/cleaned_meeting.mp3`
5. Ensure speech remains intelligible while noise is reduced

## Skills Tested
- **Audio filter navigation** - Finding and enabling VLC's audio effects
- **Parametric EQ usage** - Notch filtering specific frequencies
- **Audio export/recording** - Saving processed audio to file
- **Critical listening** - Evaluating filter effectiveness

## Approach Hints

### Method 1: Using VLC's Audio Filters (Recommended)
1. Open the audio file in VLC (already loaded)
2. Go to **Tools → Effects and Filters** (or Ctrl+E)
3. Navigate to **Audio Effects** tab
4. Enable **Equalizer** and create notches at 60Hz, 120Hz, 180Hz to remove hum
5. Enable **Compressor** to even out volume and make speech more audible
6. Optional: Adjust other bands to reduce hiss (cut high frequencies slightly)
7. Use **Media → Convert/Save** to export the filtered audio

### Method 2: Using VLC's Recording Feature
1. Apply filters as above (Tools → Effects and Filters)
2. Click the **Record** button (red circle) in the playback controls
3. Play through the audio (or let it play)
4. VLC will save the output with filters applied
5. Find the recorded file and move/rename it to the target location

### Method 3: CLI Approach (Advanced)