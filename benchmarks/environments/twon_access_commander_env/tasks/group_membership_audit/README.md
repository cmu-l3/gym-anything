# Task: group_membership_audit

## Domain Context

Access control policy at BuildingTech Solutions prohibits contractor personnel from being members of the "IT Department" or "Security Staff" groups. These groups grant badge access to the server room and the security command center. A compliance audit has detected violations that must be remediated.

## Goal

Audit the "IT Department" and "Security Staff" groups. For every user who is:
- A member of either restricted group, AND
- Employed by an external contractor company (NOT BuildingTech Solutions)

Remove that user from the restricted group. Do NOT remove legitimate BuildingTech Solutions employees.

The agent is not told which users are in violation — it must discover this by inspecting the system.

## Starting State (Injected Violations)

`setup_task.sh` injects 3 policy violations:
- Olumide Adeyemi (Meridian Facilities) → added to **IT Department**
- Tomás Guerrero (Meridian Facilities) → added to **Security Staff**
- Nadia Ivanova (Meridian Facilities) → added to **Security Staff**

Legitimate members (must NOT be removed):
- IT Department: Kwame Asante, Mei-Ling Zhang (both @buildingtech.com)
- Security Staff: Victor Schulz, Tamara Kowalski, Leon Fischer (SecureGuard Services)

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Olumide Adeyemi removed from IT Department | 30 pts |
| Tomás Guerrero removed from Security Staff | 30 pts |
| Nadia Ivanova removed from Security Staff | 30 pts |
| No legitimate members removed | 10 pts |
| **Pass threshold** | **70 pts** |

## Verification Strategy

`export_result.sh` queries the current member lists of both restricted groups and each Meridian contractor's group memberships. `verifier.py` checks each violation was resolved and that legitimate members were retained.

## Files

- `task.json` — Task specification (difficulty: very_hard)
- `setup_task.sh` — Injects 3 policy violations into restricted groups
- `export_result.sh` — Queries group membership state post-task
- `verifier.py` — Scores 4 independent criteria
