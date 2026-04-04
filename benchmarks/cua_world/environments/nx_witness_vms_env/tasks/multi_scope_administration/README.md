# Multi-Scope Administration

## Domain Context

VMS administrators onboarding a new client to a managed security platform must perform system-wide configuration across multiple functional areas: system identity (renaming the system to reflect the client's branding), logical grouping of cameras into purpose-specific layouts (perimeter vs. infrastructure monitoring), and vendor/technical access provisioning. These are conceptually distinct tasks that span different parts of the VMS, requiring the administrator to navigate system settings, camera management, layout management, and user management — all within one work session.

## Task Overview

**Difficulty**: hard
**Occupation context**: VMS Administrator / Security Management Specialist

A new retail client ("RetailSecure Pro") has been onboarded to the managed VMS platform. The client's system needs to be properly branded and organized. The agent must:

1. Rename the system to **`RetailSecure Pro`** (currently named "GymAnythingVMS")
2. Create a layout named **`"Perimeter Surveillance"`** containing:
   - Parking Lot Camera
   - Entrance Camera
3. Create a layout named **`"Infrastructure Monitoring"`** containing:
   - Server Room Camera
4. Create a new user account:
   - Login: **`vendor.tech`**
   - Full name: **`Vendor Technical Support`**
   - Email: **`tech@vendor-security.com`**
   - Role: **`Viewer`**

## Success Criteria

| Criterion | Points |
|-----------|--------|
| System renamed to "RetailSecure Pro" | 20 |
| "Perimeter Surveillance" layout with Parking Lot + Entrance cameras | 25 |
| "Infrastructure Monitoring" layout with Server Room camera | 25 |
| `vendor.tech` user with correct email and full name | 30 |
| **Total** | **100** |
| **Pass threshold** | **70** |

## Starting State

`setup_task.sh`:
- Resets system name to "GymAnythingVMS"
- Removes "Perimeter Surveillance" and "Infrastructure Monitoring" layouts if pre-existing
- Removes `vendor.tech` user if pre-existing
- Navigates Firefox to the Nx Witness system settings page

## Verification Strategy

`export_result.sh` queries:
- System name via `GET /rest/v1/system/info`
- Both layouts and their camera contents via `GET /rest/v1/layouts`
- `vendor.tech` user via `GET /rest/v1/users`

Results written to `/tmp/multi_scope_administration_result.json`.

`verifier.py` scores each of the four subtasks independently. Wrong-target rejection: if system name contains something other than "RetailSecure Pro" or variants, no points for that criterion.

## Access Information

- **URL**: https://localhost:7001
- **Login**: admin / Admin1234!
- **System name API**: `GET /rest/v1/system/info` → `{name, ...}` or `{systemName, ...}`
- **Rename API**: `POST /rest/v1/system/settings` with `{"systemName": "RetailSecure Pro"}`

## Edge Cases

- System name API field may be `name` or `systemName` depending on Nx Witness version — export handles both
- Layout `resourceId` values may have curly braces — stripped before comparison
- The agent must navigate across at least 3 distinct UI areas (system settings, layouts, users)
- Partial credit: each of the 4 subtasks scored independently

## Schema Reference

```
GET /rest/v1/system/info
  → {name: "GymAnythingVMS", ...}

POST /rest/v1/system/settings
  → {systemName: "RetailSecure Pro"}

GET /rest/v1/layouts
  → [{id, name, items: [{resourceId}]}]

POST /rest/v1/layouts
  → {name, items: [{resourceId, ...}]}

GET /rest/v1/users
  → [{id, name, fullName, email, permissions}]

POST /rest/v1/users
  → {name, fullName, email, password, permissions}
```
