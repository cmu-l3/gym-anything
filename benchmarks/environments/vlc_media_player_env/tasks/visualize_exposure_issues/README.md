# Visualize Exposure Issues Task

**Difficulty**: 🟡 Medium  
**Skills**: Video filter navigation, exposure visualization, professional workflow  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Use VLC's video filter system to visualize over-exposed and under-exposed areas in wedding footage, then capture a snapshot documenting the exposure visualization.

## Scenario

You're a wedding videographer triaging 4K footage from a challenging outdoor ceremony. The lighting was harsh with mixed exposure—bright highlights and dark shadows. You need to quickly identify which clips have blown highlights or crushed blacks using VLC's filters rather than waiting for your editing suite to load.

## Task Description

The agent must:
1. Open the wedding footage in VLC (`/home/ga/Videos/wedding_footage.mp4`)
2. Navigate to video effects/filters menu
3. Enable a filter that visualizes exposure extremes (e.g., Gradient, Extract, Threshold)
4. The filter must make problematic exposure areas visually distinct
5. Capture a snapshot showing the filtered visualization
6. Snapshot saved to `/home/ga/Pictures/vlc/`

## Expected Results

- Video filter actively applied (detected in VLC config)
- Snapshot captured showing filtered video (NOT normal playback)
- Filter makes exposure problems clearly visible

## Verification Criteria

1. ✅ **Filter Enabled**: Video filter present in VLC config
2. ✅ **Snapshot Captured**: Snapshot file exists with reasonable quality
3. ✅ **Filtered View**: Snapshot shows filtered visualization (confirmed via analysis)

**Pass Threshold**: 70%

## Skills Tested

- Advanced menu navigation (Tools → Effects and Filters)
- Understanding video filter concepts
- Applying appropriate filter for task goal
- Snapshot capture at correct moment
- Professional workflow understanding

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Video Effects tab**: Enable filters like:
  - Gradient (edge detection)
  - Extract (color/brightness extraction)
  - Threshold (binary black/white)
  - Posterize (reduced tones)
- **Snapshot**: Shift+S or Video → Take Snapshot

## Notes

This task simulates a real professional workflow where cinematographers use VLC's fast playback and filters to quickly triage footage quality before committing to full editing pipeline processing.