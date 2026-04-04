# Fantasy Football Weekly Lineup Optimizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-criteria analysis, conditional logic, constraint optimization  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~15

## Objective

Analyze player statistics to calculate optimal fantasy football lineup within position constraints. This task tests multi-criteria decision-making, formula creation, conditional logic, and constraint satisfaction—common spreadsheet optimization scenarios.

## Task Description

You're managing your fantasy football team on Tuesday morning before the Thursday night game locks your lineup. Your league uses standard PPR (Point Per Reception) scoring, and you need to determine which players to start from your roster to maximize projected points while satisfying position requirements.

The agent must:
1. Open the roster CSV file with projected player statistics
2. Calculate projected fantasy points for each player using scoring formula
3. Identify the optimal starting lineup within position constraints
4. Mark players as "START" or "BENCH" accordingly
5. Calculate total projected points for the starting lineup
6. Save the file

## Scoring Formula (Standard PPR)

- **Rushing Yards**: 0.1 points per yard
- **Receiving Yards**: 0.1 points per yard
- **Receptions**: 1 point each (PPR)
- **Rushing TDs**: 6 points each
- **Receiving TDs**: 6 points each
- **Passing Yards**: 0.04 points per yard
- **Passing TDs**: 4 points each

## Position Constraints (Standard Fantasy Lineup)

- **1 QB** (Quarterback)
- **2 RB** (Running Backs)
- **2 WR** (Wide Receivers)
- **1 TE** (Tight End)
- **1 FLEX** (RB, WR, or TE - highest remaining scorer)

**Total**: 7 starters

## Expected Results

### New Columns Created:
- **Projected Points**: Calculated using scoring formula for each player
- **Lineup Status**: "START" for starters (7 players), "BENCH" for bench players

### Lineup Optimization:
- Select highest-scoring QB
- Select 2 highest-scoring RBs
- Select 2 highest-scoring WRs
- Select highest-scoring TE
- Select highest remaining RB/WR/TE for FLEX position
- Total projected points calculated and displayed

## Verification Criteria

1. ✅ **Calculations Correct**: All projected points match scoring formula (±0.5 tolerance)
2. ✅ **Constraints Satisfied**: Exactly 7 starters with correct position breakdown
3. ✅ **Optimization Quality**: Lineup within 5% of greedy optimal points
4. ✅ **Complete Labeling**: All players marked START or BENCH appropriately

**Pass Threshold**: 85% (all criteria must be substantially met)

## Skills Tested

- Multi-column formula creation (SUM of weighted statistics)
- Conditional logic (IF statements for lineup decisions)
- Ranking and sorting by calculated values
- Constraint satisfaction (position limits)
- Optimization within constraints
- Data analysis and decision-making

## CSV Data Structure

The roster CSV contains:
- **Player Name**: Player's full name
- **Position**: QB, RB, WR, or TE
- **Proj Rush Yds**: Projected rushing yards
- **Proj Rec Yds**: Projected receiving yards
- **Proj Receptions**: Projected number of catches
- **Proj Rush TDs**: Projected rushing touchdowns
- **Proj Rec TDs**: Projected receiving touchdowns
- **Proj Pass Yds**: Projected passing yards (QBs only)
- **Proj Pass TDs**: Projected passing touchdowns (QBs only)

## Tips

- Create a "Projected Points" column first with the scoring formula
- Calculate points for all players before selecting starters
- Use sorting or ranking to identify top players by position
- Ensure FLEX player is the highest remaining scorer (not already counted)
- Create a "Lineup Status" column to mark START/BENCH
- Sum projected points for all START players to verify total
- Double-check exactly 7 players are marked START

## Realistic Scenario Context

This simulates a real weekly task that millions of fantasy football managers perform. The spreadsheet helps make data-driven decisions by aggregating multiple statistical projections into a single scoring metric, then optimizing player selection within league rules. Similar constraint-based optimization appears in many domains: shift scheduling, resource allocation, budget optimization, and portfolio selection.