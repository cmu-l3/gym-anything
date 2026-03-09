# Task: analyst_user_access

## Overview

**Domain**: Analytics User Governance
**Difficulty**: very_hard
**Occupation context**: Marketing Managers — responsible for controlling who can access which analytics data, ensuring junior analysts see only appropriate datasets, and automating reporting workflows.

## Goal

Onboard a new junior analyst with precisely scoped access:

1. **Create user** `jamie.rodriguez` (email: `jamie.rodriguez@company.test`, password: `Analytics2024!`).
2. **Grant view access** to `Main Store` and `Blog` sites **only**.
3. **Deny access** to `Mobile App` and `Confidential Data` sites.
4. **Create a monthly email report** for `jamie.rodriguez` covering the `Main Store` site.

## Pre-seeded Sites

The setup script creates four sites:
- `Main Store` — jamie.rodriguez should have 'view' access
- `Blog` — jamie.rodriguez should have 'view' access
- `Mobile App` — jamie.rodriguez must NOT have access
- `Confidential Data` — jamie.rodriguez must NOT have access

## Success Criteria

| Criterion | Points |
|-----------|--------|
| User jamie.rodriguez created with correct email | 20 |
| Has 'view' access to Main Store | 15 |
| Has 'view' access to Blog | 15 |
| Has NO access to Mobile App | 15 |
| Has NO access to Confidential Data | 15 |
| Monthly email report for jamie.rodriguez on Main Store | 20 |
| **Total** | **100** |

**Pass threshold**: ≥70 points AND user was created during task (anti-gaming gate).

## Verification Strategy

- **Wrong-target gate**: If jamie.rodriguez was not newly created during the task → score=0.
- Access check: queries `matomo_access` for (login=jamie.rodriguez, idsite=X, access=view).
- No-access check: queries `matomo_access` for jamie.rodriguez on the two restricted sites.
- Report check: queries `matomo_report` for login=jamie.rodriguez, period=month.

## Schema Reference

```sql
-- matomo_user: login, password, alias, email, token_auth, superuser_access
-- matomo_access: login, idsite, access  ('view', 'write', 'admin')
-- matomo_report: idreport, idsite, login, period, type, deleted
```
