# regional_health_education_campaign

## Overview

**Occupation**: Health Education Specialists (21-1091.00)
**Difficulty**: very_hard
**Environment**: Socioboard 4.0 (social media management platform)

A state health department scenario requiring the agent to configure a multi-regional public health campaign infrastructure. The agent must update the admin profile with a specific campaign code embedded in the bio, create 5 regional/national coordination teams, assign 3 pre-registered regional coordinators to their correct teams with strict exclusions, and add 3 public health RSS monitoring feeds.

## Goal (End State)

1. **Admin profile** updated to reflect the new director:
   - first_name: `Patricia`
   - last_name: `Wells`
   - about_me contains: `PHC-2024-DIGITAL`
   - timezone: `America/Chicago`
   - phone: contains `3125550199`

2. **Five coordination teams** created:
   - `Northeast Region`
   - `Southeast Region`
   - `Midwest Region`
   - `West Coast Region`
   - `National Campaign Hub`

3. **Coordinator assignments** (all pre-registered):
   - **Sarah Johnson** (`sarah.johnson@socioboard.local`): in `Northeast Region` + `National Campaign Hub` only
   - **David Martinez** (`david.martinez@socioboard.local`): in `Southeast Region` + `Midwest Region` + `National Campaign Hub` only
   - **Lisa Chen** (`lisa.chen@socioboard.local`): in `West Coast Region` + `National Campaign Hub` only

4. **Three RSS feeds** submitted via Content Feeds interface (≥3 POST /getRss entries)

5. **Three archive teams** from previous campaign remain unchanged: `2023 Flu Prevention Campaign`, `2023 Opioid Awareness Drive`, `2023 Mental Health Month`

## What Makes This Hard

- Campaign code (`PHC-2024-DIGITAL`) must appear verbatim in the bio — agent must type exact string
- 3 users × 5 teams = complex 3-way membership assignment
- National Campaign Hub is shared by all 3 coordinators (but each has their own regional team)
- Wrong profile timezone (New York vs. Chicago) must be detected and corrected
- Archive teams from previous campaign must be recognized as "do not touch"

## Success Criteria

| Criterion | Weight | Verification |
|---|---|---|
| Profile first_name = Patricia | 5 pts | DB: user_details.first_name |
| Profile last_name = Wells | 5 pts | DB: user_details.last_name |
| PHC-2024-DIGITAL in about_me | 8 pts | DB: user_details.about_me LIKE '%PHC-2024-DIGITAL%' |
| timezone = America/Chicago | 4 pts | DB: user_details.time_zone |
| phone contains 3125550199 | 3 pts | DB: user_details.phone_no |
| All 5 regional/national teams | 25 pts (5 each) | DB: team_informations |
| sarah.johnson correct (2 teams) | 8 pts (4 each) | DB: join membership |
| david.martinez correct (3 teams) | 12 pts (4 each) | DB: join membership |
| lisa.chen correct (2 teams) | 8 pts (4 each) | DB: join membership |
| Wrong memberships absent (8 total) | 8 pts (1 each) | DB: absence check |
| ≥3 RSS feeds submitted | 10 pts | Apache log count |
| Archive teams untouched (3) | 4 pts | DB: teams still exist |

**Pass threshold**: 60/100

## Verification Strategy

Uses `exec_in_env` for all checks. Profile query:
```sql
SELECT first_name, last_name, about_me, phone_no, time_zone
FROM user_details WHERE email = 'admin@socioboard.local' LIMIT 1;
```

Membership query:
```sql
SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  JOIN user_details ud ON jt.user_id = ud.user_id
  WHERE ti.team_name = 'Northeast Region' AND ud.email = 'sarah.johnson@socioboard.local';
```

## Schema Reference

| Table | Key Columns |
|---|---|
| `user_details` | user_id, email, first_name, last_name, about_me, time_zone, phone_no |
| `team_informations` | team_id, team_name |
| `join_table_users_teams` | user_id, team_id |

## Pre-Seeded State

**Users pre-created**:
- `sarah.johnson@socioboard.local` — Northeast coordinator
- `david.martinez@socioboard.local` — Southeast/Midwest coordinator
- `lisa.chen@socioboard.local` — West Coast coordinator

**Contaminator teams** (must not be deleted):
- `2023 Flu Prevention Campaign`
- `2023 Opioid Awareness Drive`
- `2023 Mental Health Month`

**Admin profile**: injected with wrong values (Tyler Morrison, America/New_York timezone)

## Do-Nothing Score Analysis

- Profile: 0 pts (wrong values)
- Teams don't exist: 0 pts
- Correct memberships: 0 pts (teams don't exist)
- Excluded memberships (absent from non-existent teams): ~8 pts
- RSS: 0 pts
- Archive teams exist: ~4 pts
- **Total: ~12 pts → passed=False** ✓

## Edge Cases

- Campaign code is case-sensitive: `PHC-2024-DIGITAL` (all caps with hyphens)
- Agent must not accidentally add a coordinator to ALL teams (exclusion checks)
- National Campaign Hub must be included for all 3 coordinators — easy to miss
- Archive team names from 2023 campaign must be left intact
