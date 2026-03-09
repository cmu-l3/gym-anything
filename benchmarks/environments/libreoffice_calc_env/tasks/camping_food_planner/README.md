# Camping Food Planner Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-variable formulas, conditional logic, data consolidation, cost allocation  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Create a practical camping trip food planning spreadsheet that calculates quantities based on servings per person per day, accommodates dietary restrictions, consolidates a shopping list, and fairly splits costs among participants.

## Task Description

You are organizing food for a 7-person, 5-day backcountry camping trip. The agent must:

1. **Calculate total quantities needed** for each food item using formula:
   - `(Number_of_people_eating × Servings_per_person_per_day × Trip_days) × 1.1`
   - Account for dietary restrictions (vegetarians don't eat meat items, gluten-free participants skip pasta/bread)
   - Apply 1.1 safety factor (10% extra) to all quantities

2. **Calculate total cost per item**:
   - `Total_quantity × Unit_cost`

3. **Build consolidated shopping list**:
   - Summary of all items with quantities and costs

4. **Calculate cost per person**:
   - Fair splitting based on what each person will actually consume
   - Shared items (oil, spices) split equally among all 7 people

5. **Format for clarity**:
   - Currency formatting for costs
   - Clear headers and structure

## Starting State

A partially pre-populated spreadsheet opens with:
- **Trip Parameters**: 7 people, 5 days, 1.1 safety factor
- **Participants List**: 7 people with dietary restriction flags
  - 3 vegetarians (Beth, Dana, Greg)
  - 2 gluten-free (Chris, Dana)
- **Food Items Table**: 8 items with unit costs, servings/person/day, and who eats them
  - Items include: Rice, Pasta, Chicken, Black Beans, Oatmeal, Trail Mix, Cooking Oil, Coffee

**Agent must add formulas** in "Total Quantity" and "Total Cost" columns.

## Expected Results

### Sample Calculations
- **Rice** (everyone eats): 7 × 0.5 servings/day × 5 days × 1.1 = **19.25 cups**
- **Chicken** (5 non-vegetarians): 5 × 0.4 lbs/day × 5 days × 1.1 = **11.0 lbs**
- **Pasta** (5 non-gluten-free): 5 × 0.3 lbs/day × 5 days × 1.1 = **8.25 lbs**

### Shopping List
Consolidated summary with item names, total quantities, and total costs.

### Cost Per Person
Individual cost breakdown ensuring:
- Vegetarians pay less (don't pay for meat)
- Gluten-free participants don't pay for pasta
- Sum of individual costs = Total food budget

## Verification Criteria

1. ✅ **Quantity formulas present**: Cells contain formulas (not hard-coded values)
2. ✅ **Calculations correct**: Sample items calculate to expected values (±0.5 tolerance)
3. ✅ **Safety factor applied**: 1.1 multiplier included in quantity formulas
4. ✅ **Cost per person exists**: Individual cost breakdown present and sums to total
5. ✅ **Shopping list created**: Consolidated summary section with all items
6. ✅ **Dietary restrictions honored**: Different participant counts for restricted items

**Pass Threshold**: 80% (5/6 criteria must pass)

## Skills Tested

- Multi-variable formula creation (multiplication of 3+ terms)
- Conditional calculations (if vegetarian, use different count)
- Cell reference management (absolute vs. relative)
- Data consolidation across tables
- Cost allocation algorithms
- Practical scenario modeling
- Number formatting (currency, decimals)

## Real-World Context

This represents authentic group trip planning where:
- People have different dietary needs
- Costs should be split fairly (pay for what you eat)
- Safety margins are essential (10% extra for outdoor activities)
- Clear documentation helps group coordination

## Tips

- Reference trip parameter cells (people count, days, safety factor) in formulas
- Use multiplication: `=C2*D2*E2*F2` (people × servings × days × safety_factor)
- For vegetarian items, count only non-vegetarians (e.g., 5 people for meat)
- Shopping list can use cell references to main table calculations
- Cost per person requires summing only items each person consumes