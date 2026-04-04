# Task: fix_regional_sites

## Overview

**Domain**: E-commerce Analytics Configuration
**Difficulty**: very_hard
**Occupation context**: Online Merchants — these professionals rely on accurate currency and timezone configuration to correctly attribute revenue and calculate time-based metrics across international stores.

## Goal

Three pre-seeded regional e-commerce sites have been configured with wrong settings. Fix all three:

| Site | Correct Currency | Correct Timezone | Ecommerce |
|------|-----------------|-----------------|-----------|
| UK Fashion Store | GBP | Europe/London | enabled |
| German Auto Parts | EUR | Europe/Berlin | enabled |
| Tokyo Electronics | JPY | Asia/Tokyo | enabled |

**Do not modify the 'Initial Site'** (wrong-target gate — triggers score=0 if violated).

## End State

All three sites have correct currency, correct timezone, and ecommerce=1. Initial Site is unchanged.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| UK Fashion Store: currency=GBP | 10 |
| UK Fashion Store: timezone=Europe/London | 10 |
| UK Fashion Store: ecommerce=1 | 5 |
| German Auto Parts: currency=EUR | 10 |
| German Auto Parts: timezone=Europe/Berlin | 10 |
| German Auto Parts: ecommerce=1 | 5 |
| Tokyo Electronics: currency=JPY | 10 |
| Tokyo Electronics: timezone=Asia/Tokyo | 10 |
| Tokyo Electronics: ecommerce=1 | 5 |
| All three fully correct (bonus) | 25 |
| **Total** | **100** |

**Pass threshold**: ≥70 points AND Initial Site not modified (wrong-target gate).

## Verification Strategy

- **Wrong-target gate**: If Initial Site's currency, timezone, or ecommerce value changed from its baseline → score=0 immediately.
- Per-site checks against known correct values (currency codes, IANA timezone names, ecommerce flag).
- Bonus 25 pts if all three sites are completely correct.

## Schema Reference

```sql
-- matomo_site relevant columns:
-- idsite, name, currency, timezone, ecommerce (0 or 1)
```

## Notes

- Matomo currency codes follow ISO 4217 (GBP, EUR, JPY, USD, etc.).
- Matomo timezone names follow IANA tz database (e.g., Europe/London, Europe/Berlin, Asia/Tokyo).
- E-commerce is enabled per-site via Administration → Websites → Manage → Edit.
