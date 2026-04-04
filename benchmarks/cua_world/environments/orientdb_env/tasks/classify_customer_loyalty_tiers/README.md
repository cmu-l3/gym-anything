# Classify Customer Loyalty Tiers

## Scenario
Customer success reported that no loyalty tier classification exists for a Q1 retention campaign. Order history lives in the graph (Orders vertices connected to Profiles via HasOrder edges), but there is no normalized tier layer. The campaign system cannot segment customers without it.

You are the database architect responsible for building the loyalty classification model in OrientDB.

## Occupation Grounding
- Product: `OrientDB`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)`
- Real workflow fit: designing and populating denormalized classification entities derived from relationship-aware graph traversal, as part of a CRM enrichment pipeline.

## Objective
In `demodb`, build a loyalty tier classification for four campaign customers:

**Cohort:** `yuki.tanaka@example.com`, `carlos.lopez@example.com`, `thomas.schafer@example.com`, `piet.vanderberg@example.com`

1. Create vertex class `LoyaltyTier` with the following mandatory properties:
   - `CustomerEmail` (STRING, mandatory)
   - `Tier` (STRING, mandatory) — values: `'Bronze'`, `'Silver'`, `'Gold'`
   - `TotalSpend` (DOUBLE, mandatory)
   - `CompletedOrderCount` (INTEGER, mandatory)

2. Create a `UNIQUE` index on `LoyaltyTier.CustomerEmail`.

3. For each cohort profile, traverse their `HasOrder` edges and aggregate:
   - `TotalSpend` = sum of `Price` across all their `Completed` orders
   - `CompletedOrderCount` = count of their `Completed` orders

4. Apply the tiering ruleset:
   - `Gold`:   `TotalSpend >= 4000`
   - `Silver`: `(CompletedOrderCount >= 2) OR (TotalSpend >= 1500 AND TotalSpend < 4000)`
   - `Bronze`: `CompletedOrderCount < 2 AND TotalSpend < 1500`

5. Insert one `LoyaltyTier` record per cohort profile.

## Expected Tier Assignment

| Email                          | TotalSpend | CompletedOrders | Expected Tier |
|-------------------------------|-----------|-----------------|---------------|
| yuki.tanaka@example.com        | 4500.00   | 2               | Gold          |
| carlos.lopez@example.com       | 900.00    | 1               | Bronze        |
| thomas.schafer@example.com     | 2000.00   | 2               | Silver        |
| piet.vanderberg@example.com    | 1700.00   | 1               | Silver        |

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Profiles(Email, Name, Surname, ...)`
- `Orders(OrderedId, Status, Price, Date)`
- `HasOrder` edge class (Profile → Orders)
- Target: `LoyaltyTier(CustomerEmail, Tier, TotalSpend, CompletedOrderCount)`

## Verification Strategy
- Reject wrong-target outcomes (emails not in the four-profile cohort).
- Verify `LoyaltyTier` schema with all four mandatory properties.
- Verify `UNIQUE` index on `CustomerEmail`.
- Verify tier assignment correctness and TotalSpend accuracy per profile.
- Baseline delta confirms new work was done.

## Edge Cases
- Cancelled orders must NOT count toward TotalSpend or CompletedOrderCount.
- Inserting a fifth email outside the cohort triggers wrong-target rejection.
- A row missing a mandatory field or with a wrong tier fails the payload check.

## Difficulty
`very_hard` — requires graph traversal aggregation, conditional tiering logic, schema creation with uniqueness constraints, and relationship-derived record construction.
