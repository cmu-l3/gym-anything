# Yarn Project Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Cross-sheet formulas, CEILING function, unit conversions, multi-step calculations  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Help a knitter calculate yarn requirements for a sweater project when substituting yarn. Create formulas to determine how many skeins are needed and compare costs across yarn options to find the best value.

## Task Description

The agent must:
1. Open a pre-populated 3-sheet workbook (Pattern_Specs, Yarn_Options, Calculations)
2. Navigate to the Calculations sheet
3. Pull total yardage needed from Pattern_Specs sheet (Medium size sweater)
4. Apply a 15% safety margin to account for gauge variations
5. Calculate skeins needed for each yarn option using CEILING function (must round UP)
6. Calculate total cost for each yarn option
7. Identify the most economical yarn choice
8. Save the completed workbook

## Starting State

**Pattern_Specs Sheet:**
| Size   | Total Yardage | Gauge (st/in) |
|--------|---------------|---------------|
| Small  | 1200          | 5.5           |
| Medium | 1400          | 5.5           |
| Large  | 1650          | 5.5           |

**Yarn_Options Sheet:**
| Yarn Name      | Fiber       | Yards/Skein | Price/Skein | Color Options |
|----------------|-------------|-------------|-------------|---------------|
| Cozy Wool      | 100% Wool   | 220         | 8.50        | 45            |
| Budget Acrylic | Acrylic     | 280         | 4.99        | 30            |
| Luxury Blend   | Wool/Silk   | 200         | 12.00       | 20            |

**Calculations Sheet (template):**
Headers and structure provided, formulas to be added by agent.

## Expected Results

- **B2**: Base yardage for Medium size (reference to Pattern_Specs)
- **B3**: Adjusted yardage with 15% safety margin (B2 × 1.15)
- **B5, C5, D5**: Skeins needed for each yarn option using CEILING function
- **B6, C6, D6**: Total cost for each option (skeins × price)
- **Shopping list section**: Details of most economical option

## Verification Criteria

1. ✅ **Safety Margin Applied**: Adjusted yardage is 10-15% higher than base
2. ✅ **Correct Rounding**: CEILING function used (all skein quantities are integers)
3. ✅ **Accurate Costs**: Total cost = skeins × price (±$0.50 tolerance)
4. ✅ **Best Option Identified**: Shopping list shows lowest-cost yarn
5. ✅ **Cross-sheet Formulas**: References Pattern_Specs and Yarn_Options sheets
6. ✅ **Proper Formatting**: Currency symbols, no decimals for skeins

**Pass Threshold**: 75% (5/6 criteria must pass)

## Skills Tested

- Cross-sheet cell references (Sheet1.A1 syntax)
- CEILING function for always-round-up scenarios
- Percentage calculations (safety margins)
- Formula dependencies and calculation chains
- Cost comparison and decision-making
- Professional spreadsheet formatting

## Tips

- Use cross-sheet references: `=Pattern_Specs.B3` to pull from other sheets
- CEILING syntax: `=CEILING(value, 1)` always rounds UP to nearest integer
- Can't buy partial skeins - must always round up (4.3 skeins = 5 skeins)
- Safety margin prevents running out mid-project (gauge variations, mistakes)
- Select Medium size (row 3) from Pattern_Specs
- Compare all three yarn options to find cheapest total cost

## Real-World Context

Knitters constantly substitute yarns when patterns call for discontinued products or when managing budgets. Miscalculating quantities is a common mistake that leads to:
- Running out of yarn with project 90% complete
- Mismatched dye lots (can't buy more of exact same color batch later)
- Wasted money buying too much excess yarn

This calculation prevents costly errors in craft projects typically costing $50-150.