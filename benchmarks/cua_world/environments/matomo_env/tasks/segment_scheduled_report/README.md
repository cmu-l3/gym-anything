# Task: segment_scheduled_report

## Overview

**Domain**: Search Marketing Analytics
**Difficulty**: very_hard
**Occupation context**: Search Marketing Strategists — these professionals use Matomo to isolate specific audience subsets for campaign performance analysis, particularly distinguishing organic vs paid traffic on mobile vs desktop.

## Goal

Set up a complete mobile-organic-search monitoring pipeline in Matomo:

1. **Create a custom visitor segment** capturing users who arrive via organic search channels on mobile devices (both conditions required simultaneously).
2. **Schedule a weekly email report** using this segment, delivered every Monday to `analytics@marketingteam.test`.

## End State

- A new segment exists in Matomo's segment manager with conditions filtering for mobile device type AND organic search referral type.
- A new scheduled email report exists with `period=week`, linked to the segment above, with `analytics@marketingteam.test` as a recipient.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| New segment created during task | 20 |
| Segment definition includes device-type condition | 15 |
| Segment definition includes organic/search referral condition | 15 |
| Report scheduled weekly (period=week) | 20 |
| Report email recipient is analytics@marketingteam.test | 20 |
| Report is linked to the segment (idsegment set) | 10 |
| **Total** | **100** |

**Pass threshold**: ≥70 points AND segment created during task.

## Verification Strategy

All checks are via `matomo_segment` and `matomo_report` DB tables plus the exported JSON.

- **Wrong-target gate**: If no new segment was created during the task window, score=0.
- **Segment condition check**: Looks for `deviceType` or `device` keyword AND `referrerType` or `search` keyword in the segment definition.
- **Report email check**: Looks for `analytics@marketingteam.test` anywhere in the `parameters` JSON column.
- **Report-segment link**: Verifies `matomo_report.idsegment` references the new segment.

## Schema Reference

```sql
-- matomo_segment
-- idsegment, name, definition, login, enable_all_users, enable_only_idsite,
-- auto_archive, ts_created, ts_last_edit, deleted

-- matomo_report
-- idreport, idsite, login, description, idsegment, period, hour,
-- type, parameters, ts_created, ts_last_sent, deleted
```

## Notes

- The segment definition uses Matomo's segment API syntax (e.g., `deviceType==smartphone,deviceType==tablet;referrerType==search`).
- "Mobile" can mean smartphone or tablet — both are valid.
- The `parameters` column in `matomo_report` is a JSON blob containing email addresses and report configuration.
