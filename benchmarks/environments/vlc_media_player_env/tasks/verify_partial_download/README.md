# Verify Partial Download Task

**Difficulty**: 🟡 Medium  
**Skills**: Media analysis, systematic testing, documentation  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Analyze a partially downloaded video file to determine how much content is actually playable, distinguish between corrupted and incomplete files, and document findings in a structured report.

## Task Description

The agent must:
1. Open a partial video file in VLC
2. Systematically test playback at various timestamps
3. Identify where the file becomes unplayable
4. Check VLC error logs for diagnostic information
5. Create a detailed report with findings and recommendations

## Expected Results

- Report file created at `/home/ga/Documents/partial_download_report.txt`
- Report contains:
  - Reported duration from VLC
  - Actual playable duration (tested)
  - File status (incomplete/corrupted)
  - Actionable recommendation
  - Testing methodology notes

## Verification Criteria

1. ✅ **Report Exists**: Report file found and readable
2. ✅ **Playable Duration Accurate**: Within ±2 minutes of actual (35 min)
3. ✅ **Status Correct**: Identifies file as incomplete/truncated
4. ✅ **Recommendation Present**: Provides actionable advice

**Pass Threshold**: 75% (3/4 criteria)

## Skills Tested

- Systematic testing approach (binary search)
- Media file analysis
- Error interpretation
- Technical documentation
- Problem-solving workflow

## Real-World Context

**Scenario**: User downloaded a 90-minute documentary over unreliable WiFi. Download shows "45% complete" but user needs to know:
- Can I watch anything now?
- How much is actually playable?
- Is the file corrupted or just incomplete?
- Should I keep this or restart the download?

## Controls

- **Seek**: Click timeline or use Shift+Left/Right
- **Messages**: Tools → Messages (Ctrl+M) for error logs
- **Playback**: Space to pause/play
- **File**: Create report using text editor (gedit, nano, etc.)

## Testing Strategy

Use **binary search** to efficiently find the playback boundary:
1. Seek to 50% of duration
2. If plays: seek forward (75%)
3. If freezes: seek backward (25%)
4. Continue narrowing until finding exact cutoff point

## Report Template
