# Oral History Archive Submission Validator Task

**Difficulty**: 🟡 Medium  
**Skills**: Date manipulation, logical formulas, conditional formatting, sorting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Help a volunteer coordinator at a local historical society prepare oral history interviews for submission to a state digital archive. The spreadsheet has inconsistent date formats, missing age information, and no clear way to identify which interviews meet strict archive submission requirements. The agent must clean dates, calculate ages, create validation formulas, and apply visual formatting to prioritize incomplete work.

## Task Description

The agent must:
1. **Standardize interview dates**: Create a new column with consistent YYYY-MM-DD format from mixed date entries
2. **Calculate ages**: Add a column computing interviewee age at time of interview
3. **Create validation formula**: Build an "Archive Ready" formula checking if ALL requirements are met:
   - Transcription Status = "Complete"
   - Release Form Signed = "Yes" or TRUE
   - Topic Tags is not empty
   - Interview Date is not empty
4. **Apply conditional formatting**: Visually distinguish complete ("YES") from incomplete ("NO") records
5. **Sort strategically**: Prioritize incomplete interviews (oldest first) to help volunteers focus on urgent preservation work

## Starting Data Structure

| Interviewee Name | Birth Year | Interview Date | Transcription Status | Release Form Signed | Topic Tags | Duration (min) |
|------------------|------------|----------------|---------------------|--------------------|-----------| --------------|
| Margaret Chen | 1934 | 03/15/2023 | Complete | Yes | WWII, Chinatown | 47 |
| Robert Williams | 1941 | 2023-05-22 | In Progress | Yes | Steel Mill, Union | 63 |
| Dorothy Martinez | 1938 | January 2023 | Complete | No | | 38 |
| James Peterson | 1929 | 2022-11-10 | Complete | Yes | Depression, Farming | 71 |
| Helen Kowalski | 1945 | 08/03/2023 | Not Started | | Railroad, Immigration | 0 |

**Note**: Interview dates are intentionally inconsistent (MM/DD/YYYY, YYYY-MM-DD, text like "January 2023")

## Expected Results

Three new columns should be added:
- **Interview Date (Standardized)**: All dates in YYYY-MM-DD format
- **Age at Interview**: Calculated as YEAR(Interview Date) - Birth Year
- **Ready for Archive?**: "YES" if all requirements met, "NO" otherwise

Conditional formatting should visually distinguish YES (green) from NO (yellow/orange).

Data should be sorted:
1. Primary: "Ready for Archive?" with "NO" first
2. Secondary: "Interview Date (Standardized)" ascending (oldest first)

## Verification Criteria

1. ✅ **Date Standardization**: New column exists with YYYY-MM-DD format dates
2. ✅ **Age Calculation**: New column with correct age formulas (reasonable values 18-110)
3. ✅ **Archive Formula**: Logical formula correctly identifies complete vs incomplete records
4. ✅ **Conditional Formatting**: Visual distinction applied to archive readiness
5. ✅ **Sort Priority**: Data sorted to show oldest incomplete interviews first
6. ✅ **Data Integrity**: All original data preserved, no formula errors

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Date format recognition and standardization
- Date function usage (YEAR, DATE, TODAY)
- Complex logical formulas (IF, AND, OR)
- Cell reference management (absolute vs relative)
- Conditional formatting rules
- Multi-level sorting
- Data quality assessment
- Formula auditing

## Real-World Context

This task mirrors authentic challenges in:
- Volunteer-managed community projects
- Archival metadata preparation
- Historical preservation efforts
- Grant application compliance tracking
- Certification renewal management

The urgency is real: elderly interviewees may pass away before their stories are preserved.

## Tips

- Text dates like "January 2023" need manual conversion (use 1st of month)
- Use DATE() or YEAR() functions for date manipulation
- AND() formula syntax: `=IF(AND(condition1, condition2, condition3), "YES", "NO")`
- Conditional formatting: Format → Conditional → Condition (cell value equals)
- Multi-level sort: Data → Sort → Add multiple sort keys
- Check formulas for #VALUE! errors (indicates date parsing issues)