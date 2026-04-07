# Corporate Training Catalog Setup (`corporate_training_catalog_setup@1`)

## Overview
This task evaluates the agent's ability to configure the corporate learning ecosystem within Sentrifugo's "Training" module. The agent must process a vendor contract summary to create external training providers and then populate the corporate training catalog with specific courses linked to those providers.

## Rationale
**Why this task is valuable:**
- Tests navigation within the Training module, a distinct area separate from standard employee/leave management.
- Requires understanding of relational data entry (providers must be created before courses can be linked to them).
- Evaluates the agent's ability to accurately extract and map data from an unstructured text document into structured system fields.
- **Real-world Context:** A First-Line Supervisor is finalizing the Q3 2026 Corporate Learning rollout. Before employees can request enrollment, the supervisor must add these vendors as "Training Providers" in Sentrifugo and add their contracted classes to the "Training Courses" catalog.

## Task Description

**Goal:** Register two external training providers and three training courses (correctly linked to their respective providers) in the Sentrifugo Training module, based on the provided vendor summary document.

**Starting State:** 
Firefox is open and logged into Sentrifugo as the Admin user. The dashboard is visible. A vendor summary document is located on the Desktop at `~/Desktop/q3_training_vendors.txt`. The Training module is currently empty (no providers or courses exist).

**Expected Actions:**
1. Open and read the document `~/Desktop/q3_training_vendors.txt`.
2. Navigate to the **Training** module in Sentrifugo (typically via the top menu or sidebar).
3. Access the **Training Providers** configuration section.
4. Add the first provider ("Red Cross Safety Institute") with the provided contact name, email, and phone number.
5. Add the second provider ("TechAdvantage Learning") with its respective contact details.
6. Navigate to the **Training Courses** configuration section.
7. Add the "Occupational First Aid & CPR" course, ensuring it is linked to the Red Cross provider.
8. Add the "Advanced Python for Data Science" course, ensuring it is linked to the TechAdvantage provider.
9. Add the "Cloud Architecture Fundamentals" course, also linked to the TechAdvantage provider.

**Final State:** 
Both training providers are active in the system. All three training courses are created, active, and strictly associated with the correct training provider. 

## Verification Strategy

### Primary Verification: Relational Database Verification
The verifier queries the `sentrifugo-db` Docker container to extract `main_trainingproviders` and `main_trainingcourses`. It programmatically verifies that the courses correctly reference the dynamically assigned ID of the newly created providers.

### Secondary Verification: VLM Trajectory Verification
The verifier extracts trajectory frames during the task run and prompts a Vision Language Model to ensure the agent physically navigated the Sentrifugo "Training" module interface, defending against direct API/SQL injection gaming.

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Provider 1 Exists | 15 | "Red Cross Safety Institute" created with correct email/phone. |
| Provider 2 Exists | 15 | "TechAdvantage Learning" created with correct email/phone. |
| Course 1 Created | 20 | "Occupational First Aid & CPR" exists. |
| Course 1 Linked | 5 | Course 1 is mapped to Provider 1 ID. |
| Course 2 Created | 20 | "Advanced Python for Data Science" exists. |
| Course 2 Linked | 5 | Course 2 is mapped to Provider 2 ID. |
| Course 3 Created | 15 | "Cloud Architecture Fundamentals" exists. |
| Course 3 Linked | 5 | Course 3 is mapped to Provider 2 ID. |
| **Total** | **100** | |

**Pass Threshold:** 65 points.