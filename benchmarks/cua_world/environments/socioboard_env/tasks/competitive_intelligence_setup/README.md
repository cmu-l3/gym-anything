# competitive_intelligence_setup

## Overview

**Occupation**: Marketing Managers (11-2021.00)
**Difficulty**: very_hard
**Environment**: Socioboard 4.0 (social media management platform)

A market intelligence scenario emphasizing contamination protection. Four Q1 campaign teams already exist with existing memberships — the agent must create an entirely new Q2 structure without touching the Q1 teams. The profile bio must contain an exact campaign tracking code (`COMPINT-Q2-2024`). Two users have complementary (non-overlapping) market segment assignments across 5 new teams.

## Goal (End State)

1. **Admin profile** updated:
   - first_name: `Sophia`
   - last_name: `Chen`
   - about_me contains: `COMPINT-Q2-2024`
   - timezone: `America/Los_Angeles`
   - phone: contains `4155550233`

2. **Five market segment teams** created (must NOT exist before task):
   - `Enterprise Solutions Vertical`
   - `SMB Focus Group`
   - `Consumer Direct Channel`
   - `Healthcare Vertical`
   - `Education Sector`

3. **Complementary user assignments** (non-overlapping):
   - **Alex Brand** (`alex.brand@socioboard.local`): in Enterprise Solutions Vertical, Healthcare Vertical, Education Sector — NOT in SMB Focus Group or Consumer Direct Channel
   - **John Smith** (`john.smith@socioboard.local`): in SMB Focus Group, Consumer Direct Channel — NOT in Enterprise Solutions Vertical, Healthcare Vertical, or Education Sector

4. **Four RSS feeds** submitted (≥4 POST /getRss entries after baseline)

5. **Four Q1 contaminator teams** remain completely unchanged:
   - `Q1: Brand Awareness`
   - `Q1: Product Launch Alpha`
   - `Q1: Retail Partnerships`
   - `Q1: Digital Outreach`

## What Makes This Hard

- Campaign code `COMPINT-Q2-2024` must appear verbatim in the bio (case-sensitive, hyphenated)
- 4 pre-existing Q1 teams must be recognized as off-limits (do not add users, do not delete)
- Two-user assignment is perfectly complementary — alex gets the enterprise/healthcare segments, john gets the consumer segments with zero overlap
- 5 new teams with long specific names must be created exactly
- Timezone is West Coast (America/Los_Angeles) — different from most other tasks
- 4 RSS feeds required

## Success Criteria

| Criterion | Weight | Verification |
|---|---|---|
| Profile first_name = Sophia | 4 pts | DB: user_details.first_name |
| Profile last_name = Chen | 4 pts | DB: user_details.last_name |
| COMPINT-Q2-2024 in bio | 8 pts | DB: user_details.about_me |
| timezone = America/Los_Angeles | 4 pts | DB: user_details.time_zone |
| phone contains 4155550233 | 4 pts | DB: user_details.phone_no |
| All 5 market teams | 30 pts (6 each) | DB: team_informations |
| alex.brand in 3 correct teams | 12 pts (4 each) | DB: join membership |
| alex.brand NOT in 2 excluded | 6 pts (3 each) | DB: absence check |
| john.smith in 2 correct teams | 8 pts (4 each) | DB: join membership |
| john.smith NOT in 3 excluded | 6 pts (2 each) | DB: absence check |
| ≥4 RSS feeds | 8 pts | Apache log count |
| Q1 contaminator teams untouched (4) | 6 pts (2+2+1+1) | DB: teams still exist |

**Pass threshold**: 60/100

## Verification Strategy

The contaminator team check uses SQL with escaped single quotes for the `Q1:` prefix:
```sql
SELECT COUNT(*) FROM team_informations WHERE team_name = 'Q1: Brand Awareness';
-- Expected: 1 (still exists, unchanged)
```

All membership and profile checks use the standard join patterns.

## Schema Reference

| Table | Key Columns |
|---|---|
| `user_details` | user_id, email, first_name, last_name, about_me, time_zone, phone_no |
| `team_informations` | team_id, team_name |
| `join_table_users_teams` | user_id, team_id |

## Pre-Seeded State

**Users pre-created**:
- `alex.brand@socioboard.local` — brand intelligence analyst (enterprise/healthcare focus)
- `john.smith@socioboard.local` — consumer segment manager (shared with other tasks)

**Q1 contaminator teams** (must NOT be modified):
- `Q1: Brand Awareness` (note: colon after Q1)
- `Q1: Product Launch Alpha`
- `Q1: Retail Partnerships`
- `Q1: Digital Outreach`

**Admin profile**: injected as Kevin Park, America/New_York

## Do-Nothing Score Analysis

- Profile: 0 pts (wrong values)
- 5 market teams don't exist: 0 pts
- All correct memberships: 0 pts
- "Not in excluded" (non-existent teams): ~12 pts (alex × 3pts × 2 + john × 2pts × 3 = 12)
- RSS: 0 pts
- Q1 contaminator teams exist: 6 pts
- **Total: ~18 pts → passed=False** ✓

## User Assignment Reference

| Team | alex.brand | john.smith |
|---|---|---|
| Enterprise Solutions Vertical | ✓ | ✗ |
| SMB Focus Group | ✗ | ✓ |
| Consumer Direct Channel | ✗ | ✓ |
| Healthcare Vertical | ✓ | ✗ |
| Education Sector | ✓ | ✗ |

## Edge Cases

- Q1 team names use `Q1: ` prefix with a colon — agent should not confuse with Q2 naming
- `COMPINT-Q2-2024` is the exact tracking code — no spaces, exact hyphenation
- alex.brand and john.smith assignments are complementary with zero overlap — any cross-assignment fails exclusion checks
- The 5 team names are long and specific — partial matches or abbreviations will fail exact DB comparisons
