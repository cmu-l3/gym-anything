# weekly_ops_review_setup

**Difficulty**: very_hard
**Occupation**: VP of Operations, Professional Services

## Task Summary

The agent must set up a recurring weekly 'Operations Weekly Review' meeting in Odoo Calendar with senior leadership as attendees and an email reminder configured.

## Feature Coverage

| Feature | Required |
|---------|----------|
| Create new event | Yes |
| Weekly recurrence | Yes |
| Multiple attendees (>= 3 Northbridge contacts) | Yes |
| Email reminder/alarm | Yes |

## Verification Criteria

Scoring (pass threshold: 70/100):
- Event named 'Operations Weekly Review' exists: **20 pts**
- Event has weekly recurrence: **25 pts** (partial 10 pts for any recurrence)
- Event has >= 3 Northbridge attendees: **30 pts** (partial 10 pts for 1–2 attendees)
- Event has >= 1 alarm/reminder: **25 pts**

## Agent Challenge

This is very_hard because the agent must:
1. Navigate to create a new event in Odoo Calendar
2. Look up Northbridge senior leadership in Contacts to find who to invite
3. Configure the weekly recurrence (Recurrence checkbox + Weekly frequency)
4. Set an email reminder via the Reminders section

## Partial Credit Design

- max_partial_total (if each criterion scores only partial) = 10 + 10 + 10 + 0 = 30
- Pass threshold = 70
- 30 < 70 ✓ (Anti-pattern 4 satisfied)
