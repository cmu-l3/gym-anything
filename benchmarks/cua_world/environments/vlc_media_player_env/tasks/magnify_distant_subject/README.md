# Magnify Distant Subject Task

**Difficulty**: 🟡 Medium  
**Skills**: Video cropping/zoom, transcoding, filter application  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Use VLC to magnify a distant subject in wildlife footage by applying crop/zoom filters and transcoding the result to a new video file.

## Task Description

The agent must:
1. VLC launches with access to wildlife footage
2. Identify the region containing a small/distant bird (upper-right quadrant)
3. Apply crop or transform filter to zoom into that region
4. Transcode and save the magnified video to a new file

## Scenario

Maya, an amateur bird watcher, captured video of a rare warbler, but the bird is very small in the frame. She needs to digitally zoom into the region where the bird appears and save the magnified video for identification and sharing with experts.

## Expected Results

- Magnified video file created at `/home/ga/Videos/magnified/bird_closeup.mp4`
- Video shows cropped/zoomed region (not full 1920x1080 frame)
- Output video is playable and maintains reasonable quality
- Duration approximately matches original (~30 seconds)

## Verification Criteria

1. ✅ **Output Exists**: Magnified video file found
2. ✅ **Resolution Changed**: Output resolution differs from 1920x1080 (cropped)
3. ✅ **Video Valid**: Output has correct duration and is playable
4. ✅ **Reasonable Crop**: Output dimensions suggest targeted region crop

**Pass Threshold**: 70%

## Skills Tested

- Video filter application (crop/transform)
- Understanding transcoding workflow
- Coordinate/geometry understanding for cropping
- Media conversion menu navigation
- File output management

## Controls

**Option A: GUI - Effects and Filters**
1. Tools → Effects and Filters (Ctrl+E)
2. Video Effects → Geometry tab
3. Enable "Crop" or "Transform" filter
4. Set crop coordinates for upper-right region
5. Media → Convert/Save to transcode with filters

**Option B: GUI - Convert with Profile**
1. Media → Convert/Save (Ctrl+R)
2. Add wildlife_distant_bird.mp4
3. Click Edit profile → Video codec → Filters
4. Add crop filter with coordinates
5. Set output destination and convert

**Option C: Command Line**