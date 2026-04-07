# Contractor Audit and Isolation (`contractor_audit_and_isolation@1`)

## Overview
This task evaluates the agent's ability to perform a conditional compliance audit by cross-referencing external data (a CSV roster) with internal HRMS records. The agent must apply date-based logic to determine which contractors have expired and deactivate them, while creating a new organizational structure (a Department) to isolate the active contractors for IT security purposes.

## Rationale
**Why this task is valuable:**
- **Information Integration**: Requires the agent to parse a CSV file, extract dates, and apply logic based on the current system date (March 11, 2026) before taking action.
- **Cross-Module Navigation**: Tests the ability to navigate between Organization setup (creating a department) and Employee management (editing profiles).
- **Anti-Gaming by Design**: The agent is not told *which* specific employees to deactivate or move; it must execute the logic correctly to discover the targets. Blanket actions (deactivating everyone or moving everyone) will fail to reach the passing threshold.
- **Realistic Data Usage**: Uses realistic IT staffing vendor names and plausible contract overlap periods, mimicking a true compliance audit.

**Real-world Context:** A First-Line Supervisor of Office and Administrative Support Workers has received an IT Security directive. To improve data compartmentalization, all active external contractors must be grouped into a dedicated department. Concurrently, a routine audit of the contractor roster indicates several contractors have passed their contract end dates and must have their HRMS access immediately revoked.

## Task Description

**Goal:** Parse the contractor roster, deactivate any contractors whose contracts expired before today (March 11, 2026), and move all currently active contractors into a newly created "External Contractors" department.

**Starting State:** 
- Firefox is open and logged into Sentrifugo as the admin user.
- Eight contractor profiles currently exist in Sentrifugo, mixed into various internal departments (Engineering, Finance, etc.).
- A CSV file is located at `~/Desktop/contractor_roster.csv` containing the latest contract expiration dates.

**Expected Actions:**
1. Open and read the `~/Desktop/contractor_roster.csv` file. 
2. Compare the `ContractEndDate` of each contractor against today's date (**March 11, 2026**).
3. Navigate to Sentrifugo's Organization > Departments module.
4. Create a new department exactly named `External Contractors`.
5. Navigate to the Employee Management module.
6. For every contractor whose contract has **expired** (end date is in the past):
   - Edit their profile and deactivate their account (set status to inactive). Do not delete the record.
7. For every contractor whose contract is **still active** (end date is today or in the future):
   - Edit their profile and update their Department assignment to the new `External Contractors` department. Ensure they remain active.

**Final State:** 
The "External Contractors" department exists. The four expired contractors are marked inactive. The four active contractors are assigned to the "External Contractors" department and remain active.

## Verification Strategy

### Primary Verification: Database State Verification
The verifier runs direct SQL queries against the `sentrifugo-db` Docker container using `exec_in_env` to validate the final state of the database:
1. `main_departments`: Checks for the existence and active status of `External Contractors`.
2. `main_users`: Queries the `isactive` flag for the four specifically expired employee IDs (EMP031, EMP032, EMP034, EMP037).
3. `main_users JOIN main_departments`: Queries the `department_id` and `isactive` flag for the four active employee IDs (EMP033, EMP035, EMP036, EMP038).

### Secondary Verification: Artifact Inspection
The setup script records the initial database state. The verifier checks that no collateral damage occurred (e.g., standard internal employees were not accidentally deactivated or moved). 

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Department Created | 12 | "External Contractors" department exists and is active. |
| EMP031 Deactivated | 11 | Alex Vance (Expired 2026-02-15) is inactive. |
| EMP032 Deactivated | 11 | Priya Kapoor (Expired 2026-02-28) is inactive. |
| EMP034 Deactivated | 11 | Elena Rodriguez (Expired 2026-03-01) is inactive. |
| EMP037 Deactivated | 11 | James Wilson (Expired 2025-12-31) is inactive. |
| EMP033 Isolated | 11 | Marcus Johnson (Active) is active and in "External Contractors". |
| EMP035 Isolated | 11 | David Kim (Active) is active and in "External Contractors". |
| EMP036 Isolated | 11 | Sarah O'Connor (Active) is active and in "External Contractors". |
| EMP038 Isolated | 11 | Wei Chen (Active) is active and in "External Contractors". |
| **Total** | **100** | |

**Pass Threshold:** 78 points. 
*Note on Threshold:* The threshold requires the agent to correctly create the department and successfully process at least 6 of the 8 contractors. A blanket strategy of applying one action to all 8 contractors yields a maximum of 56 points, resulting in a firm failure.