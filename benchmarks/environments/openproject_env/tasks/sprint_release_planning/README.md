# Sprint Release Planning

## Domain Context
IT Project Manager for an e-commerce platform performing end-of-meeting sprint setup: creating a new sprint, moving work packages, updating statuses, logging time, and creating release notes.

**Occupation**: Information Technology Project Managers (O*NET importance: 88.0, GDP: $296.6M)
**Rationale**: Primary environment for tracking project tasks, agile sprints, bugs, and feature development in IT contexts.

## Task Overview
After a release planning meeting, the PM must operationalize the meeting decisions in OpenProject:
1. Create a new version "Sprint 4 - Payment Overhaul" with specific dates
2. Move two work packages into the new sprint
3. Change one WP's status to "In progress"
4. Log planning time on the WP
5. Create a wiki page documenting the sprint plan

## Starting State
- **Project**: ecommerce-platform
- **WP1**: "Fix broken checkout on mobile Safari" — New status, assigned to Sprint 1
- **WP2**: "Add wishlist feature" — assigned to Sprint 2
- No "Sprint 4 - Payment Overhaul" version exists
- No wiki page "Sprint 4 Release Notes" exists
- No time entries on WP1

## Success Criteria
The agent must complete all 6 subtasks. Verification is via Rails runner queries in `export_result.sh`:

| Criterion | Points | Check |
|-----------|--------|-------|
| Version exists with correct dates/status | 15 | Version name, start_date=2025-07-01, due_date=2025-07-31, status=open |
| WP1 moved to Sprint 4 | 15 | version_name matches |
| WP2 moved to Sprint 4 | 15 | version_name matches |
| WP1 status = "In progress" | 15 | status name check |
| Time logged (2h + comment) | 20 | count > baseline, hours ≈ 2.0, comment keyword match |
| Wiki page with content | 20 | page exists, content has sprint name + both WP references |

**Pass threshold**: 70/100

## Verification Strategy
- **Baseline recording**: Initial version count, initial time entry count, start timestamp
- **Anti-gaming**: Do-nothing gate checks that no new version was created
- **Multi-criterion**: 6 independent checks with partial credit
- **Specificity**: Exact version name, exact dates, keyword matching for comments/wiki

## Key Tables/Models
- `Version` (project, name, status, start_date, effective_date)
- `WorkPackage` (project, subject, status, version, assigned_to)
- `TimeEntry` (work_package_id, hours, comments)
- `WikiPage` (wiki → project, title, content)
