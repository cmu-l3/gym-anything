# Access Control Restructure

## Domain Context

Security management specialists and loss prevention managers regularly need to maintain access control in VMS systems: deprovisioning accounts for departed personnel and onboarding external auditors or contractors with the correct permissions and contact details. This must be done precisely — wrong emails, duplicate accounts, or lingering credentials from departed staff all represent compliance and security risks.

## Task Overview

**Difficulty**: hard
**Occupation context**: Security Management Specialist / Loss Prevention Manager

The facility security team has undergone a personnel change. Two staff members (john.smith and sarah.jones) have left the organization and their VMS accounts must be deleted. A third-party security auditor from an external firm needs access. Additionally, an audit trail view layout is needed for the auditor's work.

The agent must:

1. Delete the user account with login **`john.smith`**
2. Delete the user account with login **`sarah.jones`**
3. Create a new external auditor account:
   - Login: **`ext.auditor`**
   - Full name: **`External Security Auditor`**
   - Email: **`auditor@thirdparty-sec.com`**
   - Role: **`Viewer`**
4. Create a layout named **`"Audit Trail View"`** containing:
   - Entrance Camera
   - Server Room Camera

## Success Criteria

| Criterion | Points |
|-----------|--------|
| `john.smith` account deleted | 20 |
| `sarah.jones` account deleted | 20 |
| `ext.auditor` account created with correct email and full name | 30 |
| Layout "Audit Trail View" exists with Entrance + Server Room cameras | 30 |
| **Total** | **100** |
| **Pass threshold** | **70** |

## Starting State

`setup_task.sh` ensures:
- `john.smith` and `sarah.jones` exist with Viewer role
- `ext.auditor` does NOT exist (removed if pre-existing)
- "Audit Trail View" layout does NOT exist (removed if pre-existing)

## Verification Strategy

`export_result.sh` queries the Nx Witness REST API for all users and layouts:
- Checks that `john.smith` and `sarah.jones` are absent
- Checks that `ext.auditor` exists with correct `fullName` and `email`
- Checks that "Audit Trail View" layout exists containing Entrance Camera and Server Room Camera

Results written to `/tmp/access_control_restructure_result.json`.

`verifier.py` reads the JSON and applies partial scoring per subtask.

## Access Information

- **URL**: https://localhost:7001
- **Login**: admin / Admin1234!
- **API base**: https://localhost:7001/rest/v1/

## Edge Cases

- User `ext.auditor` must have the email `auditor@thirdparty-sec.com` exactly (case-insensitive match)
- Layout items use `resourceId` which may include curly braces `{uuid}` — stripped before comparison
- Partial credit: completing only some subtasks gives proportional score

## Schema Reference

```
GET /rest/v1/users
  → [{id, name, fullName, email, permissions}]

DELETE /rest/v1/users/{id}
  → delete user

POST /rest/v1/users
  → create user: {name, fullName, email, password, permissions}

GET /rest/v1/layouts
  → [{id, name, items: [{resourceId}]}]

POST /rest/v1/layouts
  → create layout: {name, items: [{resourceId, ...}]}
```
