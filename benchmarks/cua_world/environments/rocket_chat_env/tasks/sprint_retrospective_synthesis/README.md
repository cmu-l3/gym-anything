# Sprint Retrospective Synthesis

## Occupation Context
**Software Developer / Scrum Master** at a SaaS company.
End of Q1 2026 sprint cycle -- the scrum master must synthesize feedback from 3 team retrospective channels into actionable cross-team outcomes.

## Task Overview
Three engineering teams (Alpha, Beta, Gamma) have posted their retrospective feedback in dedicated Rocket.Chat channels. The agent must read all feedback, identify cross-cutting themes, create a unified action items channel, post synthesized findings, and communicate summaries to engineering leadership.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- Three retro channels exist with seeded feedback:
  - `#retro-team-alpha` (4 messages: CI/CD wins, code review delays, regression suite, trunk-based dev)
  - `#retro-team-beta` (5 messages: analytics dashboard, design handoff, alert fatigue, monitoring, pair programming)
  - `#retro-team-gamma` (5 messages: API performance, cross-team dependencies, code review delays, API contracts, UX improvements)
- Users created: `eng.director`, `alpha.lead`, `beta.lead`, `gamma.lead`, `product.manager`, `ux.researcher`
- No `q1-retro-action-items` channel exists yet
- Baseline recorded: existing groups/channels

## Goal / End State
1. Public channel `q1-retro-action-items` exists with correct topic
2. Required members invited (`eng.director`, `alpha.lead`, `beta.lead`, `gamma.lead`, `product.manager`)
3. Synthesized summary posted identifying cross-cutting themes (e.g., code review delays across Alpha and Gamma)
4. Action items message with >= 3 items and owner assignments
5. Action items message pinned
6. DM sent to `eng.director` with executive summary
7. Confirmation messages posted in all three retro channels

## Verification Strategy (10 criteria, 100 points, pass >= 70)

| ID  | Points | Criterion |
|-----|--------|-----------|
| C1  | 8      | Public channel `q1-retro-action-items` exists (4 if private) |
| C2  | 8      | Topic contains "Q1" + "retro" + "action" (case-insensitive) |
| C3  | 12     | Required members invited (partial credit per member) |
| C4  | 15     | Synthesized summary with cross-cutting themes (code review + team/cross-team ref) |
| C5  | 15     | Action items message with >= 3 items AND owner assignments |
| C6  | 7      | Action items message is pinned |
| C7  | 10     | DM to eng.director about retrospective/cross-team issues |
| C8  | 8      | Confirmation message in #retro-team-alpha |
| C9  | 8      | Confirmation message in #retro-team-beta |
| C10 | 9      | Confirmation message in #retro-team-gamma |

### Do-nothing gate
If no action items channel exists and no DMs or confirmation messages created, score = 0.

### Anti-gaming
- Seeded messages are posted as admin; confirmation messages must contain relevant keywords (captured, action item, feedback, etc.)
- Cross-cutting theme detection requires both code-review keywords and team/cross-team references
- Action items require structured list format (numbered/bulleted) with owner name mentions
- DM content checked for retrospective/sprint-related keywords

## Features Exercised
Create public channel, set topic, invite members, post messages, pin message, send DM, post in existing channels (7 distinct features)

## Data Sources
- Retrospective messages follow real sprint retro formats (What went well / What didn't / Action needed)
- Users represent real scrum/engineering roles (Team Leads, Engineering Director, Product Manager, UX Researcher)
- Cross-cutting themes are intentionally seeded: code review delays (Alpha + Gamma), cross-team dependencies (Beta + Gamma)
