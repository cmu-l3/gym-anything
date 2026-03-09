# Remediate Swapped Hotel Geo-Coordinates

## Scenario
A bad ETL transform swapped latitude/longitude for several flagship hotels. Spatial routing and map rendering are now unreliable in production.

You are the spatial data engineer assigned to repair these records and leave a structured audit trail.

## Occupation Grounding
- Product: `OrientDB`
- Source context from `task_creation_notes`: `Spatial database software` and `Cloud database services`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)` with spatial-data stewardship responsibilities
- Real workflow fit: geospatial data quality remediation with traceable before/after audit evidence.

## Objective
In `demodb`:

1. Correct coordinates for the affected hotels to their canonical values:
   - `The Plaza Hotel` -> `Latitude=40.7645`, `Longitude=-73.9744`
   - `Park Hyatt Tokyo` -> `Latitude=35.6858`, `Longitude=139.6909`
   - `Four Seasons Sydney` -> `Latitude=-33.8611`, `Longitude=151.2112`
2. Create vertex class `GeoFixAudit` with mandatory properties:
   - `HotelName` (STRING)
   - `PreviousLatitude` (DOUBLE)
   - `PreviousLongitude` (DOUBLE)
   - `NewLatitude` (DOUBLE)
   - `NewLongitude` (DOUBLE)
   - `FixBatch` (STRING)
3. Insert one audit record per corrected hotel with `FixBatch='geo_swap_2026q1'`.

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Hotels(Name, Latitude, Longitude, Country, City, ...)`
- `GeoFixAudit(HotelName, PreviousLatitude, PreviousLongitude, NewLatitude, NewLongitude, FixBatch)`

## Verification Strategy
- Reject wrong-target outcomes unless all three hotel coordinates are corrected exactly.
- Verify corrected coordinates remain in legal geospatial ranges.
- Verify `GeoFixAudit` schema with mandatory properties.
- Verify one audit row per target hotel with the required `FixBatch`.
- Verify audit `NewLatitude/NewLongitude` values match final repaired coordinates.

## Edge Cases
- Partial coordinate repair should fail.
- Correct coordinates with missing audit evidence should fail.
- Audit rows for wrong hotels should fail.

## Difficulty
`very_hard` — combines spatial integrity repair, schema authoring, and auditable remediation records.
