# hr_performance_calibration

**Difficulty**: very_hard
**Occupation**: HR Business Partner, Corporate

## Task Summary

The agent must create a new recurring monthly 'Performance Review Calibration' event with HR leadership, CFO, and VP of Operations as attendees, write an agenda, and delete the 'Annual Performance Review - Frank Rivera' individual review that is being replaced.

## Feature Coverage

| Feature | Required |
|---------|----------|
| Create new event | Yes |
| Monthly recurrence | Yes |
| Multiple specific attendees (from Contacts) | Yes |
| Write meeting description/agenda | Yes |
| Delete an existing event | Yes |

## Setup Baseline

setup_task.sh:
- Removes any existing 'Performance Review Calibration' events
- Ensures 'Annual Performance Review - Frank Rivera' exists as the deletion target

## Verification Criteria

Scoring (pass threshold: 70/100):
- 'Performance Review Calibration' event exists: **15 pts**
- Event has monthly recurrence: **25 pts** (partial 10 pts for other recurrence)
- Frank Rivera in attendees: **10 pts**
- Grace Patel (CFO) in attendees: **10 pts**
- Henry Kim (VP Ops) in attendees: **10 pts**
- Description >= 20 characters: **10 pts** (partial 5 pts)
- 'Annual Performance Review - Frank Rivera' deleted: **20 pts**

## Partial Credit Design

- max_partial_total = 0 + 10 + 0 + 0 + 0 + 5 + 0 = 15
- Pass threshold = 70
- 15 < 70 ✓ (Anti-pattern 4 satisfied)
