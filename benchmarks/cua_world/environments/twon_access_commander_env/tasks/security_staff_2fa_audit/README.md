# Task: security_staff_2fa_audit

## Domain Context

Following penetration test findings, a corporate security policy update mandates two-factor badge access for security personnel and requires disabled accounts to be stripped of credentials to prevent bypass of account lockout at legacy readers. This is a dual-policy enforcement task requiring discovery across multiple system dimensions.

## Goal

**Policy 1 — Two-factor authentication for Security Staff:**
Every member of the "Security Staff" group must have BOTH an RFID card AND a PIN. Any Security Staff member who has a card but no PIN must have PIN **"9911"** assigned. Do not remove existing cards.

**Policy 2 — Disabled account credential hygiene:**
Any user account with `enabled=false` must have ALL credentials revoked (0 cards, 0 PINs).

The agent must discover Security Staff members and disabled users independently by inspecting the system.

## Starting State (Injected)

`setup_task.sh` prepares the challenge state:
- **Security Staff members** (Victor Schulz, Tamara Kowalski, Leon Fischer): PINs removed so each has only an RFID card.
- **Disabled users** (Priya Nair, Carlos Mendoza): accounts set to disabled=false, RFID cards restored so there are credentials to revoke.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Victor Schulz has PIN credential | 10 pts |
| Victor Schulz retains RFID card | 5 pts |
| Tamara Kowalski has PIN credential | 10 pts |
| Tamara Kowalski retains RFID card | 5 pts |
| Leon Fischer has PIN credential | 10 pts |
| Leon Fischer retains RFID card | 5 pts |
| Priya Nair has 0 credentials | 25 pts |
| Carlos Mendoza has 0 credentials | 25 pts |
| Collateral integrity (Security Staff cards intact) | 5 pts |
| **Pass threshold** | **70 pts** |

## Verification Strategy

`export_result.sh` queries the Security Staff group member list with credential details, and the two target disabled users' credential counts. `verifier.py` applies the 9-criterion scoring above.

## Files

- `task.json` — Task specification (difficulty: very_hard)
- `setup_task.sh` — Removes Security Staff PINs; disables Priya Nair and Carlos Mendoza with credentials
- `export_result.sh` — Queries Security Staff group + disabled user credentials
- `verifier.py` — Scores 9 criteria across both policies
