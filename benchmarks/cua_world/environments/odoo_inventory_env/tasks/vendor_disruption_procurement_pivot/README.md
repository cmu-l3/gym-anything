# Vendor Disruption Procurement Pivot — Force Majeure Response

**Environment**: odoo_inventory_env
**Difficulty**: very_hard
**Occupation**: Strategic Procurement Manager
**Industry**: Aerospace Parts Distribution

## Scenario

A primary aerospace parts vendor, "Precision Aeroparts Inc.", has declared force majeure, suspending all pending orders indefinitely. The procurement manager must respond by identifying all affected purchase orders, cancelling them, sourcing replacement orders from qualified backup suppliers already in the procurement database, confirming the new orders, and updating automated reorder rules to prevent future orders from routing to the disrupted vendor.

The system tracks 10 aerospace products across 3 vendors. Four products have pending POs from the disrupted vendor that must be cancelled and recreated with backup vendors. Two other products have confirmed POs from unaffected vendors that must not be touched. The remaining four products have no pending POs.

This is a very_hard task: the agent must navigate Odoo's purchasing module, read vendor internal notes to identify the disrupted supplier, trace affected POs, determine correct backup vendors from the supplier pricelist, and execute a multi-step procurement pivot without disturbing unrelated orders.

## Task Difficulty Justification (very_hard)

The description provides only the business context. The agent must independently:
1. Navigate to vendor records and identify the disrupted supplier via internal notes
2. Find all pending POs associated with the disrupted vendor
3. Cancel each affected PO (handling both draft and sent states)
4. Identify the correct backup vendor for each product from supplier pricelists
5. Create new POs with backup vendors matching original quantities
6. Confirm all new POs
7. Update reorder rules so automated replenishment uses backup vendors
8. Avoid modifying or cancelling POs from unaffected vendors (anti-gaming)

## Scoring

| Criterion | Points | Notes |
|-----------|--------|-------|
| All 4 affected POs cancelled | 15 | POs from Precision Aeroparts in cancel state |
| New POs with correct backup vendors (6.25 each) | 25 | Must use SkyTech for 001/002, AeroAlloy for 003/004 |
| New PO quantities match originals (25, 40, 15, 100) | 10 | Within 10% tolerance |
| New POs confirmed (state='purchase') | 15 | Not left in draft |
| Correct backup vendor per product | 10 | Vendor selection awareness |
| Reorder rules updated to backup vendor | 10 | Supplier priority or removal of disrupted vendor |
| Anti-gaming: unaffected POs untouched | 15 | Caps score at 55 if violated |
| **Total max** | **100** | |
| **Pass threshold** | **80** | |

### Strategy Enumeration (Anti-Gaming Validation)

| Strategy | Score | Passes? |
|----------|-------|---------|
| Do nothing | 0+0+0+0+0+0+15 = 15 | No |
| Cancel all POs (including protected) | 15+0+0+0+0+0+0 (capped at 55) | No |
| Cancel affected only, no new POs | 15+0+0+0+0+0+15 = 30 | No |
| Cancel + recreate but wrong vendors | 15+0+0+15+0+0+15 = 45 | No |
| Correct: cancel affected, recreate with backups, confirm, update rules | 15+25+10+15+10+10+15 = 100 | Yes |

## Feature Matrix

| Feature | Used |
|---------|------|
| Vendor record analysis (internal notes) | Yes |
| Purchase order management (cancel/create/confirm) | Yes |
| Supplier pricelist navigation | Yes |
| Reorder rule configuration | Yes |
| Multi-vendor procurement strategy | Yes |
| Anti-gaming protection (protected POs) | Yes |
