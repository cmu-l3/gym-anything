# Company Spinoff Restructure (`company_spinoff_restructure@1`)

## Overview
This task evaluates the agent's ability to execute a complex organizational restructuring in an HRMS. The agent must process a corporate spinoff scenario that requires cross-referencing employees, executing targeted deactivations, department creation, and personnel transfers.

## Rationale
**Why this task is valuable:**
- **Realistic Scenario:** M&A and corporate spinoffs are standard enterprise HR events requiring mass system updates.
- **Dependency Handling:** Employees must be transferred *before* mass deactivations occur to prevent accidental lockouts.
- **Precision:** Tests the agent's ability to selectively deactivate records without resorting to "deactivate all" shortcuts.
- **Multi-Module Navigation:** Requires interaction with both the `Departments` and `Employees` modules.

**Real-world Context:** A holding company has sold off its Marketing and Sales divisions. The HR administrator must clean up the system by deactivating the sold-off departments and their personnel, while retaining two key liaison employees by moving them to a newly created management department.

## Task Description

**Goal:** Process the corporate restructuring by creating a new department, transferring retained personnel, and deactivating the spinoff departments and their remaining employees.

**Starting State:** Sentrifugo is logged in and open in Firefox. A text file containing the exact restructuring instructions is located at `~/Desktop/spinoff_manifest.txt`.

**Expected Actions:**
1. Read `~/Desktop/spinoff_manifest.txt` to understand the requirements.
2. Navigate to `Organization > Departments` and create "Vendor Management".
3. Navigate to `HR > Employees` and update EMP011 and EMP019 to be in the "Vendor Management" department.
4. Deactivate all other employees currently in the "Sales" and "Marketing" departments.
5. Deactivate the "Sales" and "Marketing" departments.

**Final State:** The Vendor Management department exists. EMP011 and EMP019 are active and assigned to it. Other Sales/Marketing employees are inactive. Sales and Marketing departments are inactive.

## Verification Strategy

### Primary Verification: Programmatic Database State
The task is verified programmatically by querying the internal `sentrifugo-db` MySQL container to inspect the final state of `main_users` and `main_departments`.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| New Dept Created | 15 | "Vendor Management" exists and is active |
| Retained Emp 1 Safe | 15 | EMP011 is active and in Vendor Management |
| Retained Emp 2 Safe | 15 | EMP019 is active and in Vendor Management |
| Dept 1 Deactivated | 10 | "Marketing" department is inactive |
| Dept 2 Deactivated | 10 | "Sales" department is inactive |
| Spinoff Emps Deactivated | 20 | EMP005, EMP008, EMP014, EMP018 are inactive |
| Unrelated Emps Safe | 15 | EMP003 (Finance) remains active |
| **Total** | **100** | |

**Pass Threshold:** 70 points.
*Anti-Gaming Note:* Deactivating all users blindly will fail the "Unrelated Emps Safe" check and "Retained Emps Safe" check, capping the score at 40/100 (Fail).