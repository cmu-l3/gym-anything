# Fair Rent Split Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-factor formulas, weighted calculations, proportional allocation  
**Duration**: 180 seconds  
**Steps**: ~12

## Objective

Create a fair rent allocation system for a shared apartment where rooms have different qualities. Calculate weighted scores based on multiple room characteristics, then proportionally distribute the total rent based on each room's relative desirability. This task tests complex formula creation, weighted analysis, and proportional distribution logic.

## Task Description

The agent must:
1. Open a spreadsheet containing room characteristics (size, bathroom, parking, floor, light)
2. Create formulas to calculate weighted scores for each room based on multiple factors
3. Calculate each room's proportion of the total desirability
4. Calculate individual rent amounts proportional to weighted scores
5. Ensure all calculations are mathematically consistent (rent amounts sum to total rent)

## Starting State

- LibreOffice Calc opens with room characteristics data
- Data includes: Tenant Name, Room, Square Footage, Private Bath, Parking, Floor, Natural Light
- Columns for Weighted Score, Rent Proportion, and Monthly Rent are empty (agent must add formulas)
- Total monthly rent: $3,200

## Data Structure

| Tenant | Room | Sq Ft | Private Bath | Parking | Floor | Light (1-5) | Weighted Score | Rent Proportion | Monthly Rent |
|--------|------|-------|--------------|---------|-------|-------------|----------------|-----------------|--------------|
| Alex   | A    | 180   | Yes          | Yes     | 3     | 4           | [FORMULA]      | [FORMULA]       | [FORMULA]    |
| Blake  | B    | 140   | No           | No      | 2     | 3           | [FORMULA]      | [FORMULA]       | [FORMULA]    |
| Casey  | C    | 160   | Yes          | No      | 3     | 5           | [FORMULA]      | [FORMULA]       | [FORMULA]    |
| Drew   | D    | 200   | Yes          | Yes     | 1     | 2           | [FORMULA]      | [FORMULA]       | [FORMULA]    |

## Weighting System

Calculate weighted scores using these factors:
- **Square footage**: 2.5 points per sq ft
- **Private bathroom**: +150 points (0 if shared)
- **Parking spot**: +100 points (0 if no parking)
- **Floor level**: +20 points per floor
- **Natural light**: rating × 30 points

**Example formula for row 2 (Alex):**