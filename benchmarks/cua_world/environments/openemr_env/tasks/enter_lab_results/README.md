# Enter Lab Test Results (`enter_lab_results@1`)

## Overview

This task tests the agent's ability to enter laboratory test results into a patient's electronic health record. It validates clinical data entry skills, understanding of lab result workflows, and proper documentation of diagnostic values with their appropriate units and reference ranges.

## Rationale

**Why this task is valuable:**
- Tests multi-field form completion with specific numeric values
- Validates understanding of clinical laboratory workflows
- Requires navigation through multiple levels of patient chart
- Involves data entry accuracy critical for patient safety
- Exercises the Procedures module which is less commonly tested

**Real-world Context:** A medical assistant at a family medicine clinic receives faxed lab results from an external laboratory (Quest Diagnostics) for a patient with hypertension. The results from routine metabolic monitoring must be entered into the EHR so the physician can review them before the patient's follow-up appointment.

## Task Description

**Goal:** Enter Basic Metabolic Panel (BMP) lab results for patient Jayson Fadel into OpenEMR's procedure results system.

**Starting State:** OpenEMR is running with Firefox displaying the login page. Patient Jayson Fadel exists in the system (pid: 3) with documented hypertension.

**Clinical Context:**
Patients on antihypertensive medications (especially those containing diuretics like hydrochlorothiazide) require periodic monitoring of kidney function and electrolytes. Jayson Fadel is on amLODIPine/Hydrochlorothiazide/Olmesartan combination therapy and had blood drawn for routine monitoring.

**Lab Results to Enter:**

| Test | Result | Units | Reference Range |
|------|--------|-------|-----------------|
| Glucose | 108 | mg/dL | 70-100 |
| BUN (Blood Urea Nitrogen) | 22 | mg/dL | 7-20 |
| Creatinine | 1.2 | mg/dL | 0.7-1.3 |
| Sodium | 139 | mEq/L | 136-145 |
| Potassium | 4.5 | mEq/L | 3.5-5.0 |
| Chloride | 103 | mEq/L | 98-106 |
| CO2 (Bicarbonate) | 25 | mEq/L | 23-29 |

**Expected Actions:**
1. Log in to OpenEMR (username: admin, password: pass)
2. Search for patient "Jayson Fadel" using the patient search
3. Open the patient's chart
4. Navigate to the Procedures section (Clinical → Procedures/Results or similar)
5. Create a new procedure order OR access pending orders
6. Select or enter "Basic Metabolic Panel" or "BMP" as the procedure type
7. Enter the collection date as today's date
8. Enter each lab result value with appropriate units
9. Save/submit the results
10. Verify results appear in patient's chart

**Final State:** The lab results are saved in the patient's record and can be queried from the procedure_result table in the database.

## Verification Strategy

### Primary Verification: Database Query

Query the OpenEMR database to verify lab results were entered: