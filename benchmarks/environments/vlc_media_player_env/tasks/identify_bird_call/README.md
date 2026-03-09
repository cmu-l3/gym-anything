# Identify Bird Call Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio scrubbing, timestamp finding, segment extraction, audio enhancement  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~60

## Objective

Extract a specific bird call segment from a long field recording and save it as a shareable audio file for species identification.

## Scenario

Maya recorded 6 minutes of audio during a morning birding walk. Around 3:45, she heard an unusual warbler call she needs to identify. She needs to:
1. Find the bird call in the recording (around 3:40-3:50)
2. Extract just that ~10-second segment
3. Optionally boost the audio to make the distant call more audible
4. Save as a shareable file for the birding community

## Task Description

The agent must:
1. Open the audio recording in VLC (`/home/ga/Recordings/morning_birding_2024-06-15.wav`)
2. Scrub through the 6-minute audio to locate the bird call (around 3:45)
3. Extract a ~10-second segment containing the call
4. Save the extracted segment as a shareable audio file

## Expected Results

- Extracted audio file saved at `/home/ga/Recordings/unknown_warbler_call.{mp3,wav,ogg,flac}`
- Duration: 8-12 seconds
- Contains the timestamp range with the bird call (3:43-3:47)
- File is in a common shareable format (MP3, WAV, OGG, FLAC)
- File size reasonable for online sharing (<5 MB)

## Verification Criteria

1. ✅ **File Exists**: Extracted segment found
2. ✅ **Duration Correct**: Segment is 8-12 seconds long
3. ✅ **Valid Audio**: Has proper codec and sample rate
4. ✅ **Reasonable Size**: File <5 MB for sharing

**Pass Threshold**: 75%

## Skills Tested

- Audio file playback and navigation
- Timeline scrubbing for long files
- Timestamp identification
- Audio segment extraction (via Record or Convert features)
- File format selection
- Understanding of audio properties

## Methods to Extract Segment

### Method 1: Record Feature (Recommended)
1. Open audio file in VLC
2. Seek to ~3:38 (before the bird call)
3. Click Record button (red circle) or View → Advanced Controls → Record
4. Let audio play for ~10 seconds
5. Click Record again to stop
6. Find recorded file in Videos directory and move/rename it

### Method 2: Convert/Save with Time Range
1. Media → Convert/Save
2. Add the source audio file
3. Check "Show more options"
4. Set start time: 220s, stop time: 232s
5. Choose output format (MP3 or other)
6. Set destination path
7. Start conversion

## Controls

- **Space**: Play/Pause
- **Shift+Right/Left**: Seek forward/backward
- **View → Advanced Controls**: Show Record button
- **Media → Convert/Save**: Access conversion dialog