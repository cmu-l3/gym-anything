# Task: spec_based_goals

## Overview

**Domain**: E-commerce Conversion Tracking
**Difficulty**: very_hard
**Occupation context**: Online Merchants — responsible for setting up conversion tracking to measure the effectiveness of their e-commerce funnel from product discovery through purchase completion.

## Goal

Read the conversion tracking specification at `/workspace/tasks/spec_based_goals/funnel_spec.txt` and implement all 4 conversion goals for the 'SportsFit Shop' site in Matomo.

## Required Goals (from spec document)

| Goal Name | Pattern Type | Pattern | Notes |
|-----------|-------------|---------|-------|
| Product Page View | contains | /products/ | Visit URL |
| Add to Cart | contains | /cart/add | Visit URL |
| Checkout Started | contains | /checkout | Visit URL |
| Purchase Confirmation | **exact** | /order/thank-you | Must be exact match |

## What Makes This Hard

- The agent must first read a specification document (file-reading step)
- Must correctly interpret 4 distinct goals with different URL patterns
- Goal 4 specifically requires exact URL matching (not "contains") — a subtle but important distinction
- Must navigate Matomo's goal configuration UI for each of 4 goals independently

## Success Criteria

| Criterion | Points |
|-----------|--------|
| 'Product Page View' goal: contains /products/ | 22 |
| 'Add to Cart' goal: contains /cart/add | 22 |
| 'Checkout Started' goal: contains /checkout | 22 |
| 'Purchase Confirmation' goal: exact /order/thank-you | 22 |
| All 4 created during task (anti-gaming) | 12 |
| **Total** | **100** |

**Pass threshold**: ≥70 points AND at least 1 goal newly created.

## Verification Strategy

- **Wrong-target gate**: Checks that goals were created for SportsFit Shop, not another site.
- Per-goal check: name (case-insensitive exact match), pattern_type (contains/exact), URL pattern.
- Pattern comparison strips leading slashes and normalizes case.

## Schema Reference

```sql
-- matomo_goal: idgoal, idsite, name, match_attribute, pattern_type, pattern, revenue, deleted
-- pattern_type values: 'contains', 'exact', 'regex'
-- match_attribute values: 'url', 'title', 'file', 'external_website', 'manually'
```
