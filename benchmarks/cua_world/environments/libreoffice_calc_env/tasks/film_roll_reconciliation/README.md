# Film Roll Reconciliation Task

**Difficulty**: 🟡 Medium  
**Skills**: Data reconciliation, lookups, validation, conditional logic, multi-sheet operations  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~15

## Objective

Help a film photographer reconcile messy shooting notes with developed film rolls returned from a lab. Match lab roll IDs to original labels using contextual clues, validate frame counts against roll capacity (36 exposures), identify priority shots for scanning, and calculate per-roll statistics. This represents a real-world data reconciliation problem with validation, lookup operations, and conditional logic.

## Starting State

- LibreOffice Calc opens with a multi-sheet spreadsheet containing:
  - **"Shooting Notes"**: Photographer's original notes with frame descriptions, dates, locations
  - **"Lab Rolls"**: Lab's return data with different roll IDs, frame counts, development status
  - **"Roll Specs"**: Reference data for 35mm film types, capacity (36 frames), and costs

## Task Description

The agent must:
1. Analyze the three provided sheets to understand the data structure
2. Create a new sheet called **"Reconciliation"**
3. Match each lab roll ID to the photographer's original roll labels using contextual clues (frame counts, dates, locations)
4. Validate that frame counts don't exceed 36 (flag any rolls with >36 frames)
5. Count priority shots per roll (family photos, landmarks vs. test shots)
6. Assign scan priority scores based on priority shot count and practical considerations
7. Calculate cost per frame for each roll (development cost ÷ frame count)
8. Apply conditional formatting to highlight priorities and validation issues

## Expected Results

**Reconciliation Sheet** should contain:
- **Lab Roll ID**: The three roll IDs from Lab Rolls sheet (R2847-A, R2847-B, R2847-C)
- **Original Roll Label**: Matched labels based on shooting notes (e.g., "Beach Roll", "Mountain Roll")
- **Total Frames**: Frame count for each roll
- **Priority Frames**: Count of high-priority shots (using COUNTIF or similar)
- **Scan Priority**: Ranking score (1=scan first, 3=scan last)
- **Cost per Frame**: Development cost divided by frame count
- **Validation Flag**: Indicator if frame count exceeds 36

## Verification Criteria

1. ✅ **Reconciliation Sheet Exists**: New sheet created with appropriate name
2. ✅ **All Rolls Matched**: Three lab rolls matched to original labels
3. ✅ **Frame Validation Working**: Rolls exceeding 36 frames flagged (R2847-B has 38 frames)
4. ✅ **Priority Counts Calculated**: Formula counts priority shots per roll
5. ✅ **Priority Scores Assigned**: Logical priority ranking with differentiation (not all same)
6. ✅ **Cost per Frame Calculated**: Formula divides cost by frame count
7. ✅ **Formulas Used**: At least 3 different formula types present (lookup, count, arithmetic)
8. ✅ **Conditional Formatting Applied**: Visual indicators for priority or validation

**Pass Threshold**: 75% (6/8 criteria must pass)

## Skills Tested

- Multi-sheet navigation and cross-referencing
- VLOOKUP, INDEX-MATCH, or similar lookup functions
- COUNTIF for conditional counting
- IF statements for logical decisions
- Data validation and constraint checking
- Conditional formatting for visual feedback
- Cost calculations and per-unit metrics
- Real-world data reconciliation and pattern recognition

## Contextual Clues for Matching

- **Frame counts**: Different rolls have different numbers of shots
- **Locations**: Beach, Mountain, City mentioned in notes
- **Shot descriptions**: Family photos, landscapes, test shots
- **Dates**: Sequence of shooting dates
- **Camera notes**: Nikon FM vs. Olympus usage

## Tips

- The roll with 38 frames (R2847-B) is suspicious and should be flagged
- Priority shots include: family photos, group shots, landmarks, sunrise/sunset
- Test shots and exposure tests are lower priority
- Cost per frame helps identify which rolls give best value for scanning
- Scan priority should consider: priority shot count, total frames, and cost efficiency
- Use conditional formatting to make validation issues immediately visible (red for >36 frames)