# Golden Hour Photography Schedule Optimizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data sorting, time formulas, cumulative calculations, schedule optimization  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Optimize a photography shoot schedule by sorting locations based on optimal golden hour lighting times and calculating cumulative arrival times. This task tests data sorting, time arithmetic, formula creation, and logical planning skills essential for real-world scheduling optimization.

## Task Description

You're a freelance photographer planning tomorrow's golden hour portrait shoot. A client gave you 5 locations around the city for engagement photos, but they're listed in random order. You need to reorganize them to optimize for golden hour lighting and calculate when you'll arrive at each location.

The agent must:
1. Open a spreadsheet with 5 scrambled photography locations
2. Sort locations by "Optimal Start Time" (ascending order)
3. Add an "Arrival Time" column
4. Calculate arrival times using formulas that account for:
   - First location: Arrive at optimal start time
   - Subsequent locations: Previous arrival + setup time + travel time
5. Verify the schedule is feasible within golden hour constraints

## Data Structure

- **Location Name**: Name of photo location
- **Address**: Street address
- **Optimal Start Time**: Best moment to shoot based on light direction (HH:MM format)
- **Travel Time**: Minutes to drive from previous location
- **Setup Time**: 5 minutes for equipment setup (constant)

## Expected Results

- Locations sorted by Optimal Start Time in ascending order
- New "Arrival Time" column with formulas (not hardcoded values)
- First arrival time = first optimal start time
- Subsequent arrivals = previous arrival + previous setup + previous travel
- All arrivals within reasonable golden hour window (~60 minutes)

## Verification Criteria

1. ✅ **Correctly Sorted**: Locations ordered by Optimal Start Time (ascending)
2. ✅ **Arrival Times Calculated**: New column with formulas for each location
3. ✅ **Formula Accuracy**: Cumulative time calculations are mathematically correct (±2 min tolerance)
4. ✅ **Logical Schedule**: All arrivals fall within feasible time window

**Pass Threshold**: 75% (3/4 criteria must pass)

## Skills Tested

- Data range selection and sorting
- Time value manipulation
- Formula creation with cell references
- Cumulative calculation logic
- Time arithmetic (TIME function or equivalent)
- Understanding sequential dependencies

## Real-World Context

Professional photographers face this scheduling puzzle constantly. Golden hour only lasts about an hour, and arriving 10 minutes late to a west-facing location could mean missing the magic light entirely. This task represents scheduling optimization problems across many professions: delivery routing, sales calls, field service, event planning, etc.

## Tips

- Select entire data range before sorting to maintain row integrity
- Use Data → Sort menu
- First arrival time should reference the Optimal Start Time directly
- Subsequent arrivals need formulas: `=PreviousArrival + TIME(0, SetupMinutes + TravelMinutes, 0)`
- Or use simpler format: `=F2 + (E2+D2)/1440` where 1440 = minutes in a day
- Verify times progress forward logically