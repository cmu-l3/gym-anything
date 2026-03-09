# Enhance Telescope Recording Task

**Difficulty**: 🟡 Medium  
**Skills**: Video adjustment filters, gamma/contrast/brightness control, snapshot capture  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Apply video enhancement filters to a dark telescope recording to reveal a faint celestial object (Andromeda Galaxy), then capture a snapshot of the enhanced view.

## Task Description

The agent must:
1. Open a dark telescope recording video in VLC
2. Navigate to video effects menu (Tools → Effects and Filters)
3. Enable and configure adjustment filters:
   - Gamma: ≥1.5 (to brighten faint details)
   - Contrast: ≥1.3 (to separate object from background)
   - Brightness: ≥0.1 (additional brightness boost)
4. Seek to a clear frame (~15-20 seconds)
5. Capture a snapshot showing the enhanced view
6. Save snapshot to `/home/ga/Pictures/astronomy/andromeda_enhanced.png`

## Expected Results

- Video adjustment filters enabled and configured
- Snapshot captured with filters applied
- Snapshot saved to correct location
- Filter settings persisted in VLC configuration

## Verification Criteria

1. ✅ **Snapshot Exists**: Snapshot file found with adequate quality (≥30 KB, ≥640x480)
2. ✅ **Filters Enabled**: VLC config shows 'adjust' filter enabled
3. ✅ **Filter Parameters**: Gamma ≥1.5, Contrast ≥1.3, Brightness ≥0.1
4. ✅ **Proper Application**: Filters were active when snapshot was taken

**Pass Threshold**: 75%

## Skills Tested

- Effects and Filters menu navigation
- Understanding of gamma, contrast, brightness adjustments
- Multi-parameter configuration
- Snapshot capture with active filters
- Settings persistence verification

## Controls

- **Menu**: Tools → Effects and Filters (or `Ctrl+E`)
- **Video Effects**: Enable "Image adjust" checkbox
- **Sliders**: Adjust Gamma, Contrast, Brightness
- **Snapshot**: Video → Take Snapshot (or `Shift+S`)
- **Seek**: Timeline navigation or `Shift+Right/Left`

## Real-World Context

Amateur astronomers often record faint deep-sky objects through telescopes. Raw footage is typically very dark with barely visible details. VLC's adjustment filters provide quick enhancement to:
- Verify telescope alignment and tracking quality
- Preview results before investing time in advanced stacking software
- Share recognizable images with astronomy communities
- Assess whether an observation session was successful

## Notes

- The telescope recording is intentionally very dark to simulate real astronomical observation conditions
- Enhancement filters dramatically increase visibility of faint structures
- Proper gamma/contrast values are critical for bringing out subtle details
- This workflow is common among amateur astronomers for quick quality checks