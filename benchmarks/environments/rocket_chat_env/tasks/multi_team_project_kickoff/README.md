# Multi-Team Project Kickoff

## Occupation Context
**IT Project Manager** (SOC importance: 88.0)
Essential for continuous coordination with development teams and stakeholders, setting up project workspaces for cross-functional teams.

## Task Overview
The agent must set up a complete Rocket.Chat workspace for the "Phoenix Migration" cloud infrastructure project: a private main channel, three public sub-channels for frontend/backend/devops teams, with role-based member assignment, a project charter, and team-specific sprint planning messages.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- Users created: `fe.lead`, `be.lead`, `qa.tester`, `ux.designer`, `pm.coordinator`, `devops.lead`
- No phoenix-* channels exist (cleaned up in setup)
- Baseline: existing channels/groups recorded

## Goal / End State
1. Private channel `phoenix-migration` exists with correct topic and description
2. Three public sub-channels: `phoenix-frontend`, `phoenix-backend`, `phoenix-devops`
3. All 6 team members in main channel; role-based members in sub-channels
4. Project charter posted and pinned in main channel
5. Team-specific sprint planning messages in each sub-channel
6. DM to `pm.coordinator` about project tracking

## Verification Strategy (10 criteria, 100 points, pass >= 70)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 10 | Main channel exists as private (5 if public) |
| C2 | 8 | Topic/description with cloud/migration/Q1-Q2/2026 keywords |
| C3 | 10 | All 3 sub-channels exist (bonus for all 3) |
| C4 | 15 | All 6 members in main channel |
| C5 | 12 | Correct role-based members in sub-channels |
| C6 | 12 | Project charter with name/timeline/objective/team |
| C7 | 7 | Charter pinned |
| C8 | 12 | Sprint planning messages in all 3 sub-channels |
| C9 | 7 | Team-specific content (UI/API/CI-CD keywords) |
| C10 | 7 | DM to pm.coordinator about project tracking |

### Do-nothing gate
If no project channels created, score = 0.

### Anti-gaming
- Main channel type verified (private vs public)
- Sub-channel members checked against role-based expectations
- Charter message checked for specific project details (not just generic text)
- Sprint messages checked for team-appropriate keywords

## Features Exercised
Create private channel, create public channels, set topic, set description, invite members (role-based), post messages, pin message, send DM (8 distinct features)

## Data Sources
- Project roles follow real cross-functional agile team structure
- Channel naming follows real project workspace conventions
