# Garage Sale Pricing Strategy Task

**Difficulty**: 🟡 Medium  
**Skills**: Conditional formulas, IF statements, percentage calculations, currency formatting  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Help a family create a strategic pricing strategy for their garage sale by analyzing item conditions and applying category-based discounts. This task tests conditional logic, multi-factor calculations, and business math application in a real-world scenario.

## Task Description

The agent must:
1. Open a CSV file containing garage sale inventory with item details
2. Create a "Base Price" column using IF formulas based on item condition:
   - Excellent condition: 80% of Market Research Price
   - Good condition: 65% of Market Research Price  
   - Fair condition: 45% of Market Research Price
3. Create a "Quick Sale?" column identifying bulky items (Furniture, Large Appliances)
4. Create a "Final Sale Price" column applying 20% additional discount to Quick Sale items
5. Calculate total projected revenue using SUM formula
6. Format price columns as currency
7. Save the file

## Expected Results

- **Base Price formula** correctly implements condition-based percentages
- **Quick Sale logic** identifies Furniture and Large Appliances categories
- **Final Sale Price** applies additional 20% discount to Quick Sale items
- **Minimum prices** are enforced (no item below $1.00)
- **Total Revenue** accurately sums all Final Sale Prices
- **Currency formatting** applied to all price columns

## Verification Criteria

1. ✅ **Base Price Formula Correct**: Condition-based percentages properly implemented (4+ items)
2. ✅ **Quick Sale Logic Applied**: Furniture/appliances discounted by ~20%, others not
3. ✅ **Minimum Price Enforced**: All items ≥ $1.00
4. ✅ **Revenue Accurately Summed**: Total within $0.50 of correct sum
5. ✅ **Currency Formatted**: Price columns show $ symbol and 2 decimals
6. ✅ **File Saved**: File exists as garage_sale_pricing.ods

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Nested IF statement creation
- Cell referencing (relative and absolute)
- Percentage-based calculations
- Conditional category logic
- SUM function usage
- Currency number formatting
- Business decision modeling

## CSV Data Structure

The provided CSV contains approximately 20-25 household items with:
- **Item Name**: Description of the item
- **Category**: Furniture, Electronics, Appliances, Kitchen, Decor, Sports, Clothing
- **Original Price**: What was originally paid
- **Condition**: Excellent, Good, or Fair
- **Market Research Price**: Comparable online prices
- **Notes**: Additional item details

## Tips

- Use nested IF statements: `=IF(condition1, value1, IF(condition2, value2, value3))`
- For Quick Sale detection, check if category contains "Furniture" or "Appliances"
- Round final prices to nearest dollar for simplicity: `=ROUND(value, 0)`
- Ensure minimum price with MAX: `=MAX(calculated_price, 1)`
- Apply currency format: Format → Cells → Currency → $
- Don't forget to SUM the Final Sale Price column for total revenue