# Task: custom_dimensions_setup

## Overview

**Domain**: Research Analytics / Custom Tracking
**Difficulty**: very_hard
**Occupation context**: Market Research Analysts — these professionals extend Matomo's default tracking schema with custom dimensions to capture domain-specific user attributes and behavioral signals that standard analytics cannot capture.

## Goal

Configure five custom dimensions for the 'Research Platform' site:

| Name | Scope | Active |
|------|-------|--------|
| Subscription Tier | visit | yes |
| User Cohort | visit | yes |
| Traffic Source Detail | visit | yes |
| Page Category | action | yes |
| Form Interaction | action | yes |

## End State

All five dimensions exist in `matomo_custom_dimension` with `active=1` for the Research Platform site.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| 'Subscription Tier' (visit-scope, active) | 18 |
| 'User Cohort' (visit-scope, active) | 18 |
| 'Traffic Source Detail' (visit-scope, active) | 18 |
| 'Page Category' (action-scope, active) | 18 |
| 'Form Interaction' (action-scope, active) | 18 |
| All 5 active (bonus verification) | 10 |
| **Total** | **100** |

**Pass threshold**: ≥70 points AND at least one new dimension was created during task.

## Verification Strategy

- Wrong-target gate: If no new dimensions were created during the task window → score=0.
- Per-dimension check: name (case-insensitive), scope (visit or action), active=1.
- Bonus 10 pts if all 5 found and all are active.

## Schema Reference

```sql
-- matomo_custom_dimension:
-- idcustomdimension, idsite, index, scope ('visit' or 'action'),
-- name, active (0 or 1), extractions, case_sensitive
```

## Notes

- Custom Dimensions is a free Matomo plugin (included in default install).
- Accessible via Administration → Custom Dimensions.
- Matomo limits the number of slots per scope (default 5 visit-scope, 5 action-scope).
- The `index` column is the slot number (1–5) — exact slot number is not verified.
