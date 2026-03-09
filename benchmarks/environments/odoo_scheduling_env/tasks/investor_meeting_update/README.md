# investor_meeting_update

**Difficulty**: very_hard
**Occupation**: CFO, Financial Services

## Task Summary

The agent must update the existing 'Investor Update Preparation' meeting in Odoo Calendar: add Karen Lee (Legal Counsel) as an attendee, update the location to the Board Room, write a meeting agenda in the description, and set an advance email reminder.

## Feature Coverage

| Feature | Required |
|---------|----------|
| Find and edit an existing event | Yes |
| Add a specific attendee (discovered from Contacts) | Yes |
| Update meeting location | Yes |
| Write meeting description/agenda | Yes |
| Set email reminder/alarm | Yes |

## Setup Baseline

setup_task.sh resets the 'Investor Update Preparation' event by:
- Removing Karen Lee from attendees
- Clearing the description
- Setting location to 'Zoom Meeting' (agent must change to Board Room)
- Removing all alarms

## Verification Criteria

Scoring (pass threshold: 70/100):
- Karen Lee added as attendee: **30 pts**
- Location contains 'board' (case-insensitive): **20 pts**
- Description >= 20 characters: **25 pts** (partial 10 pts for very short)
- At least 1 alarm/reminder: **25 pts**

## Partial Credit Design

- max_partial_total = 0 + 0 + 10 + 0 = 10
- Pass threshold = 70
- 10 < 70 ✓ (Anti-pattern 4 satisfied)
