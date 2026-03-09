# Project Retrospective Documentation

## Domain Context
Software Developer leading an end-of-sprint retrospective: closing completed work with performance data, documenting carry-over items, logging review time, creating the next sprint, and writing a structured retrospective wiki page.

**Occupation**: Software Developers (O*NET importance: 90.0, GDP: $282.3M)
**Rationale**: Management of bugs, feature requests, and sprint tasks.

## Task Overview
Sprint 1 is wrapping up for ecommerce-platform. The developer must:
1. Close the DB optimization WP with a verification comment including performance metrics
2. Add a carry-over comment to the search WP with completion percentage
3. Log 4 hours of retrospective time on the search WP
4. Create "Sprint 2 - Performance & Search" version with dates
5. Move the search WP to the new sprint
6. Create a structured retrospective wiki page

## Starting State
- **DB optimization WP**: Closed status, no verification comment
- **Search WP**: In progress, assigned to Sprint 1, no time entries, no carry-over comments
- No "Sprint 2 - Performance & Search" version exists
- No "Sprint 1 Retrospective" wiki page exists

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| DB optimization WP closed + verification comment | 15 | Status + verified/production/N+1/performance keywords |
| Search WP carry-over comment | 12 | Keywords: carry/sprint 2/70%/facet or filter |
| Time logged on search WP (4h + comment) | 13 | Count > baseline, hours ≈ 4.0, retrospective keyword |
| New version created with correct dates | 15 | Name, status=open, start=2025-08-01, due=2025-08-31 |
| Search WP moved to new version | 15 | Version name matches |
| Wiki retrospective page | 30 | Page exists + went well/challenges/database/search/estimation/action items |

**Pass threshold**: 65/100

## Verification Strategy
- **Baseline recording**: Initial version count, initial time entries on search WP
- **Anti-gaming**: Do-nothing gate checks that no new version created and no wiki exists
- **Multi-criterion**: 6 independent checks with content analysis via keyword matching
- **Professional workflow**: Tests structured documentation with specific data points (performance metrics, completion percentages)

## Key Tables/Models
- `Version` (project, name, status, start_date, effective_date)
- `WorkPackage` (subject, status, version, journals/notes)
- `TimeEntry` (work_package_id, hours, comments)
- `WikiPage` (wiki → project, title, content with structured sections)
