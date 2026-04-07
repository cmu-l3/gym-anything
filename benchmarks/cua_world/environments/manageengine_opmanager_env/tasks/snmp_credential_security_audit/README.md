# Task: snmp_credential_security_audit

## Overview
This task tests an agent's ability to implement a security hardening policy in ManageEngine OpManager by replacing the default insecure SNMP community string 'public' with organization-approved credential profiles, and onboarding a new network device with the correct secure credentials. It simulates a real-world security remediation workflow driven by a formal policy document delivered by the information security team.

## Domain Context
Use of the default SNMP community string 'public' is a well-known security risk catalogued in CIS Benchmarks and vendor hardening guides. Network administrators routinely respond to audit findings by updating SNMP credential profiles in their monitoring platform and ensuring that new infrastructure is enrolled with approved, non-default strings from the outset. Failure to act leaves devices susceptible to unauthorized SNMP read access.

## Goal
The agent must read `~/Desktop/snmp_security_policy.txt`, then implement three requirements in OpManager at http://localhost:8060 (admin/Admin@123): (1) create a new SNMP credential profile named `netops-monitor-2024` with matching community string, (2) create a second profile named `netops-dmz-2024`, and (3) add a new device `Perimeter-Firewall-01` at IP `192.168.1.100` using the `netops-dmz-2024` credential.

## Starting State
OpManager is running with its default post-install configuration. No `netops-monitor-2024` or `netops-dmz-2024` SNMP credential profiles exist. No device named `Perimeter-Firewall-01` or with IP `192.168.1.100` is present in the inventory. The security policy document is pre-placed on the desktop for the agent to read.

## Agent Workflow
1. Open and read `~/Desktop/snmp_security_policy.txt` from the Ubuntu desktop.
2. Log in to OpManager at http://localhost:8060 with credentials admin/Admin@123.
3. Navigate to Settings > Discovery > SNMP Credentials.
4. Create a new SNMP credential profile named `netops-monitor-2024` with community string `netops-monitor-2024` and SNMP version v2c.
5. Create a second SNMP credential profile named `netops-dmz-2024` with community string `netops-dmz-2024` and SNMP version v2c.
6. Navigate to the device addition interface (Settings > Discovery > New Device, or Inventory > Add Device).
7. Add device with IP `192.168.1.100`, display name `Perimeter-Firewall-01`, type Firewall, and SNMP community `netops-dmz-2024`.
8. Save all changes and confirm the device appears in the inventory and credentials appear in the credential store.

## Success Criteria (100 points total, pass at 60)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Device Perimeter-Firewall-01 added | 34 | Device with name 'Perimeter-Firewall-01' or IP '192.168.1.100' exists in OpManager inventory |
| SNMP credential netops-monitor-2024 created | 33 | Credential profile with name/community string 'netops-monitor-2024' found in the OpManager database |
| SNMP credential netops-dmz-2024 created | 33 | Credential profile with name/community string 'netops-dmz-2024' found in the OpManager database |

## Verification Approach
The `export_result.sh` script fetches the full device list from the OpManager REST API and performs a broad search of the PostgreSQL database across all SNMP-, credential-, and community-related tables. It also executes targeted queries searching for the exact credential string values. The `verifier.py` script checks the API device list and raw DB text for each criterion, using case-insensitive substring matching for credential names and both name and IP matching for the device criterion.

## Anti-Gaming
- Credential checks are performed directly against the PostgreSQL database, so creating a credential that is not actually persisted (e.g., only in a browser field) will not satisfy the criterion.
- The device check requires either the exact display name `Perimeter-Firewall-01` or the exact IP `192.168.1.100` — neither can be satisfied by modifying an existing device without the correct identifier.
- The result file is populated at export time from live system state, so pre-writing a fake result file has no effect.
- The export script enumerates all SNMP/credential/community tables dynamically, so the agent cannot predict which specific table to manipulate directly.
