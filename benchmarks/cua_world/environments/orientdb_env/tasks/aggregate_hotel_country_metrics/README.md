# Aggregate Hotel Country Metrics

## Scenario
Business intelligence reported the executive dashboard cannot render country-level hotel density tiles because no aggregated summary layer exists. Raw hotel records exist in the `Hotels` vertex class but no country-level rollup is available for efficient API access.

You are the database architect responsible for materializing a denormalized metrics layer.

## Occupation Grounding
- Product: `OrientDB`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)`
- Real workflow fit: building denormalized aggregation vertices from raw data for BI dashboard consumption — a standard pattern in multi-model graph databases.

## Objective
In `demodb`, materialize a country-level hotel metrics summary:

1. Create vertex class `HotelCountryMetrics` with the following mandatory properties:
   - `Country` (STRING, mandatory)
   - `TotalHotels` (INTEGER, mandatory)
   - `LuxuryCount` (INTEGER, mandatory) — count of hotels with `Stars = 5`
   - `ReportBatch` (STRING, mandatory)

2. Create a `UNIQUE` index on `HotelCountryMetrics.Country`.

3. Query the `Hotels` class and compute per-country aggregates:
   - `TotalHotels` = total hotel records for that country
   - `LuxuryCount` = hotels where `Stars = 5`

4. Insert one `HotelCountryMetrics` record per country that has at least one hotel.

5. Set `ReportBatch = 'bi_q1_2026'` on every inserted row.

## Expected Metrics

| Country         | TotalHotels | LuxuryCount |
|----------------|------------|-------------|
| Italy           | 3          | 2           |
| Germany         | 2          | 1           |
| France          | 2          | 1           |
| United Kingdom  | 1          | 1           |
| United States   | 1          | 1           |
| Japan           | 1          | 1           |
| Australia       | 1          | 1           |
| Brazil          | 1          | 1           |
| Spain           | 1          | 1           |
| Greece          | 1          | 1           |
| Netherlands     | 1          | 1           |

Total: 11 countries, 15 hotels.

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Hotels(Name, Type, Stars, Country, City, Latitude, Longitude, ...)`
- Target: `HotelCountryMetrics(Country, TotalHotels, LuxuryCount, ReportBatch)`

## Verification Strategy
- Reject wrong-target outcomes (any country not present in the Hotels table).
- Verify `HotelCountryMetrics` schema with all four mandatory properties.
- Verify `UNIQUE` index on `Country`.
- Verify exact row count (11 countries).
- Spot-check Italy (TotalHotels=3, LuxuryCount=2), Germany, France.
- Verify `ReportBatch` value on all rows.

## Edge Cases
- A row for a country not in the Hotels table triggers wrong-target rejection.
- Miscounting LuxuryCount (e.g., including 4-star hotels) fails the payload check.
- Missing UNIQUE index on Country fails even if data is correct.

## Difficulty
`very_hard` — requires aggregation queries across a document-graph model, denormalized vertex materialization, and uniqueness-constrained indexing.
