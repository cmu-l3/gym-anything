# Manuscript Timeline Validator Task

**Difficulty**: 🟡 Medium  
**Skills**: Complex formulas, conditional logic, data validation, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Use LibreOffice Calc to identify timeline and location inconsistencies in a fiction manuscript's scene breakdown. Create validation formulas to detect impossible situations (character appearing in two locations simultaneously, POV character not present in scene, timeline contradictions).

## Task Description

The agent must:
1. Open a scene breakdown spreadsheet for a mystery novel (45 scenes)
2. Analyze the data structure (Scene #, Chapter, Timestamp, POV Character, Location, Characters Present, Scene Type)
3. Create validation formulas to detect conflicts:
   - **Location conflicts**: Character in multiple locations at same timestamp
   - **POV presence**: POV character must be in "Characters Present" list
   - **Timeline consistency**: Timestamps shouldn't go backward within chapters (except flashbacks)
4. Apply conditional formatting to highlight conflicts
5. Add summary statistics showing total conflicts found

## Data Structure

| Scene # | Chapter | Timestamp | POV Character | Location | Characters Present | Scene Type |
|---------|---------|-----------|---------------|----------|-------------------|------------|
| 1 | 1 | 2024-03-15 09:00 | Sarah | Precinct | Sarah, Wong, Captain | Normal |
| 2 | 1 | 2024-03-15 10:30 | Marcus | Coffee Shop | Marcus, Jennifer | Normal |
| ... | ... | ... | ... | ... | ... | ... |

## Expected Results

- **Validation columns added**: New columns with formulas checking for conflicts
- **Conflicts detected**: All 3 planted contradictions flagged:
  1. Scene with character location conflict
  2. Scene with missing POV character
  3. Scene with timeline reversal
- **Conditional formatting**: Conflict cells highlighted in red/yellow
- **Summary statistics**: Total conflict count displayed

## Verification Criteria

1. ✅ **Formulas Added**: At least 2 validation formula columns present
2. ✅ **Known Conflicts Detected**: All 3 planted contradictions correctly flagged
3. ✅ **Valid Scenes Passed**: No false positives (max 1 acceptable)
4. ✅ **Conditional Formatting Applied**: Conflict cells visibly highlighted
5. ✅ **Summary Statistics Present**: Conflict totals calculated with formulas

**Pass Threshold**: 80% (4/5 criteria must pass)

## Skills Tested

- Complex IF/AND/OR/COUNTIFS formulas
- Text search functions (SEARCH, FIND, ISNUMBER)
- Cross-row comparisons
- Conditional formatting rules
- Summary statistics with COUNTIF
- Boolean logic construction
- Cell reference management (absolute vs relative)

## Tips

- Use COUNTIFS to check for duplicate timestamps with different locations
- Use SEARCH or FIND to check if POV character name appears in Characters Present
- Compare current row timestamp with previous row for timeline validation
- Exclude "Flashback" scene types from timeline checks
- Use conditional formatting with formula-based rules
- Add summary section in first few rows or separate area