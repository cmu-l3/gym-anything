# Task: Multi-Rate Tax Compliance Configuration

## Overview
**Role**: Restaurant General Manager / Accountant
**Difficulty**: Very Hard
**Domain**: Restaurant POS Tax Management

## Business Context
A restaurant has received a compliance audit notice. The POS system currently has a single generic "US" tax rate (6%) applied to all sales. State regulations require separate tax rates for different product categories: food, alcohol, and retail merchandise. The manager must configure the Floreant POS system to be compliant by creating category-specific tax rates and reassigning existing menu items to the correct tax bracket.

## Task Requirements

### Part 1: Create Three New Tax Rates
Navigate to the tax configuration section in Back Office and create:
1. **FOOD TAX** — 5.5%
2. **ALCOHOL TAX** — 9.0%
3. **RETAIL TAX** — 7.25%

### Part 2: Reassign Menu Items
After creating the tax rates:
1. Find all menu items in the **BEER & WINE** category and change their tax to **ALCOHOL TAX**
2. Find all menu items in the **RETAIL** category and change their tax to **RETAIL TAX**
3. The original **US** tax (6.0%) must remain unchanged

## Success Criteria
- 3 new tax entries exist with exact names and rates (±0.01%)
- All BEER & WINE items reassigned to ALCOHOL TAX
- All RETAIL items reassigned to RETAIL TAX
- US tax rate unchanged at 6.0%

## Verification
Verification queries the Apache Derby database directly after the task ends:
- `TAX` table: checks for new entries with correct names and percentage rates
- `MENUITEM` table: checks TAX_ID foreign key for items in target categories

## Application Access
- **PIN**: 1111 (numeric keypad in Back Office)
- **Secret Key dialog**: Leave empty, click OK
- **Tax menu**: Back Office → Explorers → Tax
- **Menu Items**: Back Office → Explorers → Menu Items

## Scoring (100 points)
- FOOD TAX created correctly: 10 pts
- ALCOHOL TAX created correctly: 10 pts
- RETAIL TAX created correctly: 10 pts
- BEER & WINE items reassigned (≥1 item): 20 pts
- All BEER & WINE items reassigned: 20 pts
- RETAIL items reassigned (≥1 item): 20 pts
- US tax unchanged at 6.0%: 10 pts
- Pass threshold: 60 points
