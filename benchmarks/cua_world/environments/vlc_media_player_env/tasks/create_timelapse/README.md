# Create Time-lapse Video Task

**Difficulty**: 🟡 Medium  
**Skills**: Video conversion, speed manipulation, transcoding  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Convert a long video recording into a time-lapse video by speeding it up 60x using VLC's conversion feature.

## Scenario

You are a hobbyist filmmaker who recorded a 2-hour painting session. You want to create a 2-minute time-lapse video to share on social media, showing the entire creative process in fast-forward.

## Task Description

The agent must:
1. Open VLC's conversion dialog (Media → Convert/Save)
2. Select the source video: `/home/ga/Videos/painting_session.mp4`
3. Configure conversion settings to speed up playback by 60x
4. Set output destination: `/home/ga/Videos/timelapse_output.mp4`
5. Start conversion and wait for completion

## Expected Results

- Time-lapse video created at `/home/ga/Videos/timelapse_output.mp4`
- Video duration is approximately 1/60th of source (±15% tolerance)
- Resolution maintained (1920x1080)
- Video is playable and valid

## Verification Criteria

1. ✅ **Output Exists**: Time-lapse video file found
2. ✅ **Speed-up Correct**: Duration ratio matches 60x speed (±15%)
3. ✅ **Resolution Maintained**: Output is 1920x1080
4. ✅ **Valid Video**: Video has correct codec and properties

**Pass Threshold**: 75%

## Skills Tested

- Media → Convert/Save menu navigation
- File browser usage
- Conversion profile configuration
- Understanding of video speed/frame rate manipulation
- Progress monitoring and completion detection

## Approaches

### Method 1: VLC GUI Conversion
1. Open Media → Convert/Save (Ctrl+R)
2. Add source file
3. Click "Convert/Save" button
4. Choose profile and configure settings
5. Set destination path
6. Start conversion

### Method 2: VLC CLI (Advanced)