# Generate Day Sheet Financial Report (`generate_day_sheet@1`)

## Overview

This task tests the agent's ability to navigate OpenEMR's billing and reporting system to generate a day sheet - a critical end-of-day financial reconciliation report that summarizes all patient transactions, payments, and adjustments for a specific date.

## Rationale

**Why this task is valuable:**
- Tests navigation through OpenEMR's financial/billing module
- Validates understanding of healthcare financial reporting workflows
- Requires parameter configuration (date selection, report options)
- Involves report generation and verification
- Essential skill for medical billing staff and practice managers

**Real-world Context:** At the end of each business day, a billing clerk at a family medicine clinic needs to generate a day sheet report to reconcile cash drawer totals, verify credit card batches, and ensure all patient payments are properly recorded before closing out.

## Task Description

**Goal:** Generate a day sheet (Daily Summary) financial report for today's date showing all transactions, payments, and charges processed.

**Starting State:** OpenEMR is open with the login page displayed in Firefox. The system has existing financial data from sample patients including encounters, charges, and payments.

**Expected Actions:**
1. Log in to OpenEMR using credentials: admin / pass
2. Navigate to the Reports menu
3. Select the "Day Sheet" or "Daily Summary" report under Financial reports
4. Configure the report parameters:
   - **Date**: Today's date (current system date)
   - **Provider**: All providers (or leave as default)
5. Generate/run the report
6. The report should display in the browser window showing transaction summaries

**Final State:** The day sheet report is displayed showing financial transaction data for the selected date, including columns for charges, payments, and adjustments.

## Initial State Setup

The setup script will:
1. Ensure OpenEMR is running and accessible
2. Firefox is open to the OpenEMR login page
3. Sample financial data exists in the database (from Synthea import)
4. Window is maximized and focused

## Verification Strategy

### Primary Verification: Database Activity Check

Query the OpenEMR audit log to verify:
- User accessed the reports module
- Day sheet report was generated
- Timestamps show activity during task window

### Secondary Verification: VLM Visual Check

The verifier examines trajectory screenshots (not just final screenshot) to confirm:
1. User navigated through Reports menu
2. Financial/Billing reports section was accessed
3. Day Sheet or Daily Summary report was selected
4. Report output is displayed showing financial columns
5. Date parameter matches today's date

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Successful Login | 15 | Agent logged into OpenEMR |
| Navigated to Reports | 20 | Found and opened Reports menu |
| Accessed Financial Reports | 20 | Accessed billing/financial reports section |
| Report Generated | 25 | Day sheet report displayed with data |
| VLM Trajectory Verification | 20 | Visual confirmation of workflow completion |
| **Total** | **100** | |

**Pass Threshold:** 60 points with report evidence (either from logs or VLM confirmation)

## Anti-Gaming Measures

1. **Timestamp Verification**: Task start time recorded; activity must occur after start
2. **Log Count Comparison**: Initial vs. final audit log entries must show new activity
3. **Trajectory Verification**: VLM examines multiple frames from workflow (not just final state)
4. **Duration Check**: Suspiciously fast completion is flagged

## Technical Notes

### OpenEMR Report Location

In OpenEMR, day sheet reports are typically found under:
- Reports > Financial > Day Sheet
- OR Reports > Clients > Collections > Day Sheet
- OR Fees > Reports > Day Sheet

The exact location may vary by OpenEMR version, but the agent should be able to navigate the menu structure to find financial reports.

### Expected Report Content

A day sheet report typically displays:
- Date range
- Provider name (if filtered)
- Total charges for the day
- Total payments received
- Total adjustments
- Net accounts receivable change
- Line item breakdowns (optional)

## Data Requirements

This task uses existing financial data from the Synthea-imported sample patients. The verification does not require specific amounts - it validates that:
1. The report generation workflow was completed
2. A financial report (not clinical report) was produced
3. Activity occurred during the task window

## Edge Cases

- If no transactions exist for today's date, a valid day sheet showing $0.00 totals is acceptable
- Both detailed and summary day sheet formats are acceptable
- Printing or exporting the report is optional (display is sufficient)

## Why This Task is Appropriate Difficulty

**Medium Complexity:**
- Requires 5-10 steps to complete
- Navigation through menu structure (reports vs clinical areas)
- No complex data entry required
- Clear success criteria (report displays)

**Not Trivial:**
- Agent must find the correct report among many options
- Financial reports are in a different area than clinical functions
- Must understand difference between clinical and billing reports

**Not Impossibly Hard:**
- No multi-step clinical workflows
- No data creation required (viewing/reporting only)
- Standard OpenEMR functionality