# Board Game Night Win Rate Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data organization, COUNTIF formulas, percentage calculations, statistical analysis  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Organize board game night records and calculate meaningful player performance statistics. A weekly game group has been tracking wins casually and wants to analyze who's actually the strongest player and which games are most popular.

## Task Description

The agent must:
1. Open a spreadsheet containing raw game night data (GameLog sheet)
2. Analyze the data structure: Date, GameName, Winner columns
3. Create a player statistics section
4. Use COUNTIF formulas to count wins per player
5. Calculate games played for each player
6. Calculate win rate percentages (wins/games * 100)
7. Identify the top performer by win rate

## Starting Data Structure

**GameLog Sheet** contains ~25 game records:
- **Date**: Game session date (e.g., 2024-01-05)
- **GameName**: Name of game played (Catan, Ticket to Ride, etc.)
- **Winner**: Player who won that game
- **Players**: Number of players or comma-separated list

**5 Regular Players**: Alex, Blake, Casey, Drew, Ellis

## Expected Output

Create a player statistics section with columns:
- Player Name
- Total Wins (using COUNTIF formula)
- Games Played (count of participation)
- Win Rate (percentage: wins/games * 100)

## Success Criteria

1. ✅ **Player statistics section exists**: All 5 players represented
2. ✅ **Formulas used correctly**: COUNTIF or equivalent for counting wins
3. ✅ **Win rates calculated**: Correct percentage formula structure
4. ✅ **Mathematical accuracy**: Calculated values match expected results (±0.5%)
5. ✅ **Top player identifiable**: Clear indication of highest win rate

**Pass Threshold**: 75% (4 out of 5 criteria)

## Skills Tested

- Data analysis and organization
- COUNTIF function usage
- Cell reference mastery (absolute vs relative)
- Percentage calculation formulas
- Statistical interpretation
- Data structure understanding

## Example Statistics Output

| Player | Total Wins | Games Played | Win Rate |
|--------|------------|--------------|----------|
| Alex   | 6          | 23           | 26.1%    |
| Blake  | 7          | 25           | 28.0%    |
| Casey  | 5          | 24           | 20.8%    |
| Drew   | 4          | 22           | 18.2%    |
| Ellis  | 3          | 21           | 14.3%    |

## Tips

- Use COUNTIF to count how many times each player name appears in the Winner column
- Formula example: `=COUNTIF(B:B,"Alex")` counts "Alex" in column B
- Win rate formula: `=(TotalWins/GamesPlayed)*100` or format as percentage
- Games played can be manually counted or calculated (depends on data structure)
- Sort by Win Rate to easily identify top player

## Verification

Verifier checks:
1. Presence of player statistics with all players
2. Use of formulas (not manual values)
3. Correct COUNTIF or equivalent counting logic
4. Accurate win rate calculations
5. Mathematical correctness (recalculates and compares)