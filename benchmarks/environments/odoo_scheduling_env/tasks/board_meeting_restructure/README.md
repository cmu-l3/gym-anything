# board_meeting_restructure

**Difficulty**: very_hard
**Occupation**: Senior Business Analyst, Finance

## Task Summary

The agent must postpone the 'Quarterly Business Review' by 1 week, add Karen Lee (Legal Counsel) as a QBR attendee, set an advance reminder on the QBR, and delete the now-redundant 'Budget Committee Meeting'.

## Feature Coverage

| Feature | Required |
|---------|----------|
| Reschedule an existing event | Yes |
| Add a specific attendee (discovered from Contacts) | Yes |
| Set email reminder/alarm | Yes |
| Delete an existing event | Yes |

## Setup Baseline

setup_task.sh:
- Records the original QBR start date in /tmp/qbr_original_start.txt
- Removes Karen Lee from QBR attendees (agent must find and re-add Legal Counsel)
- Removes all QBR alarms (agent must add reminder)
- Ensures 'Budget Committee Meeting' exists as the deletion target

## Verification Criteria

Scoring (pass threshold: 70/100):
- QBR date moved >= 5 days from original: **25 pts** (partial 10 pts for 1–4 days)
- Karen Lee added as QBR attendee: **25 pts**
- QBR has >= 1 alarm/reminder: **20 pts**
- 'Budget Committee Meeting' deleted: **30 pts**

## Partial Credit Design

- max_partial_total = 10 + 0 + 0 + 0 = 10
- Pass threshold = 70
- 10 < 70 ✓ (Anti-pattern 4 satisfied)
