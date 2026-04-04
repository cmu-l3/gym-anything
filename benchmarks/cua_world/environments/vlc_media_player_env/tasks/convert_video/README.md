# Convert Video Task

**Difficulty**: 🔴 Medium+  
**Skills**: Transcoding, format conversion, codec selection  
**Duration**: 90 seconds  
**Steps**: ~50

## Objective

Convert a video file from one format to another using VLC's conversion functionality.

## Task Description

The agent must:
1. Open VLC's conversion dialog
2. Select source video file
3. Choose output format and codec
4. Start conversion process
5. Verify converted file is created

## Expected Results

- Converted video file created at `/home/ga/Videos/converted/output.avi`
- Video has valid properties and different codec from source
- Conversion completed successfully

## Verification Criteria

1. ✅ **File Exists**: Converted video file found
2. ✅ **Valid Properties**: Video has duration and codec information
3. ✅ **Format Changed**: Output codec/format differs from source

**Pass Threshold**: 75%

## Skills Tested

- Media → Convert/Save menu navigation
- File browser for source selection
- Profile/format selection
- Codec configuration
- Understanding of video formats
- Progress monitoring

## Controls

- **Media → Convert/Save**: Open conversion dialog
- **Add**: Select source file
- **Profile dropdown**: Choose output format
- **Start**: Begin conversion

## Notes

Conversion is resource-intensive and may take some time. The source video is a short 5-second clip to keep conversion time reasonable.
