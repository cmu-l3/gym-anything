# access_control_audit

**Difficulty:** very_hard
**Occupation:** IT Security Analyst
**Industry:** Information Technology

## Overview

An IT security analyst performs a quarterly user access review to enforce least-privilege principles across the Nuxeo document management system. The audit involves revoking a departed employee's access, downgrading overly broad permissions, creating a security auditor group, and documenting all changes.

## Setup State

The `setup_task.sh` script:
1. Creates users:
   - `dpatel` (Deepak Patel, departed Sept 30, 2025) — has `Everything` on Projects, `ReadWrite` on Templates
   - `lnovak` (Laura Novak, Contractor) — has `Everything` on Projects (policy max is ReadWrite)
   - `rwatson` (Robert Watson) — has `ReadWrite` on Templates (compliant, do not change)
2. Creates `Access Review Policy` Note in Templates workspace (reference doc the agent must read)
3. Creates `/home/ga/Desktop/access_review_report.csv` with the audit template pre-filled
4. Opens Firefox on the Nuxeo home page

## Agent Goal

1. Read the `Access Review Policy` (IAM-QAR-2025-Q4) in the Templates workspace
2. Revoke all access for `dpatel` across all workspaces (Projects and Templates)
3. Downgrade `lnovak`'s `Everything` permission on Projects to `ReadWrite`
4. Create a new user group `iam-auditors`
5. Grant `iam-auditors` Read access to both Projects and Templates workspaces
6. Add an audit trail comment to each workspace where permissions were modified
7. Upload `/home/ga/Desktop/access_review_report.csv` to the Templates workspace

## Verification Criteria

| Criterion | Points |
|-----------|--------|
| dpatel removed from Projects workspace | 15 pts |
| dpatel removed from Templates workspace | 10 pts |
| lnovak downgraded from 'Everything' on Projects | 10 pts |
| iam-auditors group created | 10 pts |
| iam-auditors has Read on Projects | 12 pts |
| iam-auditors has Read on Templates | 8 pts |
| Audit trail comment on at least one modified workspace | 15 pts |
| access_review_report.csv uploaded to Templates | 20 pts |
| **Total** | **100 pts** |

**Pass threshold:** 60/100

## Features Tested

- Permissions / ACL revocation (`@op/Document.RemoveACL`, `@op/Document.BlockPermissionInheritance`)
- User group creation and management (`/group/` API)
- Grant permissions (`@op/Document.AddACE`)
- Comments (`@comment` endpoint)
- Document / File upload

## Notes

- `rwatson`'s ReadWrite on Templates is compliant per policy and should not be changed (not tested).
- The Access Review Policy document specifies the exact user to revoke and the exact permission violation to fix; the agent must read it to learn this.
- The CSV file upload to Templates must result in a File-type document (not a Note).
