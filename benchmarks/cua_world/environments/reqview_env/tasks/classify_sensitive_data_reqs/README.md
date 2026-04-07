# Classify Sensitive Data Requirements (`classify_sensitive_data_reqs@1`)

## Overview

This task evaluates the agent's ability to perform a content-based compliance audit within ReqView. The agent must identify requirements containing sensitive technical data (specifically IPv4 addresses) using search or filter tools, and classify them by updating a custom "DataClassification" attribute. This tests search proficiency, bulk attribute editing, and attention to detail in a compliance context.

## Rationale

**Why this task is valuable:**
- **Tests "Search/Filter" Proficiency:** Requires using advanced filtering (e.g., regex or smart keywords) to find content distributed across a document, rather than just navigating to a known ID.
- **Validates Data Governance Workflows:** Simulates a real-world scenario where legacy data must be tagged/classified for security (GDPR/PII/Security audits).
- **Exercises Attribute Management:** Tests the ability to modify custom attributes for specific subsets of requirements.
- **Requires Decision Making:** The agent must distinguish between sensitive requirements (those with IPs) and non-sensitive ones.

**Real-world Context:** A Security Compliance Officer is auditing a legacy "Smart Home" system specification. The previous engineering team hardcoded server IP addresses into the requirements text, which violates the new security policy. Before these can be scrubbed, they must be identified and tagged as "Confidential" to prevent accidental release to external vendors.

## Task Description

**Goal:** Identify all requirements in the SRS document that contain an IPv4 address (e.g., `192.168.1.50`) and set their **DataClassification** attribute to **"Confidential"**.

**Starting State:** 
- ReqView is open with the "Smart Home" project loaded.
- The **SRS** document is open.
- A custom attribute **DataClassification** exists (Values: *Public*, *Internal*, *Confidential*) but is currently set to *Public* (or empty) for all requirements.
- Several requirements scattered throughout the SRS document have had IPv4 addresses injected into their description text (e.g., "The hub connects to 10.0.1.55...").

**Expected Actions:**
1. Analyze the SRS document to find requirements containing IPv4 addresses. (Recommended: Use the Filter bar with a text search or regular expression like `description ~ '[0-9]+\.[0-9]+\.'`).
2. For every requirement containing an IP address:
   - Select the requirement.
   - Locate the **DataClassification** attribute in the right-hand Attributes pane.
   - Change the value to **Confidential**.
3. Ensure no other requirements are changed.
4. Save the project.

**Final State:**
- All requirements containing IP address patterns have `DataClassification` set to `"Confidential"`.
- Requirements without IP addresses remain unchanged (default/empty).
- The project changes are saved to disk.

## Verification Strategy

### Primary Verification: JSON Content Analysis
The verification script parses the underlying `SRS.json` file to validate the attributes:

1. **Load Ground Truth:** The setup script recorded the list of IDs where IPs were injected (e.g., `["SRS-12", "SRS-45", "SRS-99"]`).
2. **Verify Target Requirements:** Check that every ID in the ground truth list has the attribute `DataClassification` set to `"Confidential"`.
   - *Tolerance:* All targets must be marked. Missing even one is a failure (security risk).
3. **Verify False Positives:** Check a sample of requirements *not* in the ground truth list to ensure they were NOT marked "Confidential".
   - *Tolerance:* 0 false positives allowed (preserves data integrity).
4. **Timestamp Check:** Verify the file modification time is later than task start.

### Secondary Verification: VLM Visual Confirmation
- **Filter Usage:** Check trajectory screenshots to see if the agent used the "Filter" bar (top of view) or "Search" pane. This distinguishes efficient "power user" behavior from manual scrolling.
- **Attribute Pane:** Verify the agent interacted with the "Attributes" pane on the right side.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **Recall (Sensitivity)** | 50 | All requirements containing IP addresses are marked "Confidential". (Proportional deduction for missed reqs). |
| **Precision (Selectivity)** | 30 | Requirements *without* IP addresses are NOT marked "Confidential". (-10 points per false positive). |
| **Data Integrity** | 10 | The requirement description text itself was not modified (only the attribute). |
| **Save Success** | 10 | File modification timestamp indicates successful save. |
| **Total** | **100** | |

**Pass Threshold:** 85 points (Must find almost all sensitive data and have few false positives).