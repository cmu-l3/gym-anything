# merger_workspace_consolidation

**Difficulty:** very_hard
**Occupation:** Records Manager
**Industry:** Technology / Corporate

## Overview

Following a corporate merger, a records manager must restructure the document management system to consolidate two legacy division workspaces (Alpha Division and Beta Division) into a unified organizational structure as defined in the Merger Integration Plan.

## Setup State

The `setup_task.sh` script:
1. Creates `Alpha Division` workspace with two documents:
   - `Alpha Strategic Project Plan` (project plan → goes to Product Development)
   - `Alpha Division Budget Report FY2025` (financial → goes to Corporate Services)
2. Creates `Beta Division` workspace with two documents:
   - `Beta Product Roadmap 2025` (roadmap → goes to Product Development)
   - `Beta Division Quarterly Metrics Q3 2025` (metrics → goes to Corporate Services, has empty description)
3. Creates user groups: `alpha-team` (members: acohen, jsmith) and `beta-team` (members: mgarcia, tchen)
4. Creates `Merger Integration Plan` Note at workspace level (the reference doc the agent must read)
5. Opens Firefox on the Nuxeo home page

## Agent Goal

1. Read the `Merger Integration Plan` to learn the target structure
2. Create `Integrated Operations` workspace under `/default-domain/workspaces/`
3. Create `Product Development` and `Corporate Services` sub-workspaces under it
4. Move or recreate project/roadmap docs into Product Development
5. Move or recreate financial/metrics docs into Corporate Services
6. Ensure all migrated documents have descriptions ≥ 20 characters
7. Create `integrated-team` group containing all members from alpha-team and beta-team
8. Grant `integrated-team` ReadWrite access on the Integrated Operations workspace

## Verification Criteria

| Criterion | Points |
|-----------|--------|
| Integrated Operations workspace exists | 10 pts |
| Product Development sub-workspace exists | 8 pts |
| Corporate Services sub-workspace exists | 8 pts |
| Project/roadmap docs in Product Development | 12 pts |
| Budget/metrics docs in Corporate Services | 12 pts |
| All migrated docs have description ≥ 20 chars | 10 pts |
| integrated-team group created | 10 pts |
| integrated-team has all 4 expected members | 15 pts |
| integrated-team has ReadWrite on Integrated Operations | 15 pts |
| **Total** | **100 pts** |

**Pass threshold:** 60/100

## Features Tested

- Workspace creation
- Document creation / move
- Metadata editing (dc:description)
- Permissions / ACL (`@op/Document.AddACE`)
- User group management (`/group/` API)

## Notes

- The agent may either move existing documents or recreate them in the new workspace. The verifier checks by title keywords, so either approach works.
- The Merger Integration Plan is the sole reference; the agent must read it to discover the target workspace names.
- Legacy Alpha Division and Beta Division workspaces may remain as archives.
