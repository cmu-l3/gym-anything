# Commute Route Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Statistical analysis, formula nesting, multi-criteria decision making  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~15

## Objective

Analyze real-world commute data to help someone choose the best route to their new job. Calculate average times, reliability (standard deviation), and weekly costs for three different routes, then make a data-driven recommendation. This task tests statistical thinking, formula creation, and practical decision-making with messy, incomplete data.

## Task Description

The agent must:
1. Work with a partially-filled spreadsheet containing 10 days of commute data for 3 routes
2. Calculate average commute time for each route (using AVERAGE function)
3. Calculate reliability (standard deviation) for each route (using STDEV function)
4. Calculate weekly costs considering tolls and gas
5. Create a clear summary comparing all three routes
6. Make a recommendation by highlighting the best route
7. Save the analysis

## Context

Sarah just got a new job and has been testing three different routes for two weeks:
- **Highway Route**: Fast but has traffic variability, $3.50 toll each way
- **Scenic Route**: Moderate speed, very consistent, no tolls
- **City Streets**: Variable due to traffic lights, no tolls

Some days are missing data (worked from home).

## Data Structure

| Day       | Highway (min) | Scenic (min) | City (min) |
|-----------|---------------|--------------|------------|
| Mon (W1)  | 25            | 34           | 28         |
| Tue (W1)  | 32            | 36           | 45         |
| Wed (W1)  | 27            | 33           | 31         |
| Thu (W1)  | [empty]       | 35           | 29         |
| Fri (W1)  | 38            | 37           | 42         |
| Mon (W2)  | 24            | 35           | 26         |
| Tue (W2)  | 45            | 38           | [empty]    |
| Wed (W2)  | 26            | 34           | 30         |
| Thu (W2)  | 29            | 36           | 35         |
| Fri (W2)  | 31            | 37           | 39         |

**Additional Information:**
- Highway Route: 18 miles, $3.50 toll each way, estimate $27/week gas
- Scenic Route: 22 miles, no tolls, estimate $33/week gas
- City Streets: 16 miles, no tolls, estimate $24/week gas

## Required Actions

1. **Calculate Averages**: Add AVERAGE formulas for each route
2. **Calculate Reliability**: Add STDEV formulas to measure consistency
3. **Calculate Weekly Costs**: 
   - Highway: `=(3.50 * 10) + 27` = $62/week
   - Scenic: `=33` = $33/week
   - City: `=24` = $24/week
4. **Create Summary Table**: Organize route comparison clearly
5. **Make Recommendation**: Highlight the best route (typically Scenic due to reliability)

## Expected Analysis Results
