# Poker Night Settlement Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-column formulas, SUM, arithmetic, data validation, conditional formatting, sorting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Manage the financial reconciliation of a home poker night where friends made multiple buy-ins throughout the evening. Calculate each player's net position (profit/loss) and verify the zero-sum constraint to ensure proper settlement.

## Task Description

The agent must:
1. Import poker night data showing player buy-ins and final chip counts
2. Calculate total buy-ins per player (sum of initial + rebuys)
3. Calculate net position for each player (final chips - total buy-ins)
4. Verify zero-sum constraint (all net positions must sum to $0)
5. Apply conditional formatting to distinguish winners (positive) from losers (negative)
6. Sort players by net position to facilitate settlement planning
7. Save the completed reconciliation

## Starting Data

CSV file with 8 players containing:
- **Player name** (Column A)
- **Initial buy-in** (Column B) - all players start with $50
- **Rebuy 1** (Column C) - $25 if rebought (blank otherwise)
- **Rebuy 2** (Column D) - $25 if rebought again (blank otherwise)  
- **Final chip count** (Column E) - chips held at end of night

## Expected Results

Agent should create:
- **Column F (Total Buy-in)**: SUM formula adding all buy-ins per player
- **Column G (Net Position)**: Formula calculating (Final Chips - Total Buy-in)
- **Zero-sum verification**: Sum of all net positions ≈ $0 (within $1 tolerance)
- **Conditional formatting**: Green for positive (winners), red for negative (losers)
- **Sorted data**: Players sorted by net position (descending)

## Verification Criteria

1. ✅ **Data Integrity**: All 8 players present with valid numeric data (20%)
2. ✅ **Total Buy-in Formulas**: Column F correctly sums buy-ins using formulas (20%)
3. ✅ **Net Position Formulas**: Column G correctly calculates net positions (25%)
4. ✅ **Zero-Sum Validation**: Net positions sum to $0 ± $1 tolerance (30%) **CRITICAL**
5. ✅ **Organization**: Data sorted by net position descending (5% bonus)

**Pass Threshold**: 75% (requires correct formulas and zero-sum validation)

## Skills Tested

- CSV import and data handling
- Multi-column SUM formulas with blank cell handling
- Arithmetic formula creation
- Cell reference management (relative references)
- Data validation and mathematical constraints
- Conditional formatting application
- Sorting operations maintaining row integrity
- Financial reconciliation logic

## Real-World Context

This task simulates common multi-party financial reconciliation scenarios:
- Splitting group vacation expenses
- Managing community potluck reimbursements
- Tracking rotating dinner clubs
- Handling office lunch orders with varying participation

The zero-sum constraint ensures mathematical integrity: in a closed economy (poker game), total winnings must equal total losses.

## Tips

- Use `=SUM(B2:D2)` to total all buy-ins (handles blank cells automatically)
- Net position formula: `=E2-F2`
- Select data range before applying conditional formatting
- Use Data → Sort with header row option enabled
- A verification row showing `=SUM(G2:G9)` helps confirm zero-sum