# Team Workload Rebalancing

## Domain Context
IT Project Manager conducting a mid-sprint workload review, redistributing work packages among team members based on capacity analysis, logging review time, and documenting decisions.

**Occupation**: Information Technology Project Managers (O*NET importance: 88.0, GDP: $296.6M)
**Rationale**: Primary environment for tracking project tasks, agile sprints, bugs, and feature development in IT contexts.

## Task Overview
Carol is overloaded with 2 tasks while Bob has completed his work. The PM must:
1. Reassign SSL cert task from Carol to Bob
2. Change SSL cert status to "In progress"
3. Log review time on K8s autoscaling WP
4. Create a capacity planning review WP
5. Add a workload review comment to blue-green WP
6. Create a wiki page documenting the workload review

## Starting State
- **SSL cert WP**: New, assigned to carol.williams
- **K8s autoscaling WP**: In progress, assigned to carol.williams, no time entries
- **Blue-green WP**: New, assigned to alice.johnson, no workload comments
- No "Sprint capacity planning review" WP exists
- No "Sprint Workload Review" wiki page exists

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| SSL cert reassigned to bob.smith | 15 | Assignee login check |
| SSL cert status → In progress | 10 | Status name check |
| Time logged on K8s WP (1.5h + comment) | 15 | Count > baseline, hours ≈ 1.5, comment keywords |
| Capacity planning WP created | 20 | Subject, type=Task, assignee=alice, version=Sprint 2, description |
| Comment on blue-green WP | 15 | Keywords: workload, priority, alice, sprint |
| Wiki page with review documentation | 25 | Page exists + SSL/carol/bob/reassign/overload keywords |

**Pass threshold**: 65/100

## Verification Strategy
- **Baseline recording**: Initial WP count, initial time entries on K8s WP
- **Anti-gaming**: Checks both SSL modifications and capacity WP creation
- **Multi-criterion**: 6 independent checks with keyword-based content validation
- **Judgment-adjacent**: Task requires understanding team capacity and making reassignment decisions

## Key Tables/Models
- `WorkPackage` (subject, status, assigned_to, version, journals/notes)
- `TimeEntry` (work_package_id, hours, comments)
- `WikiPage` (wiki → project, title, content)
- `User` (login: alice.johnson, bob.smith, carol.williams)
