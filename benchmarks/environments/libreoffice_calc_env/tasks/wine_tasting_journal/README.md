# LibreOffice Calc Wine Tasting Journal Task (`wine_tasting_journal@1`)

## Overview

This task challenges an agent to organize wine tasting notes from a tasting event into a structured spreadsheet format, calculate summary statistics, and identify recommended wines based on specific criteria. The agent must enter both qualitative (flavor profiles, varietals) and quantitative (ratings, prices) data, apply formulas to compute averages, use conditional logic to determine purchase recommendations, and apply conditional formatting to visually highlight the best value wines. This represents real-world personal data management and decision support workflows.

## Rationale

**Why this task is valuable:**
- **Mixed Data Types:** Tests handling of both text (flavor descriptions) and numeric (ratings, prices) data simultaneously
- **Real-world Decision Support:** Represents practical use of spreadsheets for personal hobby tracking and purchasing decisions
- **Conditional Logic Application:** Requires understanding of IF/AND formulas for multi-criteria evaluation
- **Data Quality Skills:** Tests careful data entry with attention to detail (matching proper format for ratings, currency)
- **Visual Communication:** Uses conditional formatting to make insights immediately visible
- **Practical Workflow:** Mirrors common personal database scenarios (recipe collections, book logs, product comparisons)

**Skill Progression:** This task combines fundamental spreadsheet skills (data entry, basic formulas) with intermediate logic (conditional formulas) and visualization (conditional formatting), making it appropriate for building well-rounded spreadsheet competency.

## Skills Required

### A. Interaction Skills
- **Precise Data Entry:** Type text, numbers, and currency values accurately in correct cells
- **Cell Navigation:** Move between cells efficiently using Tab, Enter, or arrow keys
- **Formula Creation:** Enter formulas using function syntax and cell references
- **Range Selection:** Select cell ranges for applying formatting rules
- **Format Menu Navigation:** Access Format menu for conditional formatting options
- **Multi-criteria Setup:** Configure conditional formatting with specific thresholds

### B. LibreOffice Calc Knowledge
- **Cell Formatting:** Understand currency format ($), decimal places, and text alignment
- **Function Syntax:** Know proper syntax for AVERAGE, IF, AND functions
- **Conditional Formatting System:** Navigate Format → Conditional → Condition dialog
- **Cell References:** Use relative references (A2, B2) vs. range references (B2:B7)
- **Formula Evaluation:** Understand how spreadsheet calculates and displays formula results
- **Format Inheritance:** Know how to apply formatting across multiple cells

### C. Task-Specific Skills
- **Structured Data Entry:** Organize unstructured notes into tabular format
- **Statistical Calculation:** Compute meaningful summary statistics (averages)
- **Multi-criteria Logic:** Evaluate wines based on combined conditions (rating AND price)
- **Value Assessment:** Understand "good value" as meeting quality threshold at reasonable price
- **Visual Design:** Apply highlighting that enhances readability and insight extraction
- **Data Validation:** Ensure entered data matches expected types and ranges

## Task Steps

### 1. Initial Setup and Examination
- Open the provided `wine_journal.ods` file that appears in the Documents folder
- Examine the existing structure: Column headers (Wine Name, Varietal, Rating, Price, Flavor Notes, Recommend?)
- Note that the spreadsheet already has the proper structure but needs data from the tasting event

### 2. Data Entry - Wine Details (Rows 2-7)
Enter the following 6 wines with their details:

**Wine 1 (Row 2):**
- Wine Name: Château Margaux Reserve
- Varietal: Cabernet Sauvignon
- Rating: 4.5
- Price: $22.00
- Flavor Notes: Rich dark fruits, oak, smooth tannins

**Wine 2 (Row 3):**
- Wine Name: Sunrise Valley Chardonnay
- Varietal: Chardonnay
- Rating: 3.5
- Price: $18.00
- Flavor Notes: Crisp apple, light citrus, buttery finish

**Wine 3 (Row 4):**
- Wine Name: Monte Rosso Pinot
- Varietal: Pinot Noir
- Rating: 4.2
- Price: $28.00
- Flavor Notes: Cherry, earthy, silky texture

**Wine 4 (Row 5):**
- Wine Name: Desert Bloom Rosé
- Varietal: Rosé
- Rating: 3.8
- Price: $15.00
- Flavor Notes: Strawberry, refreshing, dry

**Wine 5 (Row 6):**
- Wine Name: Vintage Creek Merlot
- Varietal: Merlot
- Rating: 4.3
- Price: $24.00
- Flavor Notes: Plum, chocolate, velvety

