# Baby Feeding Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Time calculations, formulas, conditional formatting, data analysis  
**Duration**: 300 seconds  
**Steps**: ~20

## Objective

Organize scattered baby feeding and sleep data into a structured format, apply time-based formulas to calculate durations and intervals, create summary statistics, and use conditional formatting to highlight potential concerns. This task simulates a real scenario where exhausted new parents need to organize data before a pediatrician appointment.

## Scenario

You're helping new parents prepare for tomorrow's pediatrician appointment. They've been tracking their baby's feeding and sleep patterns on paper scraps and phone notes. The data needs to be organized into a spreadsheet with calculations to identify patterns the doctor will ask about.

## Starting State

- LibreOffice Calc opens with a partially-filled template
- Columns: Date, Start Time, End Time, Event Type, Duration, Interval Since Last Feed
- 10-12 pre-filled entries with dates, times, and event types (Feed/Sleep)
- Duration and Interval columns are empty (need formulas)
- Summary section at bottom with labels but no calculations

## Data Structure

| Date       | Start Time | End Time | Event Type | Duration | Interval |
|------------|------------|----------|------------|----------|----------|
| 2024-01-15 | 02:30 AM   | 02:50 AM | Feed       | [empty]  | [empty]  |
| 2024-01-15 | 03:00 AM   | 05:30 AM | Sleep      | [empty]  | N/A      |
| 2024-01-15 | 05:45 AM   | 06:05 AM | Feed       | [empty]  | [empty]  |
| ...        | ...        | ...      | ...        | ...      | ...      |

## Required Actions

1. **Calculate Duration** (Column E):
   - Add formula: `=D2-C2` (End Time - Start Time)
   - Copy formula down for all data rows
   - Format as time duration (h:mm)

2. **Calculate Interval Since Last Feed** (Column F):
   - For Feed events: calculate time since previous feed ended
   - Formula example: `=C3-D2` (current start - previous end)
   - Apply only to Feed type rows

3. **Create Summary Statistics** (around row 15):
   - Shortest Interval: `=MIN(F:F)`
   - Longest Sleep Stretch: `=MAXIFS(E:E, D:D, "Sleep")`
   - Average Feeding Interval: `=AVERAGE(F:F)`

4. **Apply Conditional Formatting**:
   - Select Interval column (F)
   - Format → Conditional Formatting
   - Rule: Cell value < 1:30 (1.5 hours)
   - Format: Red background or red text
   - Purpose: Flag concerning short feeding intervals

## Success Criteria

1. ✅ **Duration formulas present**: At least 80% of Duration column contains formulas
2. ✅ **Duration calculations accurate**: Spot-check calculations within ±2 min tolerance
3. ✅ **Interval formulas present**: Interval column has formulas for Feed events
4. ✅ **Summary statistics correct**: MIN, MAX, AVERAGE formulas produce reasonable values
5. ✅ **Conditional formatting applied**: Short intervals are visually highlighted
6. ✅ **Longest sleep identified**: MAXIFS formula finds maximum sleep duration
7. ✅ **Data completeness**: At least 10 entries with valid dates/times

**Pass Threshold**: 70% (requires at least 5 out of 7 criteria)

## Skills Tested

- Time arithmetic and duration calculations
- Formula creation and copying
- Conditional aggregation (MAXIFS)
- Summary statistics (MIN, MAX, AVERAGE)
- Conditional formatting with value-based rules
- Medical/health data organization
- Pattern identification in time-series data

## Tips

- Time format: Enter times as "2:30 AM" or "14:30" (24-hour)
- Duration format: Result should show as "2:30" for 2 hours 30 minutes
- Overnight periods: Calc handles times crossing midnight correctly
- MAXIFS syntax: `=MAXIFS(range_to_max, criteria_range, criteria)`
- Conditional formatting: Format → Conditional Formatting → Condition
- Time comparisons: 1:30 represents 1.5 hours

## Medical Context

Pediatricians commonly ask about:
- **Longest sleep stretch**: Indicates baby's sleep consolidation development
- **Feeding frequency**: Too frequent (<1.5 hrs) may indicate feeding issues
- **Average interval**: Shows if baby is establishing a feeding pattern
- **Concerning patterns**: Short intervals (red flags) need discussion

## Real-World Relevance

This scenario reflects actual challenges faced by new parents who must:
- Organize data from multiple sources (paper, phone, memory)
- Identify patterns in sleep-deprived states
- Prepare meaningful information for medical consultations
- Make data-driven decisions about infant care