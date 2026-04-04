# Used Textbook Price Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Conditional formulas (IF), MIN functions, data cleaning, conditional formatting  
**Duration**: 240 seconds  
**Steps**: ~20

## Objective

Help a college student make smart textbook purchasing decisions by cleaning messy price comparison data, calculating true costs (including shipping and access codes), and identifying the best deal for each book within budget constraints.

## Task Description

A student has been frantically tracking textbook prices across multiple sources (campus bookstore, Amazon, classmate marketplace) but recorded information inconsistently. With classes starting in 3 days, they need to:

1. **Standardize the messy data** - Notes about shipping and access codes are inconsistent
2. **Calculate true costs** - Some prices include shipping, others don't; some include access codes, others don't
3. **Identify best deals** - Find the lowest-cost option for each textbook
4. **Apply visual highlighting** - Mark best deals with conditional formatting
5. **Calculate total budget** - Ensure total stays within $600 budget

## Starting Data Structure

The CSV contains:
- **Course**: Course code (e.g., "CHEM 101")
- **Book Title**: Textbook name
- **Required Edition**: Minimum acceptable edition number
- **Campus Bookstore**: Base price from campus store
- **Amazon**: Base price from Amazon
- **Marketplace**: Base price from student marketplace
- **Notes**: Messy notes about shipping, access codes, edition info

## Real-World Messiness

- Notes say "shipping included" vs "+$5 ship" vs blank (assume $5 if online and not mentioned)
- Access codes sometimes included, sometimes not; when needed but not included, add $85
- Some sources are out of stock (blank entries)
- Edition numbers vary: "12th ed", "12e", "12", or missing

## Required Actions

1. **Create "True Cost" columns** for each seller (Campus, Amazon, Marketplace)
   - Use IF formulas to add shipping if not included
   - Use IF formulas to add access code cost if needed but not included
   - Handle blank/missing entries gracefully

2. **Add "Best Deal" column**
   - Use MIN function to find lowest true cost
   - Identify which source offers the best price

3. **Apply conditional formatting**
   - Highlight the best deal cells (e.g., green fill)
   - Mark any books over budget threshold

4. **Calculate budget total**
   - Sum all "Best Deal" prices
   - Compare against $600 budget

## Success Criteria

1. ✅ **True Cost formulas present**: Calculated columns exist with IF logic for shipping/access codes
2. ✅ **Calculation accuracy**: At least 3 sample books have correct True Cost (within $1)
3. ✅ **Best Deal identified**: MIN function correctly identifies lowest cost for each book
4. ✅ **Conditional formatting applied**: Visual highlighting present for best deals
5. ✅ **Budget calculation correct**: Total sum matches expected value (±$2 tolerance)
6. ✅ **Formula robustness**: No #REF!, #VALUE!, or #DIV/0! errors in calculated columns

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Skills Tested

- Nested IF statements for multi-condition logic
- MIN/MAX functions for comparison
- Conditional formatting rules
- Data quality assessment and handling
- Cell referencing across columns
- Formula composition and debugging
- Budget constraint analysis

## Example Calculations

**Book 1 - Chemistry Textbook:**
- Amazon base price: $120
- Note: "+$5 ship, no access"
- Course needs access code: Yes
- **True Cost** = $120 + $5 (shipping) + $85 (access code) = **$210**

**Book 2 - Biology Textbook:**
- Campus base price: $95
- Note: "shipping included, w/ access code"
- **True Cost** = $95 (no additions needed)

## Tips

- Read Notes column carefully to understand what's included
- Use ISNUMBER(SEARCH("text", cell)) to detect text in Notes
- Use nested IF statements: IF(condition1, value1, IF(condition2, value2, default))
- MIN function syntax: =MIN(range1, range2, range3)
- Conditional formatting: Format → Conditional Formatting → Condition
- Test formulas on first row, then copy down to all rows