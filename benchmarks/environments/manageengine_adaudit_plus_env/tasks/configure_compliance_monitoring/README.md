# Task: Configure Compliance Monitoring Infrastructure

## Domain Context

Compliance officers and IT administrators at regulated organizations use ManageEngine ADAudit Plus to establish audit trail collection and automated reporting for frameworks such as GDPR, HIPAA, PCI-DSS, and SOX. Setting up ADAudit Plus for compliance involves configuring: SMTP for report delivery, role-based technician delegation, automated report schedules, and notification alerts for data collection health. These four distinct subsystems must all be configured correctly — a task that requires navigating four separate sections of the Admin interface.

## Task Goal

Configure ADAudit Plus for a compliance program with:
1. SMTP mail server for report delivery (Admin > Mail Server)
2. A new Auditor-role technician for compliance reviews (Admin > Delegation)
3. Two scheduled reports with different frequencies (Admin > Schedule Reports)
4. Event collection status notifications (Admin > Notifications)

## Starting State (Unique to This Task)

`setup_task.ps1` resets any pre-existing SMTP configuration to a blank state and removes previously scheduled reports, ensuring the agent starts from a known clean configuration. Additional Windows file access events are generated to C:\AuditTestFolder\Confidential\ for this task's audit data context.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|-------------|
| Technician `gdpr_auditor` with Auditor role | 20 | DB query |
| SMTP server set to smtp.internal.corp (or similar) | 20 | DB query |
| Scheduled report 'User Account Changes - Daily' exists | 20 | DB query |
| Scheduled report 'Privileged Access Weekly' exists | 20 | DB query |
| Notification configured for noc@internal.corp | 20 | DB query |

**Pass threshold**: 60/100

## Verification Strategy

`export_result.ps1` queries the ADAudit Plus PostgreSQL database for each configured item, trying multiple possible table name patterns. Results are written to `C:\Users\Docker\configure_compliance_monitoring_result.json`.

`verifier.py` copies the result JSON, parses it, and awards points per criterion independently.

## Why This Is Hard

- Requires navigating four distinct, unrelated Admin subsections (Mail Server, Delegation, Schedule Reports, Notifications)
- The specific UI path to each section is not given — the agent must discover it
- SMTP configuration requires setting security type (SSL vs TLS vs None) which is an easy step to miss
- The scheduled report creation requires selecting report type, frequency, format, AND recipient email — multiple form fields
- The agent must complete all four subsystems to exceed the pass threshold

## Edge Cases

- Some ADAudit Plus versions require clicking "Save & Run now" for notifications rather than just "Save"
- Scheduled reports may require selecting a specific report template/type before naming it
- SMTP port 465 corresponds to SSL; the security type dropdown must match
- The "Auditor" role may appear as "Auditor" or "AUDITOR" in the technician creation form
