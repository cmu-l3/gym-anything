# Reading Challenge Progress Tracker Task

**Difficulty**: 🟡 Medium
**Estimated Steps**: 20
**Timeout**: 240 seconds (4 minutes)

## Objective

Transform a simple reading log into an analyzed progress tracker with calculated metrics, conditional formatting, and summary statistics. This task tests formula creation, date calculations, conditional logic, aggregation functions, and conditional formatting in a realistic personal productivity workflow.

## Starting State

- LibreOffice Calc opens with a pre-populated reading log containing 18 books
- Data columns: Date Finished, Book Title, Author, Genre, Pages, Rating
- Books span January through mid-May of the current year
- Goal: Track progress toward 52-book annual reading challenge (1 book/week)

## Data Structure

| Date Finished | Book Title | Author | Genre | Pages | Rating |
|--------------|------------|--------|-------|-------|--------|
| 2024-01-08   | The Midnight Library | Matt Haig | Fiction | 304 | 4.5 |
| 2024-01-15   | Atomic Habits | James Clear | Non-Fiction | 320 | 5.0 |
| ... (18 books total) | ... | ... | ... | ... | ... |

## Required Actions

### 1. Create Summary Statistics Section
In an empty area (e.g., rows 1-5), create:
- Current Week calculation (using TODAY() function)
- Books Expected by Now (should equal current week number)
- Books Actually Read (count of entries)
- Average Rating (AVERAGE function)
- Projected Annual Total (pace-based projection)

### 2. Add Calculated Column
Insert a new column (e.g., "Progress Status") that uses IF logic to show whether user is on track:
- Compare actual vs. expected books
- Display "ON TRACK" or "BEHIND" (or numeric difference)

### 3. Create Genre Analysis
Add a genre breakdown section using COUNTIF:
- Count books in each genre (Fiction, Non-Fiction, Sci-Fi, Mystery)
- At least 3 genre counts required

### 4. Apply Conditional Formatting
Apply color-based conditional formatting to progress indicators:
- Green for "ON TRACK" or positive values
- Red for "BEHIND" or negative values

### 5. Calculate Projections
Add formula to project end-of-year total based on current pace:
- Formula: (books_read / weeks_elapsed) * 52
- Should indicate if goal will be met

## Success Criteria

1. ✅ **Summary Statistics Present** - Current week, expected/actual books, average rating calculated
2. ✅ **Calculated Column Added** - New column with IF logic for progress status
3. ✅ **Genre Counts** - At least 3 COUNTIF formulas for genre analysis
4. ✅ **Conditional Formatting** - Applied to progress indicators
5. ✅ **Date Functions Used** - TODAY() or equivalent present
6. ✅ **Projection Formula** - End-of-year projection calculated
7. ✅ **Accurate Count** - Book count matches actual data (18)
8. ✅ **Valid Formulas** - All formulas syntactically correct

**Pass Threshold**: 70% (6 out of 8 criteria)

## Skills Tested

- Date functions (TODAY(), WEEKNUM())
- Conditional logic (IF statements)
- Statistical functions (AVERAGE, COUNTA, COUNTIF)
- Formula references (absolute vs. relative)
- Conditional formatting
- Progress tracking calculations
- Data aggregation by category

## Tips

- Use TODAY() to get current date
- WEEKNUM(TODAY()) gives current week of year
- COUNTA() counts non-empty cells
- COUNTIF(range, criteria) for genre counts
- IF(condition, true_value, false_value) for status
- Apply conditional formatting: Format → Conditional Formatting
- For projection: (actual/elapsed)*52

## Real-World Context

**Scenario**: You've been logging books casually but now want to know if you're on track for your 52-book annual goal. A friend asked "How's your reading challenge going?" and you couldn't quickly answer. Time to add analytics to your log!

**User Persona**: Casual reader, Goodreads user, participating in annual reading challenge

**Frustration**: Have data but no insights - need to transform raw log into actionable progress dashboard