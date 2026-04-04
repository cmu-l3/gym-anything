# Astronomy Observation Log Cleaner Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, time format standardization, VLOOKUP, formulas, sorting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Clean up and standardize a messy astronomy club observation log from a star party event. Handle mixed time formats, calculate average visibility ratings, fill missing catalog numbers, sort by quality, and generate summary statistics.

## Task Description

You are helping the local astronomy club organize their star party observation notes. Multiple observers logged celestial objects throughout the night, but with inconsistent formatting. Your job is to:

1. **Standardize time formats** - Convert all observation times to 24-hour format
2. **Fill missing Messier numbers** - Use the reference sheet to populate empty catalog numbers
3. **Calculate average quality** - Compute mean visibility rating across 3 observers
4. **Identify beginner objects** - Mark objects with high visibility (≥4.0) as beginner-friendly
5. **Sort by quality** - Organize observations by average quality (best first)
6. **Generate summary** - Count total Messier objects successfully observed

## Starting State

- LibreOffice Calc opens with `star_party_observations.ods`
- **Sheet 1 (Observations)** contains messy observation data:
  - Column A: Object Name (e.g., "Andromeda Galaxy")
  - Column B: Messier Number (some missing - shows empty)
  - Column C: Observation Time (mixed 12-hour/24-hour formats)
  - Column D-F: Visibility Quality ratings from 3 observers (1-5 scale, some blank)
  - Column G: Average Quality (empty - to be calculated)
  - Column H: Best for Beginners (empty - to be filled)
- **Sheet 2 (Messier_Reference)** contains lookup table:
  - Column A: Object Name
  - Column B: Messier Number

## Required Actions

### 1. Standardize Time Format (Column C)
- Convert all times to 24-hour format (HH:MM)
- Examples: "9:45 PM" → "21:45", "10:30 PM" → "22:30"
- Times already in 24-hour format should remain unchanged

### 2. Fill Missing Messier Numbers (Column B)
- Use VLOOKUP or INDEX/MATCH to reference "Messier_Reference" sheet
- Populate all empty cells in column B
- Example: "Orion Nebula" should get "M42"

### 3. Calculate Average Quality (Column G)
- Create AVERAGE formula for columns D, E, F
- Formula should ignore blank observer ratings
- Round to 1 decimal place
- Example: `=ROUND(AVERAGE(D2:F2),1)`

### 4. Mark Beginner-Friendly Objects (Column H)
- Use IF formula to check if average quality ≥ 4.0
- Display "Yes" if quality ≥ 4.0, otherwise "No"
- Example: `=IF(G2>=4,"Yes","No")`

### 5. Sort by Average Quality
- Sort entire data range by Column G (descending)
- Best-quality observations should appear at top
- Maintain row integrity (don't break up related data)

### 6. Generate Summary Statistic
- In cell B25, create COUNTIF formula to count non-empty Messier numbers
- Example: `=COUNTIF(B2:B20,"<>")`
- Add label: "Total Messier Objects Observed: "

## Expected Results

- All times in 24-hour format (no "AM" or "PM")
- All Messier numbers populated (Column B has no empty cells)
- Average Quality calculated with formulas (Column G)
- Beginner designation applied (Column H shows "Yes" or "No")
- Data sorted by quality (highest at top)
- Summary count displays total Messier objects

## Success Criteria

1. ✅ **Time Format Standardized**: All times in 24-hour format (100% of rows)
2. ✅ **Missing Data Filled**: All Messier numbers populated via lookup (0 empty cells)
3. ✅ **Averages Calculated**: Column G contains correct formulas
4. ✅ **Conditional Logic Applied**: Column H correctly identifies beginner objects
5. ✅ **Data Sorted**: Rows sorted descending by average quality
6. ✅ **Summary Generated**: Accurate COUNTIF formula in designated cell

**Pass Threshold**: 75% (requires at least 5 out of 6 criteria)

## Skills Tested

- Inconsistent data handling
- Time format conversion
- VLOOKUP/INDEX-MATCH for data lookup
- AVERAGE function with blank handling
- Conditional IF logic
- Multi-criteria sorting
- COUNTIF for summary statistics
- Formula creation and validation

## Tips

- Use TEXT() or TIME() functions for time conversion
- VLOOKUP syntax: `=VLOOKUP(A2,Messier_Reference.$A$2:$B$10,2,0)`
- AVERAGE automatically ignores blank cells
- Sort via Data → Sort menu
- Select entire data range before sorting
- Use absolute references ($) for VLOOKUP range