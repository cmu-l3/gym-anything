# influencer_campaign_operations

## Overview

**Occupation**: Advertising and Promotions Managers (11-2011.00)
**Difficulty**: very_hard
**Environment**: Socioboard 4.0 (social media management platform)

A digital advertising agency scenario with the most complex multi-user membership matrix of the suite. Three different users (alex.rivera, priya.nair, john.smith) must each be assigned to specific client teams from a set of 5, with all three having distinct and partially overlapping assignments and strict exclusions. GreenPath Sustainability is shared by both alex.rivera and priya.nair; NovaBrand Retail and MediaCraft Studios are the only teams john.smith joins.

## Goal (End State)

1. **Admin profile** updated:
   - first_name: `Marcus`
   - last_name: `Webb`
   - about_me contains: `Fusion Creative Agency`
   - timezone: `America/New_York`
   - phone: contains `2125550177`

2. **Five client teams** created:
   - `TechFlow Solutions`
   - `NovaBrand Retail`
   - `GreenPath Sustainability`
   - `MediaCraft Studios`
   - `SportsPulse Network`

3. **Three-way user assignments**:
   - **Alex Rivera** (`alex.rivera@socioboard.local`): in TechFlow, NovaBrand, GreenPath — NOT in MediaCraft or SportsPulse
   - **Priya Nair** (`priya.nair@socioboard.local`): in GreenPath, MediaCraft, SportsPulse — NOT in TechFlow or NovaBrand
   - **John Smith** (`john.smith@socioboard.local`): in NovaBrand, MediaCraft — NOT in TechFlow, GreenPath, or SportsPulse

4. **Three RSS feeds** submitted (≥3 POST /getRss entries after baseline)

5. **Three Q1 client teams** remain unchanged: `Q1 - Luminary Fashion`, `Q1 - BrewCo Beverages`, `Q1 - Atlas Automotive`

## What Makes This Hard

- Three users with intersecting but distinct assignments (hardest membership puzzle in the suite)
- GreenPath Sustainability is the only team with 2 members (alex + priya) — not john
- NovaBrand Retail is in BOTH alex's and john's list but NOT priya's
- MediaCraft Studios is in BOTH priya's and john's list but NOT alex's
- Agent must track 3 separate assignment matrices simultaneously
- 7 total "NOT in" exclusions to respect

## Success Criteria

| Criterion | Weight | Verification |
|---|---|---|
| Profile (4 fields) | 20 pts (4-5 each) | DB: user_details |
| All 5 client teams | 25 pts (5 each) | DB: team_informations |
| alex.rivera correct (3 teams) | 12 pts (4 each) | DB: join membership |
| alex.rivera NOT in 2 excluded | 4 pts (2 each) | DB: absence check |
| priya.nair correct (3 teams) | 12 pts (4 each) | DB: join membership |
| priya.nair NOT in 2 excluded | 4 pts (2 each) | DB: absence check |
| john.smith correct (2 teams) | 8 pts (4 each) | DB: join membership |
| john.smith NOT in 3 excluded | 6 pts (2 each) | DB: absence check |
| ≥3 RSS feeds | 9 pts | Apache log count |

**Pass threshold**: 60/100

## Verification Strategy

Uses `exec_in_env` for all checks. Same membership query pattern as other tasks:
```sql
SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  JOIN user_details ud ON jt.user_id = ud.user_id
  WHERE ti.team_name = 'TechFlow Solutions' AND ud.email = 'alex.rivera@socioboard.local';
```

## Schema Reference

| Table | Key Columns |
|---|---|
| `user_details` | user_id, email, first_name, last_name, about_me, time_zone, phone_no |
| `team_informations` | team_id, team_name |
| `join_table_users_teams` | user_id, team_id |

## Pre-Seeded State

**Users pre-created**:
- `alex.rivera@socioboard.local` — technology/consumer brand lead
- `priya.nair@socioboard.local` — media/entertainment lead
- `john.smith@socioboard.local` — media buying coordinator (shared with other tasks)

**Q1 contaminator teams** (must remain):
- `Q1 - Luminary Fashion`
- `Q1 - BrewCo Beverages`
- `Q1 - Atlas Automotive`

**Admin profile**: injected as Casey Thornton, America/Los_Angeles

## Do-Nothing Score Analysis

- Profile: 0 pts (wrong values)
- 5 client teams don't exist: 0 pts
- All correct memberships: 0 pts
- "Not in excluded" (non-existent teams): ~14 pts
- RSS: 0 pts
- **Total: ~14 pts → passed=False** ✓

## Membership Matrix Reference

| Team | Alex | Priya | John |
|---|---|---|---|
| TechFlow Solutions | ✓ | ✗ | ✗ |
| NovaBrand Retail | ✓ | ✗ | ✓ |
| GreenPath Sustainability | ✓ | ✓ | ✗ |
| MediaCraft Studios | ✗ | ✓ | ✓ |
| SportsPulse Network | ✗ | ✓ | ✗ |
