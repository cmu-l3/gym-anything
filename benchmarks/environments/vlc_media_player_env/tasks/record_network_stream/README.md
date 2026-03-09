# Record Network Stream Task

**Difficulty**: 🟡 Medium  
**Skills**: Network streaming, convert/save feature, recording  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Record a network video stream to a local MP4 file using VLC's advanced streaming and conversion capabilities.

## Task Description

The agent must:
1. Open VLC's "Media → Convert/Save" dialog (or "Open Network Stream")
2. Enter a network stream URL in the Network tab
3. Choose "Convert/Save" (not just "Play")
4. Configure output format (H.264/MP4)
5. Specify output file path
6. Start recording and capture at least 10 seconds

## Realistic Scenario

You're a graduate student who discovered a live-streamed academic webinar that's only available for the next hour, but you have a class conflict. You need to record the stream so you can watch it later tonight.

## Expected Results

- Recorded video file at `/home/ga/Videos/recordings/captured_webinar.mp4`
- File size > 100 KB (meaningful content)
- Duration > 5 seconds
- Valid video codec (H.264 preferred)
- File is playable

## Verification Criteria

1. ✅ **File Created**: Recording file exists at expected path
2. ✅ **Non-Empty**: File size > 100 KB
3. ✅ **Valid Format**: File is valid MP4 with video stream
4. ✅ **Sufficient Duration**: Recording duration > 5 seconds
5. ✅ **Valid Codec**: Video uses H.264 or compatible codec

**Pass Threshold**: 70%

## Skills Tested

- Deep menu navigation (Media → Convert/Save)
- Network stream URL handling
- Understanding Convert/Save vs Play modes
- Profile/format selection
- Output path specification
- Recording process management

## Controls

- **Menu**: Media → Convert/Save (Ctrl+R)
- **Network Tab**: Enter stream URL
- **Convert/Save Button**: Initiate recording
- **Profile Dropdown**: Select output format
- **Destination**: Specify output file path
- **Start Button**: Begin recording

## Notes

- The task uses a local file with file:// URL to simulate a network stream for reproducibility
- Recording continues until the stream ends or VLC is closed
- VLC can record while transcoding to different formats
- Important: Click "Convert/Save", not "Play" in the initial dialog