# Progressive Overload Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-criteria formulas, COUNTIFS, date calculations, conditional formatting, logical operators  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze a messy 8-week workout log and calculate when to increase weights based on progressive overload principles. Apply formulas to identify exercises ready for progression and use conditional formatting to highlight actionable insights.

## Task Description

You're a home gym enthusiast who has logged 8 weeks of workouts inconsistently (missed sessions, deload weeks, varying rep counts). You need to analyze this data to determine which exercises are ready for weight increases.

The agent must:
1. Open a workout log spreadsheet with columns: Date, Exercise, Weight, Reps Completed, Target Reps, Notes
2. Create helper column: "Sessions at Current Weight" using COUNTIFS to count successful sessions
3. Create helper column: "Days Since Last Session" using date calculations
4. Create helper column: "Ready for Increase?" with complex IF/AND logic
5. Calculate "Recommended Weight" based on exercise type (upper body +5 lbs, lower body +10 lbs)
6. Apply conditional formatting to highlight exercises ready for progression (green = YES, gray = NO)
7. (Optional) Add summary statistics

## Progressive Overload Rules (3x5 Rule)

An exercise is ready for weight increase when:
- ✅ Completed target reps for 3+ sessions at current weight
- ✅ Still actively training (< 14 days since last session)
- ✅ Not in a deload week (Notes don't contain "DELOAD")

**Weight increase guidelines:**
- **Squat, Deadlift**: +10 lbs
- **Bench Press, Overhead Press, Barbell Row**: +5 lbs

## Expected Results

### Helper Columns Created
- **Sessions at Current Weight**: Formula using `COUNTIFS(Exercise_Range, Exercise, Weight_Range, Weight, Reps_Range, ">=Target")`
- **Days Since Last Session**: Formula using `TODAY()` and date calculations
- **Ready for Increase?**: Formula combining `IF(AND(Sessions>=3, Days<14, NOT(SEARCH("DELOAD",Notes))), "YES", "NO")`
- **Recommended Weight**: Formula adding 5 or 10 lbs based on exercise type

### Conditional Formatting
- "YES" cells highlighted in green (RGB: 200, 255, 200)
- "NO" cells highlighted in light gray (RGB: 240, 240, 240)

## Verification Criteria

1. ✅ **COUNTIFS Formula Present** (25%): At least one column uses COUNTIFS to track sessions
2. ✅ **Progression Logic Correct** (30%): "Ready for Increase?" correctly identifies exercises meeting 3x5 rule
3. ✅ **Weight Recommendations Accurate** (20%): Recommended weights follow 5/10 lb increase rules
4. ✅ **Conditional Formatting Applied** (15%): Visual highlighting works for ready/not ready states
5. ✅ **No Formula Errors** (10%): All formulas calculate without #REF!, #VALUE!, #DIV/0! errors

**Pass Threshold**: 75% (requires core formula logic + either formatting or complete accuracy)

## Sample Data Structure

| Date       | Exercise       | Weight | Reps Completed | Target Reps | Notes           |
|------------|----------------|--------|----------------|-------------|-----------------|
| 2024-01-01 | Squat          | 225    | 5              | 5           |                 |
| 2024-01-03 | Bench Press    | 185    | 5              | 5           |                 |
| 2024-01-05 | Squat          | 225    | 5              | 5           |                 |
| 2024-01-08 | Squat          | 225    | 5              | 5           | Ready to progress |
| 2024-01-10 | Overhead Press | 115    | 4              | 5           | Struggled       |
| ...        | ...            | ...    | ...            | ...         | ...             |
| 2024-02-12 | Squat          | 185    | 5              | 5           | DELOAD WEEK     |

## Skills Tested

- **COUNTIFS function**: Count rows meeting multiple criteria
- **Date functions**: Calculate days elapsed, TODAY()
- **Complex IF logic**: Combine IF, AND, OR, NOT functions
- **Cell referencing**: Mix absolute and relative references
- **Conditional formatting**: Apply color rules based on cell values
- **Data analysis**: Interpret messy real-world data

## Tips

- Use structured references if working with tables (e.g., `[@Exercise]`)
- COUNTIFS syntax: `COUNTIFS(range1, criteria1, range2, criteria2, ...)`
- Date calculation: `TODAY() - date_cell` gives days elapsed
- Search for text: `SEARCH("text", cell)` returns position or error
- Conditional formatting: Format → Conditional → Condition...
- Upper body exercises: Bench Press, Overhead Press, Barbell Row (+5 lbs)
- Lower body exercises: Squat, Deadlift (+10 lbs)