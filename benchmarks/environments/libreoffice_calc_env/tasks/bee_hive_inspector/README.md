# Bee Hive Inspector Task

**Difficulty**: 🟡 Medium  
**Skills**: Nested formulas, conditional logic, data analysis, conditional formatting  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Organize and analyze messy beekeeping inspection data to calculate colony health scores and identify at-risk hives. This task tests data interpretation, multi-criteria decision logic, formula construction, and visual formatting—simulating a real-world workflow for hobbyist beekeepers transitioning from handwritten notes to digital tracking.

## Scenario

You are helping a beekeeper who has been recording hive inspection data over 4 weeks. The data is partially structured with inconsistent formatting (some values are text like "Strong", others are numbers like 40000). Your goal is to calculate health scores for Week 4 hives and visually highlight colonies needing intervention.

## Starting State

- LibreOffice Calc opens with `hive_inspections.csv` containing:
  - 4 weeks of inspection data (Week 1-4)
  - 5 hives (Hive-A through Hive-E)
  - Columns: Week, Hive ID, Inspection Date, Population Estimate, Frames of Brood, Honey Stores, Disease Signs, Queen Seen
- Data contains mixed formats: text ("Strong", "Moderate", "Weak", "None", "Full") and numbers (30000, 8, 7)

## Data Structure

| Week | Hive ID | Date | Population | Brood Frames | Honey Stores | Disease | Queen |
|------|---------|------|------------|--------------|--------------|---------|-------|
| 1 | Hive-A | 2024-04-01 | Strong | 9 | Full | None | Yes |
| 1 | Hive-B | 2024-04-01 | Moderate | 7 | Adequate | None | Yes |
| ... | ... | ... | ... | ... | ... | ... | ... |
| 4 | Hive-A | 2024-04-22 | Strong | 10 | Full | None | Yes |
| 4 | Hive-C | 2024-04-22 | Weak | 3 | Low | Confirmed | No |

## Health Scoring Criteria

You must implement a weighted scoring system (total: 0-23 points):

### Population Score (0-5 points)
- **"Strong"** or **>50,000 bees** = 5 points
- **"Moderate"** or **30,000-50,000 bees** = 3 points
- **"Weak"** or **<30,000 bees** = 1 point

### Frames of Brood Score (0-5 points)
- **8+ frames** = 5 points
- **5-7 frames** = 3 points
- **<5 frames** = 1 point

### Honey Stores Score (0-5 points)
- **"Full"** or **>8 frames** = 5 points
- **"Adequate"** or **4-8 frames** = 3 points
- **"Low"** or **<4 frames** = 1 point

### Disease Signs Score (0-5 points)
- **"None"** (or "None seen") = 5 points
- **"Possible"** (or "Suspected") = 2 points
- **"Confirmed"** = 0 points (critical issue)

### Queen Present Bonus (0-3 points)
- **"Yes"** = 3 points
- **"No"** = 0 points (serious concern)

## Required Actions

1. **Navigate to Week 4 data** (should be rows 17-21, with 5 hives)
2. **Add "Health Score" column header** in cell I1 (if not present)
3. **Create health score formulas** in column I for each Week 4 hive (I17:I21)
   - Use nested IF statements to evaluate each criterion
   - Handle both text values ("Strong") and numeric values (40000)
   - Sum all component scores
4. **Apply conditional formatting** to Health Score column (I17:I21):
   - **Red/Orange**: Scores <12 (URGENT - immediate attention needed)
   - **Yellow**: Scores 12-17 (MONITOR - watch closely)
   - **Green**: Scores 18+ (HEALTHY - continue regular inspections)
5. **Save the file** as `bee_colony_health_analysis.ods`

## Example Formula Structure
