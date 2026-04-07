# Corporate Divestiture Data Segregation (`corporate_divestiture_segregation@1`)

## Overview
This task tests the agent's ability to execute a mass employee data update in response to a corporate divestiture. The agent must configure new master data categories (a job title and an employment status) and then systematically apply those changes—along with domain-specific email updates—to a targeted list of employees separating from the parent company.

## Rationale
**Why this task is valuable:**
- **Master Data Sequencing:** Tests the agent's understanding that system-level configurations (job titles, employment statuses) must be created before they can be assigned to user profiles.
- **Iterative Accuracy:** Evaluates the agent's ability to maintain precision across a repetitive loop (updating 6 different employee records across multiple tabs).
- **String Manipulation:** Requires the agent to read existing data (`first.last@company.local`), perform a string replacement for the domain, and input the new value without corrupting the prefix.
- **Real-world relevance:** Divestitures, spin-offs, and mergers are common corporate events that require HR to rapidly isolate or harmonize large batches of employee records before automated IT migrations occur.

**Real-world Context:** A First-Line HR Supervisor is coordinating the spin-off of the company's Quality Assurance and Customer Support teams into a standalone private equity-backed entity called "QA-Serve". Before the IT department can migrate these users to the new active directory, HR must isolate their records in the Sentrifugo HRMS by updating their employment status, job titles, and email domains.

## Task Description

**Goal:** Create a specific Job Title and Employment Status for divested employees, then update 6 targeted employee records to reflect their transition to the new QA-Serve entity.

**Starting State:** 
- Firefox is open and logged into Sentrifugo HRMS as an administrator.
- The default employee database is populated.
- A confidential divestiture memo is located at `~/Desktop/divestiture_memo.txt`.

**Expected Actions:**
1. Open and read the `divestiture_memo.txt` on the Desktop.
2. Navigate to the relevant HRMS configuration menus to create a new Job Title: "Divestiture Transition Staff".
3. Navigate to the master data configuration to create a new Employment Status: "Divested Entity".
4. Locate the 6 employees specified in the memo (EMP008, EMP010, EMP012, EMP015, EMP018, EMP020).
5. For **each** of the 6 employees, edit their profile to:
   - Change their Job Title to "Divestiture Transition Staff".
   - Change their Employment Status to "Divested Entity".
   - Update their email address domain to `@qaserve.com` while strictly preserving their existing `first.last` prefix (e.g., if their email is `amanda.white@sentrifugo.local`, it must become `amanda.white@qaserve.com`).

**Final State:** 
- The new Job Title and Employment Status exist and are Active.
- All 6 target employees have the new job title, new employment status, and an `@qaserve.com` email address.
- No other employees in the system have been modified.

## Verification Strategy

### Primary Verification: Database State Verification (Programmatic)
The verifier will execute direct MySQL queries against the `sentrifugo-db` Docker container to validate the exact system state:
1. **Master Data Check:** Queries `main_jobtitles` and `main_employmentstatus` to verify the creation and active status of the required text strings.
2. **Employee Foreign Key Check:** Queries `main_users` for the 6 specific `employeeId` values and joins against the job title and employment status tables to verify the assignments use the newly created master data IDs.
3. **Email String Verification:** Uses SQL `LIKE '%@qaserve.com'` and exact string matching to ensure the email prefix wasn't accidentally deleted or corrupted during the domain update.

### Secondary Verification: Negative Control Check
The verifier will check a sample of non-divested employees (e.g., EMP005) to ensure their emails and job titles were *not* modified, ensuring the agent didn't maliciously script a global database update.

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Job Title Configured | 5 | "Divestiture Transition Staff" exists and is active |
| Employment Status Configured | 5 | "Divested Entity" exists and is active |
| EMP008 Data Update | 15 | 5 pts for Job Title, 5 pts for Status, 5 pts for correct Email |
| EMP010 Data Update | 15 | 5 pts for Job Title, 5 pts for Status, 5 pts for correct Email |
| EMP012 Data Update | 15 | 5 pts for Job Title, 5 pts for Status, 5 pts for correct Email |
| EMP015 Data Update | 15 | 5 pts for Job Title, 5 pts for Status, 5 pts for correct Email |
| EMP018 Data Update | 15 | 5 pts for Job Title, 5 pts for Status, 5 pts for correct Email |
| EMP020 Data Update | 15 | 5 pts for Job Title, 5 pts for Status, 5 pts for correct Email |
| **Total** | **100** | |

**Pass Threshold:** 70 points. 
*Anti-gaming mechanism: A score of 70 requires the agent to successfully complete the master data configuration AND perfectly update at least 4 of the 6 employee records. If the agent merely changes all 6 email addresses without updating the drop-downs (which tests cross-tab navigation), it will only score 30 points and fail.*