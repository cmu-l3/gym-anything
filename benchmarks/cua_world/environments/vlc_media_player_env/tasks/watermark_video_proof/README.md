# Watermark Video Proof Task

**Difficulty**: 🟡 Medium  
**Skills**: Video transcoding, overlay filters, text rendering, format conversion  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Add a semi-transparent text watermark to a video file using VLC's conversion feature with text overlay filter. This simulates a real freelance videographer workflow where client previews need copyright protection.

## Task Description

The agent must:
1. VLC launches with convert/transcode dialog ready
2. Add source video file (`client_preview_raw.mp4`)
3. Configure video filters to add text overlay watermark
4. Set watermark text (e.g., "PREVIEW ONLY - DO NOT DISTRIBUTE")
5. Configure watermark position and opacity
6. Start conversion and save to `client_preview_watermarked.mp4`

## Expected Results

- Watermarked video file created at `/home/ga/Videos/client_preview_watermarked.mp4`
- Video contains visible text watermark throughout playback
- Duration preserved from input video (±5% tolerance)
- Watermark is semi-transparent and positioned appropriately

## Verification Criteria

1. ✅ **Output File Exists**: Watermarked video file found
2. ✅ **Playable Video**: Video has valid duration and codec
3. ✅ **Duration Preserved**: Output duration matches input (±5%)
4. ✅ **Watermark Present**: Text overlay detected via OCR
5. ✅ **Watermark Persistent**: Watermark appears throughout video (60%+ of sampled frames)

**Pass Threshold**: 75%

## Skills Tested

- Media → Convert/Save navigation
- Video filter configuration
- Text overlay/subtitle renderer usage
- Transcode profile selection
- Understanding of overlay opacity
- File path management
- Progress monitoring

## Controls

- **Menu**: Media → Convert / Save (Ctrl+R)
- **Profile editor**: Tools icon next to profile dropdown
- **Video codec tab**: Enable video filters
- **Filters**: Text renderer, Overlay, or Marquee filter

## Real-World Context

Maria is a freelance wedding videographer who needs to send a preview to a client who hasn't paid yet. She's been ghosted before by clients who took unmarked previews. She needs to add a visible watermark that protects her work while still allowing the client to review the content quality.

## Notes

- Conversion may take 30-60 seconds depending on video length
- Text overlay can be added via "Marquee" filter or "Text renderer"
- Position options: top, bottom, left, right, center
- Opacity: 50-70% recommended for visibility without distraction