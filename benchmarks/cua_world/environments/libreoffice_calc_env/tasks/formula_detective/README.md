# Formula Detective Task

**Difficulty**: 🟡 Medium-High  
**Skills**: Formula analysis, pattern recognition, reverse engineering, logical deduction  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~15

## Objective

Analyze a partially corrupted sales commission spreadsheet and reverse-engineer missing formulas by studying patterns in existing correct calculations. This task tests formula comprehension, debugging skills, and pattern recognition.

## Task Description

**Scenario**: A small business owner's commission spreadsheet was partially corrupted when opened in an older version of Excel. Several formula cells were accidentally converted to static values, breaking automatic calculations. The quarterly report is due tomorrow, and you need to reconstruct the missing formulas by analyzing the intact ones.

**The Challenge**:
- Some commission and payout formulas still work correctly
- Others show only static values (marked with light red background)
- You must deduce the commission structure from working examples
- Then rebuild the missing formulas in corrupted cells

## Data Structure

| Row | Sales Rep | Sales Amount | Commission | Status | Total Payout |
|-----|-----------|--------------|------------|--------|--------------|
| 1   | (Header)  | (Header)     | (Header)   | (Header)| (Header)    |
| 2   | Rep A     | $8,500       | FORMULA ✓  | Standard| FORMULA ✓   |
| 3   | Rep B     | $12,000      | **BROKEN** | Standard| **BROKEN**  |
| 4   | Rep C     | $18,000      | FORMULA ✓  | Premium | FORMULA ✓   |
| 5   | Rep D     | $22,000      | **BROKEN** | Premium | **BROKEN**  |
| 6   | Rep E     | $28,000      | FORMULA ✓  | Standard| FORMULA ✓   |
| 7   | Rep F     | $15,000      | **BROKEN** | Premium | **BROKEN**  |
| 8   | Rep G     | $5,000       | FORMULA ✓  | Standard| FORMULA ✓   |

## Commission Structure (to be deduced)

By analyzing intact formulas, you should discover:
- **Tier 1**: Sales $0-$10,000 → 5% commission
- **Tier 2**: Sales $10,001-$25,000 → 7% commission  
- **Tier 3**: Sales $25,001+ → 10% commission

**Bonus Rule**: "Premium" status employees get $500 bonus if commission > $1,000

## Required Actions

1. **Analyze** intact formulas in Commission column (cells D2, D4, D6, D8)
2. **Identify** the tiered commission structure
3. **Reconstruct** commission formulas in corrupted cells (D3, D5, D7)
4. **Analyze** intact Total Payout formulas (cells F2, F4, F6, F8)
5. **Identify** the bonus logic for Premium status
6. **Reconstruct** payout formulas in corrupted cells (F3, F5, F7)
7. **Verify** formulas produce correct results
8. Save the repaired spreadsheet

## Expected Formula Patterns

**Commission Formula** (example for row 2):