**Wine 6 (Row 7):**
- Wine Name: Hillside Sauvignon Blanc
- Varietal: Sauvignon Blanc
- Rating: 3.2
- Price: $16.00
- Flavor Notes: Grassy, tart, mineral

### 3. Calculate Average Rating (Cell C9)
- Navigate to cell C9 (row 9 has label "Average Rating:" in column B)
- Enter formula: `=AVERAGE(C2:C7)`
- Verify the calculated average appears correctly (~3.92)

### 4. Calculate Average Price (Cell D9)
- Navigate to cell D9 (row 10 has label "Average Price:" in column B)
- Enter formula: `=AVERAGE(D2:D7)`
- Ensure currency formatting is maintained (~$20.50)

### 5. Create Recommendation Formula (Column F)
For each wine (F2:F7), determine if it should be recommended based on:
- Rating must be ≥ 4.0 (out of 5.0)
- Price must be ≤ $25.00

- In cell F2, enter: `=IF(AND(C2>=4.0, D2<=25), "YES", "NO")`
- Copy this formula down to cells F3 through F7
- Verify that only wines meeting BOTH criteria show "YES"

### 6. Apply Conditional Formatting to Highlight Best Values
Highlight wines that meet the recommendation criteria:
- Select the range A2:F7 (all data rows)
- Navigate to Format → Conditional Formatting → Condition
- Set condition: Formula is `$F2="YES"`
- Choose a background color (light green or light yellow) to highlight recommended rows
- Apply the formatting

### 7. Verify Results
Expected recommendations:
- Château Margaux Reserve: YES (4.5 rating, $22)
- Monte Rosso Pinot: NO (4.2 rating, but $28 > $25)
- Vintage Creek Merlot: YES (4.3 rating, $24)

### 8. Save File
- Save the completed spreadsheet (Ctrl+S or File → Save)
- The file should be saved as `wine_journal.ods`

## Verification Strategy

### Verification Approach
The verifier uses **comprehensive multi-criteria spreadsheet analysis** combining:

### A. Data Integrity Verification
- **Cell Value Checking:** Validates that all 6 wines have been entered with correct names, varietals, ratings, and prices
- **Data Type Validation:** Ensures ratings are numeric floats (3.0-5.0 range), prices are numeric with proper values
- **Text Accuracy:** Checks that wine names and varietals match the provided tasting notes
- **Completeness:** Confirms all required cells contain data (no missing entries)

### B. Formula Verification
- **Average Rating Formula:** Checks cell C9 contains `=AVERAGE(C2:C7)` or equivalent
- **Average Price Formula:** Checks cell D9 contains `=AVERAGE(D2:D7)` or equivalent
- **Formula Results:** Validates computed averages are within expected ranges
  - Expected average rating: ~3.92 (±0.15 tolerance)
  - Expected average price: ~$20.50 (±$1.50 tolerance)

### C. Recommendation Logic Verification
- **Formula Structure:** Validates cells F2:F7 contain IF/AND formulas with correct conditions
- **Logic Correctness:** Checks formula evaluates: `rating >= 4.0 AND price <= 25`
- **Result Accuracy:** Verifies recommendation results match expected outcomes

### D. Conditional Formatting Verification
- **Format Presence:** Checks that conditional formatting rules exist in the spreadsheet
- **Rule Logic:** Validates formatting rule targets cells with "YES" recommendations
- **Visual Highlighting:** Confirms that recommended wines have distinct background formatting

### Verification Checklist
- ✅ **All Wine Data Entered:** 6 wines with complete information
- ✅ **Ratings Accurate:** All 6 ratings match expected values
- ✅ **Prices Accurate:** All 6 prices match expected values
- ✅ **Average Rating Formula:** Cell C9 contains AVERAGE formula
- ✅ **Average Price Formula:** Cell D9 contains AVERAGE formula
- ✅ **Recommendation Formulas:** All 6 cells (F2:F7) contain IF/AND formulas
- ✅ **Recommendation Results:** Recommendations match expected YES/NO values
- ✅ **Conditional Formatting Applied:** Recommended wines are visually highlighted

### Scoring System
- **100%:** All 8 criteria met perfectly
- **87.5%:** 7/8 criteria met (excellent)
- **75%:** 6/8 criteria met (good - passing threshold)
- **62.5%:** 5/8 criteria met (adequate)
- **50%:** 4/8 criteria met (partial)
- **0-49%:** <4 criteria met (insufficient)

**Pass Threshold:** 75% (requires at least 6 out of 8 criteria)

## Technical Implementation

### Files Structure