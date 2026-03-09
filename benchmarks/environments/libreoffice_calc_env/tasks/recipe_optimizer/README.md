# Recipe Experiment Optimizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, text normalization, formula creation, multi-criteria analysis  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~50

## Objective

Clean messy recipe experiment data, normalize ratings from different scales, create weighted composite scores, and identify the optimal chocolate chip cookie ingredient combination. This task tests data cleaning, text standardization, formula creation with conditional logic, and analytical reasoning skills.

## Task Description

A home cook has recorded 20 chocolate chip cookie baking experiments using different ingredient combinations (butter types, sugar types, chocolate types). The data was recorded inconsistently with:
- Inconsistent capitalization and spacing in ingredient names
- Mixed rating scales (some 1-5, some 1-10)
- Multiple quality factors (taste, texture, cost, ease)

The agent must:
1. **Clean the data**: Standardize ingredient names (capitalization, spacing)
2. **Normalize ratings**: Convert all ratings to a consistent 0-10 scale
3. **Create composite score**: Build weighted formula combining taste (40%), texture (30%), ease (20%), and cost (10%, inverted)
4. **Identify optimal combinations**: Sort or rank experiments by composite score
5. **Flag invalid data**: Mark experiments with missing data or poor scores
6. **Analyze by category**: Calculate average scores by ingredient type
7. **Save the analyzed spreadsheet**

## Expected Results

The final spreadsheet should contain:
- **Cleaned columns**: Standardized ingredient names (e.g., "Butter_Clean", "Sugar_Clean", "Chocolate_Clean")
- **Normalized columns**: All ratings on 0-10 scale (e.g., "Taste_Norm", "Texture_Norm", "Ease_Norm")
- **Composite_Score column**: Weighted average formula
- **Valid column**: TRUE/FALSE flags for data quality
- **Sorted data** or **top 3 identified**: Highest scoring experiments clearly marked
- **Category averages**: Summary statistics by ingredient type

## Verification Criteria

1. ✅ **Data Cleaning (20%)**: Ingredient names standardized (consistent capitalization, no duplicates like "butter" and "Butter")
2. ✅ **Normalization (15%)**: All ratings converted to 0-10 scale
3. ✅ **Composite Score (25%)**: Weighted formula correctly applied with appropriate weights
4. ✅ **Ranking (15%)**: Top 3 experiments correctly identified by score
5. ✅ **Validity Flags (10%)**: Experiments with missing/poor data flagged
6. ✅ **Category Analysis (15%)**: Average scores calculated by ingredient type

**Pass Threshold**: 70% (requires at least 4-5 criteria with good execution)

## Skills Tested

### Data Cleaning
- Text case normalization (UPPER, LOWER, PROPER functions)
- Whitespace removal (TRIM function)
- Duplicate detection and standardization
- Creating cleaned data columns

### Formula Creation
- Conditional formulas (IF statements)
- Scale conversion formulas
- Weighted average calculations
- Statistical functions (AVERAGE, COUNT)

### Analysis
- Multi-criteria decision making
- Data sorting and ranking
- Category grouping and aggregation
- Quality validation

### Spreadsheet Operations
- Creating new columns
- Applying formulas to ranges
- Sorting data
- Cell formatting

## Starting Data Issues

The `cookie_experiments.csv` contains intentional inconsistencies:
- **Capitalization variations**: "butter", "Butter", "margarine", "Margarine "
- **Trailing spaces**: "butter " vs "butter"
- **Mixed rating scales**: Taste ratings include both 1-5 (need doubling) and 1-10 scales
- **Different cost ranges**: $2-$8 (need normalization)
- **Inconsistent ease ratings**: Mixed 1-3 and 1-5 scales

## Tips for Agents

- Use TRIM() to remove extra spaces
- Use PROPER() or LOWER() for consistent capitalization
- Create helper columns for cleaned data
- Use IF() to detect and convert different rating scales
- Composite score formula example: `=(Taste*0.4 + Texture*0.3 + Ease*0.2 + (10-Cost)*0.1)`
- Sort by composite score descending to find top experiments
- Use COUNTIF() or AVERAGEIF() for category analysis