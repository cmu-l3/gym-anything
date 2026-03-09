# Hospital Staffing Overtime Audit

**Environment**: microsoft_excel_2010_env
**Difficulty**: Very Hard
**Occupation**: Medical and Health Services Manager (SOC 11-9111)
**Industry**: Healthcare / Hospital Administration

## Task Overview

The agent receives a hospital staffing workbook (`hospital_staffing.xlsx`) containing 600 rows of timesheet data across four departments (ICU, Emergency, Surgery, Oncology/Pediatrics) for 30 employees over 20 working days. Two summary sheets (`Employee_Overtime_Summary` and `Department_Cost_Summary`) are pre-populated with employee IDs and department headers but all calculation columns are blank. The agent must implement payroll formulas to compute overtime hours, overtime pay, and flag employees requiring HR review, then roll up costs by department.

## Domain Context

Under US FLSA (Fair Labor Standards Act) standards for non-exempt hospital employees, overtime is typically defined as hours worked beyond 40 hours in a given pay period. Healthcare organizations track overtime carefully because overtime premiums (1.5× regular rate) significantly impact labor budgets. Department cost rollups are used in monthly operating reports reviewed by hospital CFOs and department directors.

## Data Sources

**Hourly Wage Rates** (Timesheets sheet, Hourly_Rate column, $24–$62/hr):
- Source: US Bureau of Labor Statistics, Occupational Employment and Wage Statistics (OEWS) Survey, May 2023
- URL: https://www.bls.gov/oes/current/oes_nat.htm
- BLS OEWS May 2023 median hourly wages for hospital occupations:
  - Registered Nurses (SOC 29-1141): median $40.92/hr, mean $44.80/hr; ICU/critical care premium ~$48–$55/hr
  - Licensed Practical Nurses (SOC 29-2061): median $25.25/hr, mean $25.31/hr
  - Nursing Assistants (SOC 31-1131): median $17.95/hr, mean $18.81/hr
  - Medical Assistants (SOC 31-9092): median $18.67/hr, mean $19.69/hr
  - Emergency Medical Technicians (SOC 29-2042): median $21.77/hr, mean $24.24/hr
  - Surgeons (SOC 29-1067): median wages >$100/hr (capped at $62/hr in task for non-physician surgical RNs and surgical techs)
- Employee hourly rates in task ($24–$62/hr) represent the distribution from nursing assistants through experienced ICU/OR nurses, consistent with these published BLS benchmarks

**Shift Hours** (Hours_Worked column, 6–11 hours/day):
- Standard US hospital shift patterns: 8-hour (day/evening/night shifts), 12-hour shifts (common in ICU/ER), and occasional 10-hour shifts
- Reference: American Nurses Association (ANA) Safe Staffing factsheet; Joint Commission staffing standards
- Note: 12-hour shifts are standard in ICU, ER, and OR departments; 8-hour shifts in Oncology and Pediatrics outpatient areas

**Overtime Threshold** ($40 hours/pay period):
- Source: US Fair Labor Standards Act (FLSA), 29 U.S.C. § 207
- Standard overtime threshold: 40 hours/workweek; this task uses a 20-day (4-week) period so the monthly threshold is 160 regular hours, with OT flagged at >80 hours overtime (>200 total hours)
- FLSA reference: https://www.dol.gov/agencies/whd/flsa

## Data

**Timesheets sheet** (600 rows, pre-filled):

| Column | Description |
|--------|-------------|
| Employee_ID | e.g., IC01–IC06 (ICU), ER01–ER04 (Emergency), Su01–Su06 (Surgery), On01–On04 (Oncology), Pe01–Pe06 (Pediatrics) |
| Department | ICU, Emergency, Surgery, Oncology, Pediatrics |
| Date | 20 working days |
| Hours_Worked | Daily hours (varies 6–11 hours) |
| Hourly_Rate | Employee-specific rate ($24–$62/hr) |

## Required Analysis

### Employee_Overtime_Summary sheet (agent fills in)

For each of 30 employees:
- **Total Hours**: `SUMIF` from Timesheets by Employee_ID
- **OT Hours** (hours above 40h threshold): `MAX(0, Total Hours - 40)`
- **Regular Hours**: `MIN(Total Hours, 40)`
- **OT Pay**: `OT Hours × Hourly Rate × 1.5`
- **Regular Pay**: `Regular Hours × Hourly Rate`
- **Total Pay**: `Regular Pay + OT Pay`
- **OT Flag**: "OT_REVIEW" if OT Hours > 40 (i.e., more than 80 total hours), else blank

Expected OT_REVIEW employees (OT Hours > 40): 7 employees
Expected total OT hours across all employees: ~776 hours
Expected total OT pay: ~$53,667

### Department_Cost_Summary sheet (agent fills in)

For each department:
- **Total Regular Pay**: Sum from Employee_Overtime_Summary
- **Total OT Pay**: Sum from Employee_Overtime_Summary
- **Total Labor Cost**: Regular + OT
- **OT %**: OT Pay / Total Labor Cost × 100

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| OT Hours column populated for ≥20 employees | 20 | Non-zero values present |
| Total OT hours in TOTALS row in [650, 900] | 20 | Correct SUMIF + MAX logic |
| Total OT Pay in [47,000, 62,000] | 20 | Correct 1.5× premium applied |
| At least 5 OT_REVIEW flags present | 20 | Correct 40h OT threshold |
| ICU department total labor cost in [48,000, 66,000] | 20 | Correct departmental rollup |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank in starter file)

## Why This Is Hard

- Requires SUMIF with Employee_ID lookup across 600-row Timesheets sheet
- OT calculation requires MAX(0, total - threshold) — cannot just sum hours
- OT pay requires combining OT hours × employee-specific rate × 1.5 premium
- Department rollup requires SUMIF aggregation by department from the summary sheet
- 30 employees × 6 formula columns = 180 cells of formula work
- Must correctly distinguish regular vs OT pay calculation

## Verification Strategy

1. **is_new check**: Export script records file modification time; verifier gates on is_new
2. **Independent xlsx re-analysis**: Verifier copies xlsx and parses with openpyxl `data_only=True`
3. **Range validation**: OT hours, OT pay, ICU cost all checked against plausible ranges
4. **Flag count**: OT_REVIEW string count checked in flag column
5. **TOTALS row**: Checks for aggregated row at bottom of Employee_Overtime_Summary
