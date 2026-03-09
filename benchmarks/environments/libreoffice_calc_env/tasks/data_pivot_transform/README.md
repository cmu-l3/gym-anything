# Data Restructuring Task (Wide to Long Format)

**Difficulty**: 🟡 Medium  
**Skills**: Data structure understanding, cell references, systematic data manipulation  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Transform quarterly sales data from "wide" format (quarters as columns) to "long" format (stacked rows with Quarter column). This represents a common data preparation workflow required for charting, pivot tables, and data analysis.

## Scenario

You're preparing a quarterly sales report for your small business. The bookkeeping software exported sales data with quarters as separate columns (Q1, Q2, Q3, Q4), but to create a line chart showing trends, you need each row to represent one product-quarter combination. Your colleague is waiting for this restructured data to start the presentation.

## Starting Data Structure (Wide Format)

| Category         | Q1    | Q2    | Q3    | Q4    |
|------------------|-------|-------|-------|-------|
| Electronics      | 45000 | 52000 | 48000 | 61000 |
| Home & Garden    | 23000 | 28000 | 31000 | 26000 |
| Clothing         | 18000 | 15000 | 22000 | 29000 |
| Sports Equipment | 12000 | 14000 | 19000 | 16000 |
| Books            | 8000  | 7500  | 8200  | 11000 |

**Location**: Columns A-E, starting at row 1

## Target Data Structure (Long Format)

| Category         | Quarter | Sales |
|------------------|---------|-------|
| Electronics      | Q1      | 45000 |
| Electronics      | Q2      | 52000 |
| Electronics      | Q3      | 48000 |
| Electronics      | Q4      | 61000 |
| Home & Garden    | Q1      | 23000 |
| ...              | ...     | ...   |

**Expected location**: Any clear area (e.g., columns G-I, or a new sheet)

## Required Actions

1. **Examine source data** (columns A-E)
   - Note: 5 product categories, 4 quarters per category
   - Calculate: Need 5 × 4 = 20 data rows in output

2. **Create destination structure**
   - Add three column headers: "Category", "Quarter", "Sales"
   - Place in columns G-I (or another clear area)

3. **Transform data systematically**
   - For each category, create 4 rows (one per quarter)
   - Fill: Category name, Quarter ID (Q1/Q2/Q3/Q4), Sales value
   - Use cell references (e.g., `=$A$2`) to maintain accuracy
   - Continue until all 20 data rows are complete

4. **Verify completeness**
   - Check row count: Should have 20 data rows + 1 header row
   - Each category should appear exactly 4 times
   - All quarters (Q1-Q4) should appear once per category

5. **Save the file** (Ctrl+S)

## Verification Criteria

1. ✅ **Correct Structure**: 3-column layout (Category, Quarter, Sales)
2. ✅ **Correct Row Count**: 20 data rows (5 categories × 4 quarters)
3. ✅ **Complete Coverage**: Each category appears exactly 4 times
4. ✅ **Quarter Coverage**: Q1, Q2, Q3, Q4 present for each category
5. ✅ **Value Accuracy**: All sales values match source data (±0.01 tolerance)
6. ✅ **No Empty Cells**: All cells in restructured area populated

**Pass Threshold**: 75% (requires solid transformation with minor acceptable errors)

## Skills Tested

- Data structure comprehension (wide vs. long format)
- Systematic data entry and replication
- Cell reference usage (relative/absolute)
- Pattern recognition and mapping
- Data integrity maintenance
- Efficient copy-paste strategies

## Tips

- **Systematic approach**: Process one category at a time, or one quarter at a time
- **Use formulas**: Reference original cells (e.g., `=$A$2`) instead of retyping
- **Fill down**: Type first few rows, then use Ctrl+D to fill down patterns
- **Double-check**: Verify each category has exactly 4 rows before moving on
- **Quarter labels**: Use consistent format (all "Q1", "Q2", etc.)

## Common Approaches

### Option A: Manual but Systematic
- Type category name, quarter, and reference sales value
- Repeat for each category-quarter combination
- Use absolute references for category ($A$2)

### Option B: Formula-based
- Create formulas using INDEX or OFFSET functions
- Replicate down to generate all rows

### Option C: Copy-Paste Pattern
- Create structure for first category (4 rows)
- Modify and replicate for remaining categories

All approaches are valid if the final result is correct!