# Tune Alert Rules to Suppress False Positives (`tune_rule_false_positives@1`)

## Overview

This task tests the agent's ability to tune Wazuh's built-in detection rules to reduce alert fatigue by suppressing known false positives. The agent must override an existing rule's alert level and create a child rule that excludes a known-good service account — two of the most common day-to-day operations for Security Operations Center analysts.

## Rationale

**Why this task is valuable:**
- Tests understanding of Wazuh rule override mechanism (`overwrite="yes"`)
- Tests creation of child/exception rules using `if_sid`
- Validates ability to edit `local_rules.xml` through the API or direct file editing
- Requires a manager restart to apply changes, testing operational awareness
- Directly addresses the #1 pain point in SIEM operations: alert fatigue

**Real-world Context:** An Information Security Analyst at a financial services company is drowning in low-value alerts. The SOC team has identified two persistent sources of noise: (1) Rule 5402 ("Successful sudo to ROOT executed") fires hundreds of times per day because their environment has many administrators who routinely use sudo — this is expected and approved behavior. (2) Rule 5501 ("Login session opened") constantly fires for the `backup_svc` service account which runs automated backup jobs every 15 minutes. The analyst needs to tune these rules in `local_rules.xml` so the team can focus on real threats.

## Task Description

**Goal:** Modify Wazuh's `local_rules.xml` to suppress two known sources of false positive alerts, then restart the manager so the changes take effect.

**Starting State:** Wazuh manager, indexer, and dashboard are running with default configuration. The `local_rules.xml` file either does not exist or contains only the default empty group. Firefox is open to the Wazuh dashboard.

**Expected Actions:**

1. **Override rule 5402** (Successful sudo to ROOT executed) by adding an overwrite entry in `/var/ossec/etc/rules/local_rules.xml` that sets its level to `0`. The overwritten rule must retain the original `if_sid` of `5401` and the original `match` pattern `; USER=root ; COMMAND=`. Use the `overwrite="yes"` attribute on the `<rule>` element. Update the description to indicate the rule has been suppressed (e.g., append " - suppressed due to expected admin sudo usage").

2. **Create a new child rule with ID 100100** under rule 5501 (Login session opened) that matches logs containing the username `backup_svc`. Set this rule's level to `0` so that login session alerts for the backup service account are suppressed. Include a meaningful description such as "Suppressed: Login session for backup_svc service account".

3. **Restart the Wazuh manager** so the new rules are loaded and active.

The rules should be added to `/var/ossec/etc/rules/local_rules.xml` inside the Wazuh manager container (`wazuh-wazuh.manager-1`). This can be done via:
- The Wazuh API endpoint `PUT /rules/files/local_rules.xml`
- Or by directly editing the file inside the container using `docker exec`

**Final State:** After the manager restart, querying the Wazuh API for rule 5402 should show level 0, and rule 100100 should exist with level 0 and `if_sid` 5501.

## Verification Strategy

### Primary Verification: API Rule Query & File Inspection

The verifier performs multiple checks:
1.  **API Status**: Queries the running Wazuh API to confirm rule 5402 is now level 0 and rule 100100 exists at level 0. This proves the rules were loaded successfully.
2.  **File Content**: Inspects `local_rules.xml` for `overwrite="yes"` and specific match patterns (`backup_svc`).
3.  **Process State**: Checks if the Wazuh manager was restarted during the task window.

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Rule 5402 exists with level 0 | 25 | API query confirms rule 5402 is overridden to level 0 |
| Rule 5402 uses overwrite="yes" | 10 | The local_rules.xml contains proper overwrite attribute |
| Rule 5402 retains original logic | 5 | Rule still has if_sid 5401 and correct match pattern |
| Rule 100100 exists with level 0 | 25 | API query confirms child rule 100100 exists at level 0 |
| Rule 100100 references if_sid 5501 | 10 | Child rule correctly chains from parent rule 5501 |
| Rule 100100 matches backup_svc | 10 | Rule contains match/field for the backup_svc username |
| Manager restarted successfully | 10 | Wazuh manager is running with the new rules loaded |
| local_rules.xml is valid XML | 5 | File parses correctly and doesn't break the manager |
| **Total** | **100** | |

**Pass Threshold:** 70 points, with both Rule 5402 level 0 (25pts) and Rule 100100 exists (25pts) being mandatory for a pass.