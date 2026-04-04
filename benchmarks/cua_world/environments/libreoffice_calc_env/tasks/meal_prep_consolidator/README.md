# Meal Prep Ingredient Consolidation Task

**Difficulty**: 🟡 Medium  
**Skills**: Data consolidation, SUMIF formulas, VLOOKUP, conditional logic, cross-sheet references  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Consolidate ingredients from 5 different meal recipes into a unified shopping list, eliminate duplicates by aggregating quantities, cross-reference with existing pantry inventory, and calculate how much of each ingredient needs to be purchased. This simulates real-world meal prep planning where people want to minimize grocery trips and avoid buying items they already have.

## Task Description

The agent must:
1. Work with a spreadsheet containing three sheets: **Recipes**, **Pantry**, and **Shopping List**
2. Extract and consolidate all ingredients from 5 different recipes on the Recipes sheet
3. Aggregate quantities for ingredients that appear in multiple recipes
4. Cross-reference each ingredient with the Pantry inventory
5. Calculate "need to buy" amounts: Total Needed - On Hand
6. Populate the Shopping List sheet with only items that need to be purchased (quantity > 0)

## Scenario Context

**User Story:** Sarah meal-preps every Sunday. She has 5 recipes selected for the week but her ingredient lists are scattered. She needs to know exactly what to buy without duplicating items already in her pantry. Manual consolidation is tedious and error-prone - she's forgotten items and bought duplicates before.

## Data Structure

### Recipes Sheet
Contains 5 recipes with ingredients (some ingredients appear in multiple recipes):
- Chicken Stir Fry: chicken breast (2 lbs), olive oil (2 tbsp), onion (1), garlic (2 cloves), bell pepper (2)
- Pasta Primavera: olive oil (2 tbsp), onion (1), garlic (2 cloves), bell pepper (1), pasta (1 lb)
- Taco Bowl: chicken breast (2 lbs), onion (2), bell pepper (1), black beans (2 cans), rice (2 cups)
- Breakfast Scramble: eggs (12), onion (1), bell pepper (1), cheese (1 cup)
- Veggie Soup: onion (2), garlic (2 cloves), carrots (4), celery (4 stalks), vegetable broth (4 cups)

### Pantry Sheet
Current inventory:
- olive oil: 4 tbsp
- onion: 5 whole
- garlic: 1 cloves
- salt: 100 tsp
- pepper: 50 tsp
- rice: 3 cups

### Shopping List Sheet (Empty - Agent Fills)
Expected columns: Ingredient | Quantity to Buy | Unit

## Expected Results

**Key Aggregations:**
- **olive oil**: 2+2 = 4 tbsp needed, 4 on hand → Buy 0 tbsp (should NOT appear in list)
- **chicken breast**: 2+2 = 4 lbs needed, 0 on hand → Buy 4 lbs
- **onion**: 1+1+2+1+2 = 7 needed, 5 on hand → Buy 2
- **garlic**: 2+2+2 = 6 cloves needed, 1 on hand → Buy 5 cloves
- **bell pepper**: 2+1+1+1 = 5 needed, 0 on hand → Buy 5

## Verification Criteria

1. ✅ **Aggregation Correct**: Common ingredients properly summed (3+ spot-checks pass)
2. ✅ **Pantry Subtracted**: On-hand quantities correctly deducted from totals
3. ✅ **Formula-Driven**: Shopping List contains formulas (SUMIF/VLOOKUP), not hard-coded values
4. ✅ **Filtered Properly**: Only items with quantity > 0 appear in Shopping List
5. ✅ **Completeness**: At least 80% of unique ingredients accounted for

**Pass Threshold**: 75% (requires at least 4 out of 5 criteria)

## Skills Tested

- Multi-sheet navigation and cross-sheet references
- Text standardization (handling "onion" vs "onions")
- SUMIF/SUMIFS for aggregation
- VLOOKUP or INDEX-MATCH for inventory lookup
- IF statements for conditional "need to buy" logic
- MAX function to ensure non-negative values
- Data filtering and organization

## Tips

- Start by consolidating all unique ingredients
- Use LOWER() and TRIM() to standardize ingredient names
- SUMIF to aggregate quantities: `=SUMIF(Recipes.B:B, "chicken", Recipes.C:C)`
- VLOOKUP for pantry check: `=VLOOKUP(A2, Pantry.A:B, 2, FALSE)`
- Handle not-found cases with IFERROR: `=IFERROR(VLOOKUP(...), 0)`
- Calculate need: `=MAX(0, TotalNeeded - OnHand)`
- Filter final list to show only positive quantities