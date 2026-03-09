# investigative_journalism_beat_setup

## Overview

**Occupation**: News Analysts, Reporters, and Journalists (27-3023.00)
**Difficulty**: very_hard
**Environment**: Socioboard 4.0 (social media management platform)

A newsroom scenario requiring the agent to configure a comprehensive beat monitoring system from scratch for an investigative journalism publication. The agent must discover which team assignments map to which reporters by reading the task description, then execute a multi-step setup involving team creation, selective member assignment with strict exclusions, and multiple RSS feed submissions.

## Goal (End State)

The Socioboard workspace for The Meridian Tribune should have:

1. **Five beat teams** created with exact names: `Politics & Government`, `Technology & Innovation`, `Climate & Environment`, `Finance & Markets`, `Public Health`

2. **Emily Chen** (`emily.chen@socioboard.local`) is a member of exactly:
   - `Politics & Government`
   - `Finance & Markets`
   - She must NOT appear in the other three beat teams

3. **Michael Okafor** (`michael.okafor@socioboard.local`) is a member of exactly:
   - `Technology & Innovation`
   - `Climate & Environment`
   - `Public Health`
   - He must NOT appear in the other two beat teams

4. **Five RSS feeds** have been submitted via the Content Feeds interface (≥5 POST /getRss Apache log entries after task start)

5. **Two legacy teams** (`Morning Briefing Archive`, `Sports Desk Legacy`) remain in the system unchanged — the agent must not delete them

6. **Admin profile** does not need to be updated for this task

## What Makes This Hard

- No profile update required — agent must recognize this and skip that step
- 5 teams × 2 users = complex membership matrix with strict exclusions
- Both users' assignments are "mirror image" (opposite beats), making wrong-cross contamination easy
- 5 RSS feeds must be submitted, not just 1
- Legacy contaminator teams must be recognized and left alone

## Success Criteria

| Criterion | Weight | Verification |
|---|---|---|
| All 5 beat teams exist | 40 pts (8 each) | DB: `team_informations WHERE team_name = '...'` |
| emily.chen in Politics + Finance | 10 pts (5 each) | DB: join_table_users_teams JOIN |
| emily.chen NOT in Tech/Climate/Health | 12 pts (4 each) | DB: absence check |
| michael.okafor in Tech/Climate/Health | 15 pts (5 each) | DB: join_table_users_teams JOIN |
| michael.okafor NOT in Politics/Finance | 8 pts (4 each) | DB: absence check |
| ≥5 RSS feeds submitted | 10 pts | Apache log: count "POST /getRss" |
| Contaminator teams untouched | 5 pts (2+2+1) | DB: teams still exist |

**Pass threshold**: 60/100

## Verification Strategy

The verifier uses `exec_in_env` to run MySQL queries directly in the VM:

```sql
-- Team existence
SELECT COUNT(*) FROM team_informations WHERE team_name = 'Politics & Government';

-- Membership check
SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  JOIN user_details ud ON jt.user_id = ud.user_id
  WHERE ti.team_name = 'Politics & Government' AND ud.email = 'emily.chen@socioboard.local';
```

RSS check uses Apache log tail from baseline:
```bash
sudo tail -n +$((baseline+1)) /var/log/apache2/socioboard_access.log | grep -c "POST /getRss"
```

## Schema Reference

| Table | Key Columns |
|---|---|
| `user_details` | user_id, email, first_name, last_name |
| `team_informations` | team_id, team_name |
| `join_table_users_teams` | user_id, team_id |

## Pre-Seeded State

- `emily.chen@socioboard.local` — pre-created reporter (politics/finance beat)
- `michael.okafor@socioboard.local` — pre-created reporter (tech/science beat)
- `Morning Briefing Archive` — contaminator team (must not be deleted)
- `Sports Desk Legacy` — contaminator team (must not be deleted)
- Admin profile: reset to neutral (no wrong values to fix)

## Do-Nothing Score Analysis

With no agent action:
- Beat teams don't exist: 0 pts
- Both reporters excluded from non-existent teams: ~20 pts (below threshold)
- RSS: 0 pts
- Contaminator teams exist: ~4 pts
- **Total: ~24 pts → passed=False** ✓

## Edge Cases

- If agent adds emily.chen to ALL 5 teams, exclusion checks fail (-12 pts)
- If agent creates teams with slightly wrong names (e.g., "Politics and Government"), all dependent checks fail
- RSS feeds must be submitted via the UI (POST /getRss), not via API
- Contaminator team deletion: -4 pts (don't delete them)
