# Guitar Practice Log Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, formula creation, conditional logic, summary statistics  
**Duration**: 300 seconds  
**Steps**: ~25

## Objective

Organize messy practice log data from handwritten notes into a structured spreadsheet, calculate practice time statistics, and identify priority areas using conditional logic. This task tests data cleaning, formula creation, and analytical thinking.

## Scenario

Nina is a guitar student who tracked her practice sessions over 2 weeks using sticky notes, phone memos, and notebook margins. Her instructor needs a clean spreadsheet showing:
- Standardized practice times (in minutes)
- Weekly summaries and totals
- Difficulty ratings for each session
- Priority areas (high difficulty but low practice time)

## Starting State

- A CSV file (`practice_notes_raw.csv`) contains Nina's messy practice data
- Time entries are inconsistent: "45 min", "1 hr", "about an hour", "1:15", "20"
- Some dates are missing
- Difficulty ratings (1-5) are partially incomplete

## Required Actions

1. **Import and Clean Data**
   - Open the CSV file in LibreOffice Calc
   - Standardize time entries to numeric minutes (e.g., "45 min" → 45, "1 hr" → 60, "1:15" → 75)
   - Fill in missing dates based on week context
   - Fill missing difficulty ratings with reasonable estimates

2. **Add Category Analysis**
   - Categorize activities as "Technique", "Song", or "Exercise"
   - Add a new column for categories (optional but helpful)

3. **Calculate Weekly Statistics**
   - Create summary section with:
     - Week 1 Total Time (Jan 8-14)
     - Week 2 Total Time (Jan 15-21)
     - Overall Total Time
     - Average Session Duration
     - Average Difficulty

4. **Identify Priority Areas**
   - Flag sessions where Difficulty ≥ 4 AND Time < 30 minutes as "HIGH PRIORITY"
   - Use formulas: `=IF(AND(difficulty>=4, time<30), "HIGH PRIORITY", "")`
   - Apply conditional formatting to highlight priorities

5. **Create Instructor Summary**
   - Identify most/least practiced techniques
   - Recommend focus areas based on data

## Success Criteria

1. ✅ **Data Cleaned**: Time values converted to numeric (no text like "min" or "hr")
2. ✅ **Calculations Accurate**: Weekly totals use formulas, values are reasonable
3. ✅ **Priorities Identified**: 2-4 HIGH PRIORITY items correctly flagged
4. ✅ **Summary Present**: Summary section with weekly totals and averages
5. ✅ **Conditional Formatting**: Cells highlighted based on criteria
6. ✅ **Instructor Insights**: Recommendations section present

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Sample Data Structure

### Before (Raw CSV):