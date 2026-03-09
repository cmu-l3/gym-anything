# Verify Smooth Playback Task

**Difficulty**: 🟡 Medium  
**Skills**: Performance diagnostics, statistics analysis, technical reporting  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Test if your system can play high-quality video smoothly by analyzing VLC's playback statistics and creating a performance report.

## Task Description

The agent must:
1. Play a high-bitrate 4K test video in VLC for at least 30 seconds
2. Access VLC's codec information or statistics window
3. Record playback performance metrics (frames decoded, displayed, dropped)
4. Create a text report documenting whether playback is smooth

## Expected Results

- Statistics report created at `/home/ga/Documents/playback_stats.txt`
- Report contains frame statistics from VLC
- Report indicates performance verdict (smooth or not smooth)
- Playback tested for minimum 30 seconds

## Verification Criteria

1. ✅ **Report Exists**: Statistics report file found and parseable
2. ✅ **Sufficient Duration**: Playback tested for 30+ seconds
3. ✅ **Complete Metrics**: Report contains decoded/displayed/dropped frame counts
4. ✅ **Performance Assessment**: Drop rate calculated and verdict provided

**Pass Threshold**: 70%

## Skills Tested

- VLC advanced features (codec information, statistics)
- Menu navigation (Tools → Codec Information / Media Information)
- Technical data interpretation
- Performance analysis
- Documentation and reporting

## Controls

- **Menu**: Tools → Codec Information (Ctrl+J) or Tools → Media Information (Ctrl+I → Statistics tab)
- **Playback**: Space to play/pause, seek controls
- **Report**: Create text file with findings

## Context

This task simulates a real-world scenario: deciding whether to download a high-quality (4K) or standard-quality (1080p) version of content based on your system's playback capabilities. Smooth playback means < 1% frames dropped.

## Notes

- The test video is a generated 4K pattern (3840x2160) with high bitrate (~30 Mbps)
- VLC's statistics show "Lost frames" or frame counts in the codec/media information windows
- A 1080p alternative is also available for comparison testing if needed