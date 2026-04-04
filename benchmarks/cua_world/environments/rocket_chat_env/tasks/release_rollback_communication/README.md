# Release Rollback Communication

## Occupation Context
**Software Developer / Release Manager** (SOC importance: 90.0)
Critical for agile team communication, release coordination, and rollback procedures.

## Task Overview
Release 8.0.2 has a critical regression in the payment processing module. The agent must coordinate a rollback to version 7.8.5 across Rocket.Chat using 10 distinct communication features.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- `#release-updates` channel exists with real GitHub release data (seeded by `seed_rocket_chat.py` from `rocketchat_releases_github_api_2026-02-16.json`)
- Release messages for 7.8.5 and 8.0.2 exist with recorded message IDs
- Users created: `qa.lead`, `devops.engineer`, `product.manager`
- No rollback channel exists
- No announcement on `#release-updates`
- Admin status is clear

## Goal / End State
1. Release 7.8.5 message starred
2. Release 8.0.2 message reacted with :warning: emoji
3. `rollback-8-0-2-coordination` channel created with description
4. Team members invited (`qa.lead`, `devops.engineer`, `product.manager`)
5. Rollback plan posted with version numbers, reason, and verification steps
6. Rollback plan pinned
7. DM to `devops.engineer` with rollback instructions
8. Announcement set on `#release-updates`
9. Admin status text changed to rollback coordination notice

## Verification Strategy (10 criteria, 100 points, pass >= 70)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 8 | 7.8.5 message starred |
| C2 | 8 | 8.0.2 reacted with :warning: (4 if wrong emoji) |
| C3 | 10 | Rollback channel exists |
| C4 | 10 | Channel description mentions rollback + payment/regression |
| C5 | 12 | Members invited (4 pts each) |
| C6 | 15 | Rollback plan with versions, reason, and 3+ verification steps |
| C7 | 7 | Rollback plan pinned |
| C8 | 10 | DM to devops.engineer with deployment instructions |
| C9 | 10 | Release-updates announcement about rollback |
| C10 | 10 | Admin status text about rollback |

### Do-nothing gate
If no rollback channel and no starred/reacted messages, score = 0.

### Anti-gaming
- Starred/reacted messages verified against specific message IDs from seed manifest
- Rollback plan must mention both version numbers (8.0.2, 7.8.5) and reason
- Announcement and status text checked for rollback-specific keywords

## Features Exercised
Star message, react with emoji, create public channel, set description, invite members, post messages, pin message, send DM, set channel announcement, set user status (10 distinct features)

## Data Sources
- Release data from real Rocket.Chat GitHub API responses (`rocketchat_releases_github_api_2026-02-16.json`)
- Seed manifest at `/tmp/rocket_chat_seed_manifest.json` provides message IDs
