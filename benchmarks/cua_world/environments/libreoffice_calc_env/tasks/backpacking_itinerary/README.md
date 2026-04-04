# Backpacking Trip Itinerary Planner Task

**Difficulty**: 🟡 Medium  
**Skills**: Cumulative calculations, formula logic, conditional statements, time estimation  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Plan a safe 7-day backpacking trip by calculating cumulative distances, estimating hiking times based on distance and elevation gain, and identifying potentially dangerous days that exceed safe daylight hours. This simulates real-world trip planning where poor calculations can lead to getting caught on the trail after dark.

## Task Context

**Scenario**: You're planning a week-long backpacking trip in the mountains. The trip starts in 2 days, and you need to verify the itinerary is safe. Some days might have too much hiking for the available daylight (approximately 12 hours in summer). Days requiring more than 10 hours of hiking are concerning; individual segments over 6 hours or elevation gains exceeding 3000 feet are also risky.

**Why this matters**: Underestimating hiking time can lead to:
- Being caught on the trail after dark
- Exhaustion and injury
- Getting lost or needing rescue
- Missing critical water sources or campsites

## Starting State

- LibreOffice Calc opens with trail segment data in CSV format
- Data columns: Day, Segment Name, Distance (miles), Elevation Gain (feet)
- 7 days of hiking with 15 total segments
- Some days will be challenging and need to be flagged

## Required Actions

### 1. Add Cumulative Distance Column
- Create a new column "Cumulative Distance (mi)"
- Calculate running total of distances from start to each segment
- First row: equals first segment distance
- Subsequent rows: previous cumulative + current distance
- Verify final cumulative distance is reasonable for a week-long trip

### 2. Calculate Estimated Hiking Time
- Create column "Est. Time (hours)"
- Apply hiking estimation formula combining:
  - **Distance component**: Assuming ~2.5 mph average pace on trails
  - **Elevation component**: Elevation gain adds significant time (~1 hour per 1000 ft gain)
- Suggested formula: `=(Distance/2.5) + (Elevation_Gain/1000)`
- Copy formula to all segment rows

### 3. Flag Problematic Segments/Days
- Add "Status" or "Warning" column OR use conditional formatting
- Use IF function to identify:
  - Segments with time > 6 hours: "Long Segment"
  - Segments with elevation > 3000 ft: "Steep"
  - Daily totals > 10 hours: "Warning"
  - Daily totals > 12 hours: "Danger"
- Apply conditional formatting (optional but recommended):
  - Yellow background for warnings
  - Red background for danger

### 4. Verify Calculations
- Check cumulative distance increases correctly
- Spot-check time estimates are reasonable
- Ensure formulas have no errors (#DIV/0!, #REF!, etc.)
- Confirm problem flags make intuitive sense

## Expected Results

### Cumulative Distance Column
- Monotonically increasing values
- Final cumulative: ~65-70 miles total
- Uses formulas (not hardcoded values)

### Estimated Time Column
- Reasonable hiking times (typically 2-8 hours per segment)
- Combines distance and elevation effects
- Uses formulas with both distance and elevation references

### Problem Identification
- Day 3 should be flagged (steep climb: 3200 ft elevation in one segment)
- Day 4 should be flagged (long day: ~10 hours total)
- Individual steep segments identified
- Visual formatting makes problems obvious

## Success Criteria

1. ✅ **Cumulative Distance Calculated**: Running total formula correctly implemented
2. ✅ **Hiking Time Estimated**: Formula combines distance AND elevation appropriately  
3. ✅ **Problems Flagged**: Conditional logic identifies risky segments/days
4. ✅ **No Formula Errors**: All formulas execute without errors
5. ✅ **Realistic Results**: Calculated values pass sanity checks

**Pass Threshold**: 75% (requires accurate cumulative distance, reasonable time estimation, and basic problem identification)

## Skills Tested

- **Cumulative calculations**: Running totals with proper cell references
- **Multi-variable formulas**: Combining distance and elevation into time estimate
- **Conditional logic**: IF statements to flag problems
- **Conditional formatting**: Visual highlighting of risky days
- **Formula copying**: Dragging formulas while maintaining correct references
- **Real-world modeling**: Translating domain knowledge into spreadsheet logic

## Tips

- **Cumulative Distance**: First cell references the first distance, second cell adds previous cumulative to current distance
- **Time Formula**: Both distance/pace and elevation/rate should be included
- **Absolute vs Relative References**: Be careful when copying formulas down
- **Naismith's Rule**: Classic hiking time estimation (3 mph + 1 hour per 2000 ft)
- **Problem Thresholds**: 
  - Single segment > 6 hours: concerning
  - Daily total > 10 hours: warning
  - Elevation > 3000 ft: steep and slow
  - Daily total > 12 hours: dangerous

## Real-World Application

This task simulates actual trip planning used by:
- Backpackers planning multi-day wilderness trips
- Hiking groups assessing route feasibility
- Outdoor education programs teaching trip planning
- Search and rescue teams estimating hiker positions

A spreadsheet like this directly informs the decision: "Is this itinerary safe, or do we need to modify it?"