# Assign Hotel Maintenance Priorities

## Scenario
The facilities operations team needs every hotel in the travel graph classified by maintenance priority before the Q1 inspection cycle begins. Hotels are currently stored as raw vertex records with Stars ratings and Type attributes, but there is no priority classification or graph link to an inspection entity.

You are the database architect responsible for implementing the maintenance prioritization model.

## Occupation Grounding
- Product: `OrientDB`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)`
- Real workflow fit: building normalized classification entities with rule-based record population and graph edge linking — a standard DBA task in facilities and asset management systems.

## Objective
In `demodb`, implement the hotel maintenance priority model:

1. Create vertex class `HotelMaintenanceFlag` with the following mandatory properties:
   - `HotelName` (STRING, mandatory)
   - `Priority` (STRING, mandatory) — values: `'CRITICAL'`, `'HIGH'`, `'STANDARD'`
   - `LastInspectionYear` (INTEGER, mandatory)
   - `MaintenanceBatch` (STRING, mandatory)

2. Create a `UNIQUE` index on `HotelMaintenanceFlag.HotelName`.

3. Create edge class `RequiresMaintenance` (extends E).

4. Apply the priority ruleset to all 15 hotels:
   - `CRITICAL`: `Stars = 5` AND `Type` is `'Luxury'` or `'Palace'`
   - `HIGH`:     `Stars = 5` AND `Type` is neither `'Luxury'` nor `'Palace'`
   - `STANDARD`: `Stars < 5`

5. Insert one `HotelMaintenanceFlag` record per hotel with:
   - Correct `Priority` per the ruleset
   - `LastInspectionYear = 2024`
   - `MaintenanceBatch = 'maint_q1_2026'`

6. Create a `RequiresMaintenance` edge from each `HotelMaintenanceFlag` vertex to its corresponding `Hotels` vertex.

## Expected Priority Distribution

| Priority | Count | Example Hotels |
|----------|-------|----------------|
| CRITICAL | 6     | Hotel Adlon Kempinski, Hotel de Crillon, The Savoy, Park Hyatt Tokyo, Four Seasons Sydney, Intercontinental Amsterdam |
| HIGH     | 6     | The Plaza Hotel, Copacabana Palace, Hotel Arts Barcelona, Grande Bretagne Hotel, Hotel Villa d Este, Baglioni Hotel Luna |
| STANDARD | 3     | Hotel Artemide, Fairmont Le Manoir, Melia Berlin |

Total: 15 HotelMaintenanceFlag records, 15 RequiresMaintenance edges.

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Hotels(Name, Type, Stars, Country, City, ...)`
- Target: `HotelMaintenanceFlag(HotelName, Priority, LastInspectionYear, MaintenanceBatch)`
- Target: `RequiresMaintenance` edge class (HotelMaintenanceFlag → Hotels)

## Verification Strategy
- Reject wrong-target outcomes (any hotel with incorrect Priority tier).
- Verify `HotelMaintenanceFlag` schema with all four mandatory properties.
- Verify `UNIQUE` index on `HotelName`.
- Verify `RequiresMaintenance` edge class existence.
- Verify total record count = 15.
- Verify priority distribution: exactly 6 CRITICAL, 6 HIGH, 3 STANDARD.
- Verify `RequiresMaintenance` edge count = 15.
- Spot-check specific hotels against expected Priority values.

## Edge Cases
- Hotels with Stars=5 but Type='Boutique' or 'Historic' must be HIGH, not CRITICAL.
- Hotels with Stars=4 must be STANDARD regardless of Type.
- Any hotel assigned to the wrong tier triggers immediate rejection.

## Difficulty
`very_hard` — requires rule-based multi-class record construction, edge class creation with relational linking, uniqueness-constrained indexing, and full-coverage schema population across 15 entities.
