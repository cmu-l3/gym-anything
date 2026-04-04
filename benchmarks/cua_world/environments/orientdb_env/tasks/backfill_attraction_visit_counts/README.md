# Backfill Attraction Visit Counts

## Scenario
Tourism analytics discovered that attraction records lack a denormalized `VisitCount` property required by the new ranked-query API. `HasVisited` edges are the authoritative source of visit data. Attractions are split across three subclasses (`ArchaeologicalSites`, `Castles`, `Monuments`) all extending the base `Attractions` class.

You are the database architect responsible for backfilling the visit count property and creating an audit trail.

## Occupation Grounding
- Product: `OrientDB`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)`
- Real workflow fit: schema enrichment and data backfill using graph traversal to derive denormalized properties from relationship counts — a standard DBA migration task.

## Objective
In `demodb`, backfill visit counts across the attractions hierarchy:

1. Add property `VisitCount` (INTEGER) to the `Attractions` class. This property will be available on all subclasses (`ArchaeologicalSites`, `Castles`, `Monuments`).

2. For each attraction record (across all subclasses), count the number of incoming `HasVisited` edges and set `VisitCount` accordingly. Attractions with no visitors should have `VisitCount = 0`.

3. Create vertex class `AttractionVisitAudit` with the following mandatory properties:
   - `AttractionName` (STRING, mandatory)
   - `NewVisitCount` (INTEGER, mandatory)
   - `AuditBatch` (STRING, mandatory)

4. Create a `NOTUNIQUE` index on `AttractionVisitAudit.AuditBatch`.

5. Insert one `AttractionVisitAudit` record for each attraction that has `VisitCount >= 1`, with `AuditBatch = 'visit_backfill_2026q1'`.

## Expected Visit Counts

| Attraction               | Class               | Expected VisitCount |
|--------------------------|---------------------|---------------------|
| Acropolis of Athens       | ArchaeologicalSites | 2                   |
| Neuschwanstein Castle     | Castles             | 2                   |
| Sagrada Familia           | Monuments           | 1                   |
| Edinburgh Castle          | Castles             | 1                   |
| Brandenburg Gate          | Monuments           | 1                   |
| All others (9 attractions)| various             | 0                   |

Expected audit records: 5 (one per attraction with VisitCount >= 1).

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Attractions(Name, Type, Latitude, Longitude, City, Country)` — base class
- `ArchaeologicalSites EXTENDS Attractions`
- `Castles EXTENDS Attractions`
- `Monuments EXTENDS Attractions`
- `HasVisited` edge class (Profile → Attraction)
- Target: `Attractions.VisitCount` (new INTEGER property)
- Target: `AttractionVisitAudit(AttractionName, NewVisitCount, AuditBatch)`

## Verification Strategy
- Verify `VisitCount` property exists on `Attractions`.
- Verify correct `VisitCount` for high-traffic attractions (Acropolis=2, Neuschwanstein=2).
- Verify correct `VisitCount` for single-visit attractions.
- Verify `AttractionVisitAudit` schema and NOTUNIQUE index on AuditBatch.
- Verify audit row count = 5 with correct AuditBatch tag.

## Edge Cases
- Updating VisitCount via the base class `Attractions` propagates to all subclasses.
- VisitCount > expected for any tracked attraction triggers a wrong-target check.
- Audit records for attractions with VisitCount=0 should NOT be inserted.

## Difficulty
`very_hard` — requires class hierarchy property management, graph traversal for edge counting, conditional record insertion, and indexed audit trail creation.
