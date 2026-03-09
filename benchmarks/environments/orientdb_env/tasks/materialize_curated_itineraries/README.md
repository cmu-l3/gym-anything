# Materialize Curated Heritage Itineraries

## Scenario
Travel content operations needs a curated itinerary layer for a premium heritage campaign. Base interaction edges exist, but monument visits and campaign summaries were never materialized.

You are the graph/database architect responsible for completing the curation layer.

## Occupation Grounding
- Product: `OrientDB`
- Source context from `task_creation_notes`: `Database System` and `Cloud database services`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)`
- Real workflow fit: campaign-data curation where graph interactions are transformed into indexed summary entities for downstream analytics.

## Objective
In `demodb`, for cohort profiles:

- `sophie.martin@example.com`
- `luca.rossi@example.com`
- `elena.petrakis@example.com`

perform the curation workflow:

1. Add missing `HasVisited` edges:
   - `sophie.martin@example.com -> Eiffel Tower`
   - `luca.rossi@example.com -> Colosseum`
   - `elena.petrakis@example.com -> Parthenon`
2. Create vertex class `ItinerarySummary` with mandatory properties:
   - `Email` (STRING)
   - `Country` (STRING)
   - `HotelCount` (INTEGER)
   - `RestaurantCount` (INTEGER)
   - `AttractionCount` (INTEGER)
   - `CurationTag` (STRING)
3. Create `UNIQUE` index on `ItinerarySummary.Email`.
4. Insert exactly one summary row per cohort profile with:
   - `Country` matching the curated destination country
   - `HotelCount = 1`
   - `RestaurantCount = 1`
   - `AttractionCount = 1`
   - `CurationTag = 'heritage_trio_2026q1'`

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Profiles(Email, ...)`
- `HasStayed`, `HasEaten`, `HasVisited` edge classes
- `ItinerarySummary(Email, Country, HotelCount, RestaurantCount, AttractionCount, CurationTag)`
- `ItinerarySummary.Email` unique index

## Verification Strategy
- Reject wrong-target outcomes unless the exact cohort-to-monument mapping is present.
- Verify `ItinerarySummary` schema and mandatory fields.
- Verify uniqueness hardening on `ItinerarySummary.Email`.
- Verify campaign summary payload values exactly match expected per-profile counts and tags.
- Verify summary row cardinality is exactly the cohort size.

## Edge Cases
- Missing one `HasVisited` edge should fail.
- Overproducing summary rows should fail.
- Correct counts with wrong country/tag values should fail.

## Difficulty
`very_hard` — combines graph repair, campaign-scoped summary modeling, and index-safe materialization.
