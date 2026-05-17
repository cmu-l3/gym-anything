# restructure_division_merger

**Difficulty:** very_hard  
**Timeout:** 720 s / 90 steps  
**Reward type:** sparse

## Domain context

HR Managers and HR Business Partners routinely handle division consolidations when a business unit is dissolved and its headcount is absorbed into a surviving team. The task mirrors a common quarter-end reorganisation: a separate project division is being merged into Research & Development, requiring personnel re-assignment, job-title corrections, coaching-relationship setup, departmental leadership appointment, and archival of the now-defunct division.

Real practitioners consult an internal announcement (here: a chatter note on the R&D department record) that specifies the exact reassignments, then execute the changes across the Employees and Departments modules.

## Goal (end state)

- Three employees currently assigned to the Long Term Projects department must be transferred to Research & Development with the correct new job positions.
- One of those three is designated as coach for a colleague — this must be reflected in the employee record.
- Ronnie Hart must be set as the R&D Department Manager.
- The Long Term Projects department must be archived.

The exact assignments are encoded in a note posted to the R&D department's chatter log; the agent must discover and read that note.

## Success criteria

| Criterion | Points |
|-----------|--------|
| C1: All three employees in R&D (10 pts each) | 30 |
| C2: Correct new job titles — Senior Developer (Ernest), Project Lead (Randall) | 20 |
| C3: Paul Williams has Ernest Reed set as his Coach | 15 |
| C4: Ronnie Hart is R&D Department Manager | 20 |
| C5: Long Term Projects department archived | 15 |
| **Pass threshold** | **≥ 60** |

## Verification strategy

`export_result.sh` reads via XML-RPC:
- `hr.employee` records for Ernest Reed, Paul Williams, Randall Lewis — checks `department_id`, `job_id`, `coach_id`
- `hr.department` R&D record — checks `manager_id`
- `hr.department` LTP record (with `active_test: False`) — checks `active`

Ground truth IDs written to `/tmp/restructure_merger_gt.json` by setup.

## Data notes

Uses Odoo demo employees (Ernest Reed, Paul Williams, Randall Lewis, Ronnie Hart) and existing departments (R&D, Long Term Projects, Management). Job positions Senior Developer, Developer, Project Lead are created by setup if absent. The restructuring plan is posted as a chatter note — no external files required.

## Edge cases

- Setup posts the memo fresh on each run (removes previous to avoid duplicates).
- If the LTP department does not exist, setup creates it — verifier uses the ID from gt.
- Agent must locate the chatter note without being told where to look.
