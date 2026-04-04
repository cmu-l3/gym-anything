# LibreOffice Calc Blood Pressure Log Analysis Task (`bp_log_analysis@1`)

## Overview

This task challenges an agent to analyze blood pressure readings collected over several weeks, identify concerning patterns, calculate averages by time of day, and flag readings that exceed medical thresholds. The agent must work with real-world messy health data that includes missing entries, readings at inconsistent times, and notes about circumstances affecting readings.

## Rationale

**Why this task is valuable:**
- **Health Data Management:** Tests ability to work with personal health metrics that people track for medical purposes
- **Time-Based Analysis:** Requires grouping and aggregating data by meaningful time periods (morning vs. evening)
- **Threshold Detection:** Applies real-world medical guidelines to flag concerning values
- **Real-World Messiness:** Handles incomplete data, inconsistent timing, and contextual notes
- **Practical Impact:** Represents actual spreadsheet work people do for doctor appointments
- **Formula Complexity:** Combines conditional logic (IF), averaging with criteria (AVERAGEIF), and statistical analysis
- **Health Literacy:** Introduces agent to understanding systolic/diastolic pressure and medical thresholds

**Skill Progression:** This task bridges basic formulas with real-world health data analysis, requiring conditional logic, time categorization, and multi-criteria calculations.

## Skills Required

### A. Interaction Skills
- **Data Entry:** Input calculated formulas in designated cells
- **Formula Construction:** Build complex formulas using multiple functions
- **Range Selection:** Reference cell ranges across different columns
- **Conditional Logic:** Use IF statements to categorize and flag data
- **Time Functions:** Work with time data to categorize readings
- **Statistical Functions:** Calculate averages with criteria
- **Cell Formatting:** Apply appropriate number formats and conditional formatting for visual alerts

### B. LibreOffice Calc Knowledge
- **AVERAGE Functions:** Use AVERAGE and AVERAGEIF for conditional averaging
- **IF Function:** Implement conditional logic for threshold detection
- **COUNTIF Function:** Count occurrences meeting specific criteria
- **Time Functions:** Work with HOUR or TIME functions to categorize readings
- **Cell References:** Use absolute and relative references appropriately
- **Conditional Formatting:** Apply formatting rules to highlight concerning values (optional)
- **Date/Time Handling:** Parse and categorize time-of-day data

### C. Task-Specific Skills
- **Medical Threshold Understanding:** Know that systolic ≥140 or diastolic ≥90 indicates hypertension
- **Time Categorization:** Distinguish morning readings (before noon) from evening readings
- **Data Quality Assessment:** Work with incomplete or missing data gracefully
- **Pattern Recognition:** Identify trends or concerning patterns in health data
- **Health Data Context:** Understand that BP varies by time of day, activity, stress

## Task Steps

### 1. Initial Assessment
- Examine the blood pressure log CSV file that opens automatically in LibreOffice Calc
- Note the structure: Date, Time, Systolic (mmHg), Diastolic (mmHg), Pulse (bpm), Notes
- Observe that some readings are missing or have incomplete data
- Identify morning readings (typically 6-11 AM) vs. evening readings (typically 6-10 PM)

### 2. Calculate Overall Averages
- In designated summary cells (H2-H4), create formulas to calculate:
  - H2: Average systolic pressure across all readings
  - H3: Average diastolic pressure across all readings
  - H4: Average pulse rate across all readings
- Use AVERAGE function with appropriate cell ranges (C2:C50, D2:D50, E2:E50)
- Ensure formulas handle empty cells gracefully

### 3. Calculate Morning vs. Evening Averages
- Create formulas to calculate average systolic and diastolic pressure separately for:
  - H6: Morning systolic (time before 12:00 PM)
  - H7: Morning diastolic
  - H9: Evening systolic (time after 6:00 PM / 18:00)
  - H10: Evening diastolic
- Use AVERAGEIF or AVERAGEIFS with time-based criteria
- Example: `=AVERAGEIF(B:B,"<12:00",C:C)` or similar approach

