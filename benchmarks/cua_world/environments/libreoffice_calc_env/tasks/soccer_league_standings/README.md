# Soccer League Standings Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Complex formulas, multi-criteria sorting, sports data analysis  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Calculate final standings for an amateur soccer league based on match results. Apply the standard soccer points system (Win=3pts, Draw=1pt, Loss=0pts), calculate goal difference as a tiebreaker, and produce a properly sorted standings table with ranking positions.

## Task Description

You are the volunteer coordinator for your local community soccer league. The season has just ended and you need to produce the official final standings to determine:
- Which team wins the championship trophy
- Which teams qualify for next season's playoffs
- Official records for the league archive

The agent must:
1. Open the spreadsheet containing match results from the season
2. Create or complete a standings table with all teams
3. Calculate statistics for each team:
   - Matches Played (P)
   - Wins (W)
   - Draws (D)
   - Losses (L)
   - Goals For (GF)
   - Goals Against (GA)
   - Goal Difference (GD = GF - GA)
   - Points (Pts = W*3 + D*1)
4. Sort the standings by Points (descending), then by Goal Difference (descending)
5. Add position/rank numbers (1, 2, 3, ...)
6. Save the file

## Match Results Data Structure

The spreadsheet contains a "Match Results" sheet with columns:
- Match Date
- Home Team
- Home Goals
- Away Goals
- Away Team

Each row represents one match played during the season.

## Expected Results

**Standings Table** with columns:
- Position (1, 2, 3, ...)
- Team Name
- P (Played)
- W (Wins)
- D (Draws)
- L (Losses)
- GF (Goals For)
- GA (Goals Against)
- GD (Goal Difference)
- Pts (Points)

**Sorted** by:
1. Points (descending) - primary
2. Goal Difference (descending) - tiebreaker

## Verification Criteria

1. ✅ **All Teams Included**: Every team from match results appears exactly once
2. ✅ **Points Correctly Calculated**: Points = Wins*3 + Draws*1 for all teams
3. ✅ **Goal Difference Correct**: GD = GF - GA for all teams
4. ✅ **Primary Sort Valid**: Teams sorted by Points (descending)
5. ✅ **Tiebreaker Sort Valid**: Teams tied on points sorted by GD (descending)
6. ✅ **Position Column Accurate**: Positions numbered 1, 2, 3, ... N

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Skills Tested

- **COUNTIFS Function**: Count wins/draws/losses by team
- **SUMIF Function**: Sum goals scored/conceded by team
- **Multi-level Sorting**: Sort with primary and secondary criteria
- **Complex Formulas**: Combine multiple functions and references
- **Data Analysis**: Understanding sports ranking logic
- **Absolute References**: Use $ correctly when copying formulas

## Formula Examples

**Matches Played (for team in A2):**