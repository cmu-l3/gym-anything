# crisis_comms_rapid_response

## Overview

**Occupation**: Public Relations Specialists (27-3031.00)
**Difficulty**: very_hard
**Environment**: Socioboard 4.0 (social media management platform)

A crisis communications scenario that uniquely requires **team deletion** — the only task in this suite that tests this feature. The agent must clean up 4 archived teams (identifiable by their `[ARCHIVED]` name prefix), then build fresh crisis monitoring infrastructure, manage two users with distinct roles, and add 4 news RSS feeds. The archive cleanup must be performed without touching any of the 6 ongoing operational teams.

## Goal (End State)

1. **All [ARCHIVED] teams deleted**:
   - `[ARCHIVED] Seasonal Campaign Q3` — deleted
   - `[ARCHIVED] Product Launch Beta` — deleted
   - `[ARCHIVED] Regional Partnership West` — deleted
   - `[ARCHIVED] Trade Show Presence` — deleted

2. **Admin profile** updated:
   - first_name: `Daniel`
   - last_name: `Park`
   - about_me contains: `Meridian PR`
   - timezone: `Europe/London`
   - phone: contains `7700900042`

3. **Three crisis monitoring teams** created:
   - `Crisis: Media Monitoring`
   - `Crisis: Social Sentiment`
   - `Crisis: Executive Briefing`

4. **Victoria Santos** (`victoria.santos@socioboard.local`) in ALL three crisis teams

5. **John Smith** (`john.smith@socioboard.local`) in `Crisis: Media Monitoring` and `Crisis: Social Sentiment` ONLY — NOT in `Crisis: Executive Briefing`

6. **Four RSS feeds** submitted (≥4 POST /getRss entries after baseline)

7. **Six operational teams** remain intact (e.g., `Brand Monitoring`, `Media Relations`, others)

## What Makes This Hard

- Team deletion is NOT common in typical Socioboard workflows — agent must find the delete option
- Must distinguish `[ARCHIVED]` teams (delete) from non-archived teams (preserve)
- 4 archived teams must ALL be deleted — partial deletion still fails
- Victoria Santos goes into ALL crisis teams; John Smith only into 2 of 3 — easy to over-add
- Timezone must change to UK (Europe/London) — a transatlantic switch
- Phone number is in UK format (+44-7700-900042) — different from US numbers in other tasks
- 4 RSS feeds (more than most tasks)

## Success Criteria

| Criterion | Weight | Verification |
|---|---|---|
| 4 [ARCHIVED] teams deleted | 20 pts (5 each) | DB: COUNT(*) = 0 for each name |
| Profile first_name = Daniel | 4 pts | DB: user_details.first_name |
| Profile last_name = Park | 4 pts | DB: user_details.last_name |
| Meridian PR in bio | 5 pts | DB: user_details.about_me |
| timezone = Europe/London | 4 pts | DB: user_details.time_zone |
| phone contains 7700900042 | 4 pts | DB: user_details.phone_no |
| 3 crisis teams created | 15 pts (5 each) | DB: team_informations |
| victoria.santos in all 3 | 15 pts (5 each) | DB: join membership |
| john.smith in 2 correct teams | 10 pts (5 each) | DB: join membership |
| john.smith NOT in Executive Briefing | 5 pts | DB: absence check |
| ≥4 RSS feeds | 10 pts | Apache log count |
| 2 safe teams still exist | 4 pts (2 each) | DB: team_informations |

**Pass threshold**: 60/100

**Important**: Even if the agent cannot delete teams (20 pts lost), the remaining 80 pts still allows passing at 60. Team deletion is the distinguishing challenge but not a hard gate.

## Verification Strategy

Deletion check (team should NOT exist):
```sql
SELECT COUNT(*) FROM team_informations WHERE team_name = '[ARCHIVED] Seasonal Campaign Q3';
-- Expected: 0 (deleted)
```

All other checks use the standard membership join pattern.

## Schema Reference

| Table | Key Columns |
|---|---|
| `user_details` | user_id, email, first_name, last_name, about_me, time_zone, phone_no |
| `team_informations` | team_id, team_name |
| `join_table_users_teams` | user_id, team_id |

## Pre-Seeded State

**Users pre-created**:
- `victoria.santos@socioboard.local` — crisis communications lead
- `john.smith@socioboard.local` — PR monitoring specialist

**Teams created by setup**:
- 4 `[ARCHIVED]` teams — agent must delete all of them
- 6 operational teams (Brand Monitoring, Media Relations, Social Listening, Executive Comms, Internal Comms, Influencer Network) — must NOT be deleted

**Admin profile**: injected as "Temp Account"

## Do-Nothing Score Analysis

- [ARCHIVED] teams still exist: 0 pts (they need to be deleted)
- Profile: 0 pts (wrong values)
- Crisis teams don't exist: 0 pts
- Victoria/John memberships: 0 pts
- john.smith NOT in non-existent Executive Briefing: 5 pts
- Safe teams exist: 4 pts
- **Total: ~9 pts → passed=False** ✓

## Edge Cases

- Team deletion UI: Teams > select team > team settings > delete (may require scrolling)
- `[ARCHIVED]` includes the square brackets — agent must search for exact prefix pattern
- europe/London vs America/* — timezone selector has limited options; must scroll to find Europe/London
- victoria.santos must be in ALL 3 crisis teams, not just 2 — easy to under-add
