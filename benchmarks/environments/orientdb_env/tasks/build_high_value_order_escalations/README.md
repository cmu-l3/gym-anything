# Build High-Value Order Escalation Queue

## Scenario
Revenue operations reported that unresolved high-value bookings are no longer being escalated after a pipeline migration. The graph has order records but no normalized escalation layer.

You are the database architect responsible for rebuilding this escalation model in OrientDB.

## Occupation Grounding
- Product: `OrientDB`
- Source context from `task_creation_notes`: `Cloud database services`, `Database System`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)`
- Real workflow fit: designing durable escalation entities and relationship-aware incident pipelines for revenue operations.

## Objective
In `demodb`, implement a high-value pending-order escalation pipeline:

1. Create vertex class `OrderEscalation` with properties:
   - `OrderedId` (INTEGER, mandatory)
   - `EscalationTier` (STRING, mandatory)
   - `Reason` (STRING, mandatory)
   - `OwnerEmail` (STRING, mandatory)
   - `SnapshotPrice` (DOUBLE, mandatory)
2. Create a `UNIQUE` index on `OrderEscalation.OrderedId`.
3. Create edge class `EscalatesOrder`.
4. Insert escalation records only for orders with:
   - `Status = 'Pending'`
   - `Price >= 1800`
5. Tiering rule:
   - `P1` when `Price >= 3000`
   - `P2` otherwise
6. Set `Reason = 'pending_high_value'`.
7. Set `OwnerEmail` to the profile email that owns the order via `HasOrder`.
8. For each escalation record, create `EscalatesOrder` edge from `OrderEscalation` -> `Orders`.

Expected escalation scope after remediation:
- `OrderedId=3` -> Tier `P2`, Owner `anna.mueller@example.com`
- `OrderedId=7` -> Tier `P1`, Owner `james.brown@example.com`

No escalation should exist for `OrderedId=10`.

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Orders(OrderedId, Status, Price, Date)`
- `Profiles(Email, ...)`
- `HasOrder` edge class
- `OrderEscalation(OrderedId, EscalationTier, Reason, OwnerEmail, SnapshotPrice)`
- `EscalatesOrder` edge class

## Verification Strategy
- Reject wrong-target outcomes if any escalation is created for non-target orders.
- Verify escalation schema and mandatory-field requirements.
- Verify `UNIQUE` index hardening on `OrderEscalation.OrderedId`.
- Verify payload correctness for each expected escalated order.
- Verify `EscalatesOrder` edges map each escalation to the correct source order.

## Edge Cases
- Escalating completed orders should fail.
- Wrong owner-email attribution should fail.
- Correct escalation rows without graph edges should fail.

## Difficulty
`very_hard` — requires schema hardening, indexing, relationship-aware record construction, and scoped incident remediation.