### 4. Identify Hypertensive Readings
- Create a new column G called "Status" that categorizes each reading:
  - "Normal" if systolic <120 AND diastolic <80
  - "Elevated" if systolic 120-129 AND diastolic <80
  - "Stage 1" if systolic 130-139 OR diastolic 80-89
  - "Stage 2" if systolic >=140 OR diastolic >=90
  - "Crisis" if systolic >180 OR diastolic >120
- Use nested IF statements: `=IF(C2>180,"Crisis",IF(C2>=140,"Stage 2",...))`
- Handle blank rows (where BP data is missing)

### 5. Count Concerning Readings
- Calculate the total number of readings in each category:
  - H12: Count "Normal" readings
  - H13: Count "Elevated" readings
  - H14: Count "Stage 1" readings
  - H15: Count "Stage 2" readings
  - H16: Count "Crisis" readings
- Use COUNTIF: `=COUNTIF(G:G,"Normal")`

### 6. (Optional) Flag High Readings with Conditional Formatting
- Apply conditional formatting to systolic column (C):
  - Yellow for values 130-139
  - Orange for values 140-179
  - Red for values ≥180
- Apply similar conditional formatting to diastolic column (D)

### 7. Review and Save
- Verify all formulas calculate correctly
- Ensure summary statistics are visible
- Save the file

### 8. Automatic Export
- The post-task hook will automatically export the result as "bp_analysis_complete.ods"

## Verification Strategy

### Verification Approach
The verifier uses **multi-criteria formula and value validation** combined with **medical threshold accuracy**:

### A. Formula Correctness Verification
- **Average Formulas:** Checks that AVERAGE functions are correctly applied to data ranges
- **Conditional Averages:** Validates that AVERAGEIF or similar correctly filter by time of day
- **IF Statement Logic:** Verifies that status categorization uses correct medical thresholds
- **Count Formulas:** Ensures COUNTIF correctly counts readings in each category

### B. Calculated Value Accuracy
- **Overall Averages:** Verifies calculated averages match expected values within tolerance (±2 mmHg)
- **Morning/Evening Split:** Validates that time-based averages are correctly calculated
- **Status Categorization:** Checks that readings are correctly classified according to medical guidelines
- **Count Accuracy:** Ensures counts of each status category are correct (±2 tolerance)

### C. Medical Threshold Application
- **Hypertension Detection:** Confirms that readings ≥140/90 are flagged appropriately
- **Normal Range:** Verifies readings <120/80 are marked as normal
- **Elevated Category:** Checks that borderline readings (120-129/<80) are correctly identified

### D. Formula Presence
- **No Hardcoding:** Verifies that calculations use formulas, not hardcoded values
- **Error-Free:** Ensures no #DIV/0!, #VALUE!, or other formula errors appear

### Verification Checklist
- ✅ **Overall Averages Calculated:** Systolic, diastolic, and pulse averages are present and accurate (±2 mmHg)
- ✅ **Time-Based Averages Calculated:** Morning and evening averages are correctly computed
- ✅ **Status Column Created:** Readings are correctly categorized by medical guidelines
- ✅ **Counts Accurate:** Number of readings in each status category is correct (±2)
- ✅ **Formulas Used:** Calculations use formulas, not hardcoded values (5+ formulas detected)
- ✅ **No Formula Errors:** All formulas evaluate successfully without errors
- ✅ **Medical Thresholds Correct:** Categorizations align with standard medical guidelines

### Scoring System
- **100%:** All 7 criteria met (perfect medical data analysis)
- **85-99%:** 6/7 criteria met (excellent analysis with minor issue)
- **70-84%:** 5/7 criteria met (good analysis, passing threshold)
- **50-69%:** 3-4/7 criteria met (basic calculations present but categorization incomplete)
- **0-49%:** <3 criteria met (insufficient analysis or major calculation errors)

**Pass Threshold:** 70% (requires at least 5 out of 7 criteria)

## Technical Implementation

### Files Structure