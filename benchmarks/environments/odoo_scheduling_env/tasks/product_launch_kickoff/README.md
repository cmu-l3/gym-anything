# product_launch_kickoff

**Difficulty**: very_hard
**Occupation**: Product Manager, Technology

## Task Summary

The agent must create a new 'Product Launch Kickoff' meeting with engineering and marketing team members, set in the Engineering Lab with an agenda, AND delete the superseded 'Sprint Planning - Engineering' meeting.

## Feature Coverage

| Feature | Required |
|---------|----------|
| Create new event | Yes |
| Add multiple attendees (discovered from Contacts) | Yes |
| Set meeting location | Yes |
| Write meeting description/agenda | Yes |
| Delete an existing event | Yes |

## Setup Baseline

setup_task.sh:
- Removes any existing 'Product Launch Kickoff' events
- Ensures 'Sprint Planning - Engineering' exists as the deletion target

## Verification Criteria

Scoring (pass threshold: 70/100):
- 'Product Launch Kickoff' event created: **20 pts**
- Event has >= 3 attendees: **25 pts** (partial 10 pts for 1–2 attendees)
- Location contains 'engineering' (case-insensitive): **20 pts**
- Description >= 20 characters: **10 pts** (partial 5 pts)
- 'Sprint Planning - Engineering' deleted: **25 pts**

## Partial Credit Design

- max_partial_total = 0 + 10 + 0 + 5 + 0 = 15
- Pass threshold = 70
- 15 < 70 ✓ (Anti-pattern 4 satisfied)
