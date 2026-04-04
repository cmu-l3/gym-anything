# Task: stolen_card_replacement

## Domain Context

Physical security managers issue emergency card replacements when a batch of RFID cards is discovered to have been compromised at the manufacturer. The compromised cards must be identified by serial number range, revoked from all holders, and replaced — without disrupting user access or disabling accounts.

## Goal

Cards in the serial number range **0004521820–0004521829** have been flagged as a compromised batch. For every user holding a card in this range:
1. **Revoke** the compromised card
2. **Assign a replacement card** starting from 0004522100 (first affected user gets 0004522100, second gets 0004522101, etc.)
3. Keep all user accounts **enabled** (do NOT disable anyone)

The agent must scan the system to identify which users have compromised cards.

## Starting State (Injected)

`setup_task.sh` assigns compromised cards to 2 employees (replacing their original cards):
- Heather Morrison → card **0004521820** (originally 0004521893)
- Robert Nakamura → card **0004521821** (originally 0004521894)

Any prior replacement-range cards (0004522100–0004522109) are cleaned up before the task.

## Success Criteria

| Criterion | Points | Per user |
|-----------|--------|----------|
| Compromised card revoked | 20 pts each | 40 pts total |
| Replacement card (0004522100-0004522109) assigned | 30 pts each | 60 pts total |
| **Pass threshold** | **70 pts** | |

## Verification Strategy

`export_result.sh` inspects the credentials of both target users. `verifier.py` checks each of the 2 per-user criteria × 2 users = 4 scored items.

## Files

- `task.json` — Task specification (difficulty: very_hard)
- `setup_task.sh` — Assigns compromised cards to Heather and Robert
- `export_result.sh` — Queries target users' credentials and enabled status
- `verifier.py` — Scores 6 criteria across 2 users
