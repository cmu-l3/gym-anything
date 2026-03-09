# Defect Triage and Escalation

## Domain Context
QA Analyst performing critical defect triage after a production incident, escalating priorities, adding incident comments, creating emergency work packages, and documenting the incident.

**Occupation**: Software Quality Assurance Analysts and Testers (O*NET importance: 99.0, GDP: $156M)
**Rationale**: Reporting bugs, tracking defects, and managing workflows are fundamental to the QA role.

## Task Overview
Two bugs have been confirmed as critical: a production pagination bug and a security vulnerability. The QA analyst must:
1. Escalate pagination bug priority to Immediate
2. Change pagination bug status to In progress
3. Add production incident comment to pagination bug
4. Escalate JWT audit priority to High + add security comment
5. Create an emergency bug WP for token invalidation
6. Create a wiki incident report page

## Starting State
- **Pagination bug WP**: New, Normal priority, assigned to alice.johnson
- **JWT audit WP**: In progress, Normal priority, assigned to carol.williams
- No "Emergency: Token invalidation on user logout" WP exists
- No "Incident Report - Transaction History" wiki page exists

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Pagination bug priority → Immediate | 12 | Priority name (Urgent/High accepted with partial credit) |
| Pagination bug status → In progress | 10 | Status name check |
| Comment on pagination bug about incident | 15 | Keywords: production, escalated/P0, customer/support |
| JWT audit priority → High + comment | 18 | Priority + vulnerability/JWT/logout keywords in notes |
| Emergency bug WP created | 25 | Subject, type=Bug, assignee=carol, version=Sprint 1, priority=Urgent, description |
| Wiki incident report | 20 | Page exists + pagination/production/customer/escalation/remediation keywords |

**Pass threshold**: 65/100

## Verification Strategy
- **Baseline recording**: Initial WP count in mobile-banking-app
- **Anti-gaming**: Checks both WP modifications and emergency WP creation
- **Multi-criterion**: 6 independent checks with partial credit per attribute
- **Priority escalation**: Tests understanding of priority hierarchy (Normal → High → Urgent → Immediate)

## Key Tables/Models
- `WorkPackage` (subject, status, priority, assigned_to, version, type, journals/notes)
- `IssuePriority` (name: Normal, High, Urgent, Immediate)
- `Type` (name: Bug, Task, Feature)
- `WikiPage` (wiki → project, title, content)
