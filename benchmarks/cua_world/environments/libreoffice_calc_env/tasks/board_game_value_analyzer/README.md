# Board Game Collection Value Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, conditional logic, data normalization, error handling  
**Duration**: 180 seconds  
**Steps**: ~25

## Objective

Analyze a board game collection by calculating entertainment value metrics from messy real-world data. Handle missing play counts, normalize inconsistent rating scales (1-5 vs 1-10), and create composite value scores to identify which games provide the best value-per-play.

## Task Context

**The Scenario:** You're a board game enthusiast moving to a smaller apartment and need to decide which games to keep. Your collection tracking spreadsheet has messy data—some friends rated games 1-5, others 1-10, and several expensive games have never been played. You need objective metrics to make informed decisions.

## Starting State

- LibreOffice Calc opens with `board_game_collection.ods`
- Columns A-E contain: Game Name, Purchase Price, Play Count, Rating, Last Played Date
- 10 board games with varied data quality
- Some games have 0 plays, ratings use different scales (1-5 and 1-10)

## Data Structure

| Game Name        | Cost | Plays | Rating | Last Played |
|------------------|------|-------|--------|-------------|
| Wingspan         | $40  | 12    | 9      | 2024-11-15  |
| Catan            | $30  | 15    | 4      | 2024-12-20  |
| Pandemic Legacy  | $70  | 8     | 5      | 2024-10-30  |
| Monopoly         | $20  | 2     | 2      | 2023-01-05  |
| Gloomhaven       | $140 | 0     |        | (blank)     |
| Ticket to Ride   | $35  | 24    | 8      | 2024-12-28  |
| Azul             | $30  | 18    | 4      | 2024-11-22  |
| Unmatched        | $25  | 7     | 7      | 2024-09-14  |
| Splendor         | $30  | 11    | 4      | 2024-12-01  |
| 7 Wonders        | $45  | 3     | 3      | 2022-06-10  |

**Note:** Some ratings are 1-5 scale (Catan, Pandemic, Azul, Splendor), others are 1-10 (Wingspan, Ticket to Ride, Unmatched, 7 Wonders)

## Required Actions

### 1. Create Cost-Per-Play Formula (Column F)
- Add header "Cost Per Play" in F1
- In F2, create formula: `=IF(C2>0, B2/C2, B2)`
  - If play count > 0: divide cost by plays
  - If play count = 0 or blank: show original cost
- Copy formula down for all games (F2:F11)
- Format as currency or decimal

### 2. Create Normalized Rating Formula (Column G)
- Add header "Normalized Rating" in G1
- In G2, create formula to convert all ratings to 0-1 scale
  - For 1-5 scale: `(rating-1)/4`
  - For 1-10 scale: `(rating-1)/9`
  - Use conditional logic: `=IF(D2<=5, (D2-1)/4, (D2-1)/9)`
  - Handle blank ratings: `=IF(ISBLANK(D2), 0, IF(D2<=5, (D2-1)/4, (D2-1)/9))`
- Copy formula down for all games (G2:G11)

### 3. Create Value Score Formula (Column H)
- Add header "Value Score" in H1
- In H2, create formula combining low cost-per-play and high rating
  - Example: `=IF(F2>0, G2/(F2/100), 0)` or `=IF(F2>0, (G2*100)/F2, 0)`
  - Higher score = better value (high rating + low cost-per-play)
- Copy formula down for all games (H2:H11)

### 4. Save the File
- Save as `board_game_analysis.ods`

## Success Criteria

1. ✅ **Cost-Per-Play Formula Present**: Column F contains division formula with error handling (IF statement or similar)
2. ✅ **Normalized Rating Formula Present**: Column G contains rating normalization (values between 0-1)
3. ✅ **Value Score Formula Present**: Column H contains formula combining cost and rating
4. ✅ **Correct Calculations**: Spot-checked values match expected results (e.g., Wingspan: $3.33 cost-per-play, 0.89 normalized rating)
5. ✅ **Error Handling**: No #DIV/0!, #VALUE!, or other formula errors
6. ✅ **Data Completeness**: Formulas applied to all game entries

**Pass Threshold**: 70% (requires at least cost-per-play and one additional metric with proper error handling)

## Skills Tested

- **Formula Creation**: Multiple related formulas
- **Conditional Logic**: IF, ISBLANK functions
- **Error Handling**: Division by zero prevention
- **Data Normalization**: Converting different scales
- **Cell References**: Relative references for formula copying
- **Multi-metric Analysis**: Combining multiple data points

## Expected Calculated Values (for verification)

| Game             | Cost/Play | Norm Rating | Value Score |
|------------------|-----------|-------------|-------------|
| Wingspan         | $3.33     | 0.89        | ~26.7       |
| Catan            | $2.00     | 0.75        | ~37.5       |
| Gloomhaven       | $140      | 0.00        | 0           |
| Ticket to Ride   | $1.46     | 0.78        | ~53.4       |

## Tips

- Use IF statements to handle zero or blank play counts
- Detect rating scale by checking if rating ≤ 5
- Normalize ratings: subtract 1, then divide by (max-1)
- For 1-5 scale: (rating-1)/4 converts to 0-1
- For 1-10 scale: (rating-1)/9 converts to 0-1
- Value score can be: (normalized_rating × 100) / cost_per_play
- Remember to handle division by zero in value score too

## Verification Strategy

The verifier checks:
1. **Formula patterns** using regex (not exact string matching)
2. **Calculated values** for 3-4 sample games
3. **Error-free calculation** (no formula errors in any cell)
4. **Complete application** (formulas in all data rows)
5. **Proper normalization** (all normalized ratings between 0-1)