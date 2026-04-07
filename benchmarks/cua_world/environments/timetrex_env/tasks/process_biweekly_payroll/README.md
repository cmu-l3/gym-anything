# Process Bi-Weekly Payroll Run (`process_biweekly_payroll@1`)

## Overview
This task tests the agent's ability to execute a complete payroll run in TimeTrex. The agent must navigate the Payroll module, identify an open pay period, and trigger the payroll processing engine to generate employee pay stubs while handling any potential exception warnings.

## Rationale
**Why this task is valuable:**
- Tests navigation to the core financial execution module (Payroll -> Pay Periods)
- Requires identifying the correct target from a list (an Open, Bi-Weekly pay period)
- Tests interaction with a multi-step processing wizard and warning dialogs
- Real-world relevance: Processing payroll is the primary terminal action of the entire TimeTrex system; all time tracking, policies, and scheduling ultimately lead to this critical workflow.

**Real-world Context:** 
The current bi-weekly pay period has just concluded. All department supervisors have signed off on their employees' timesheets. As a Payroll and Timekeeping Clerk (SOC 43-3051), your final critical task for the day is to process the payroll run for this period. This action triggers the system to calculate taxes, apply deductions, compute overtime, and generate the final pay stubs for tomorrow's direct deposit transmission.

## Task Description

**Goal:** Process the payroll for the oldest "Open" Bi-Weekly pay period in TimeTrex so that employee pay stubs are generated.

**Starting State:** 
Firefox is open and logged into TimeTrex as `demoadmin1` (password: `demo`). The system contains pre-generated demo data with active employees, recorded time punches, and several pay periods in an "Open" status.

**Expected Actions:**
1. Navigate to the **Payroll** menu, then select **Pay Periods**.
2. Locate a pay period belonging to the **Bi-Weekly** schedule that currently has a status of **Open**.
3. Select this pay period from the list.
4. Click the **Process** button (typically found in the top toolbar or action menu).
5. If the system warns you about existing timesheet exceptions (e.g., "Exceptions exist for this pay period"), choose the option to **Ignore Exceptions and Process** (or the equivalent option to force processing).
6. Wait for the payroll processing engine to complete its calculations (this may take a few moments).
7. Confirm that the pay period status changes (e.g., to "Processed" or "Closed") and that you can view the newly generated pay stubs.

**Final State:** 
The selected Bi-Weekly pay period has been processed, its status is no longer "Open", and new records exist in the system's pay stub database for that period.

## Verification Strategy

### Primary Verification: Database Record Count Check (PostgreSQL)
The primary verification checks if the payroll processing engine was successfully triggered by comparing the number of records in the `pay_stub` table before and after the task. If payroll was processed, this count will increase significantly as a pay stub is generated for each active employee.

### Secondary Verification: Pay Period Schedule Verification
The evaluation script queries the database to ensure that the newly processed pay period specifically belonged to a "Bi-Weekly" schedule, as requested in the instructions, and that its status was updated during the task's timeframe.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Payroll Engine Executed | 50 | The total count of `pay_stub` records in the database increased after the task started. |
| Correct Schedule Type | 50 | A "Bi-Weekly" pay period had its status updated to "Processed" during the task session. |
| **Total** | **100** | |

Pass Threshold: 100 points. Both the execution of the engine and the selection of the correct schedule type are required for a perfect score.