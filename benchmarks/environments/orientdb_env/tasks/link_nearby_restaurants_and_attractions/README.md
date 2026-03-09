# Link Nearby Restaurants and Attractions

## Scenario
A new tourism recommendation feature requires graph edges between restaurants and attractions located in the same city, enabling a "dine and explore nearby" recommendation API. The graph has city data on both `Restaurants` and `Attractions` vertices but no direct relationship edges. Only same-city pairs should be linked — cross-city links corrupt the recommendation model.

You are the database architect responsible for building the geo-proximity link layer.

## Occupation Grounding
- Product: `OrientDB`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)`
- Real workflow fit: building recommendation graph edges from shared entity attributes — a standard graph database pattern for spatial proximity features.

## Objective
In `demodb`, implement the city-based restaurant-attraction proximity model:

1. Create edge class `ProximityLink` (extends E) with the following mandatory property:
   - `MatchBasis` (STRING, mandatory) — set to `'same_city'` on every edge

2. Create vertex class `RecommendationManifest` with the following mandatory properties:
   - `RestaurantName` (STRING, mandatory)
   - `AttractionName` (STRING, mandatory)
   - `City` (STRING, mandatory)
   - `MatchBasis` (STRING, mandatory)
   - `BatchId` (STRING, mandatory)

3. Create a `NOTUNIQUE` index on `RecommendationManifest.City`.

4. Discover all pairs where `Restaurants.City = Attractions.City` by querying the graph. Attractions span all three subclasses: `ArchaeologicalSites`, `Castles`, `Monuments`.

5. For each matched pair, create a `ProximityLink` edge from the `Restaurants` vertex to the `Attractions` vertex, with `MatchBasis = 'same_city'`.

6. For each matched pair, insert one `RecommendationManifest` record with:
   - `RestaurantName` = restaurant name
   - `AttractionName` = attraction name
   - `City` = shared city
   - `MatchBasis = 'same_city'`
   - `BatchId = 'geo_proximity_2026q1'`

## Expected Matches

| City      | Restaurant              | Attraction           |
|-----------|------------------------|----------------------|
| Rome      | Da Enzo al 29           | Colosseum            |
| Berlin    | Lorenz Adlon Esszimmer  | Brandenburg Gate     |
| Paris     | Le Cinq                 | Eiffel Tower         |
| London    | Sketch                  | Big Ben              |
| New York  | Per Se                  | Statue of Liberty    |
| Athens    | Spondi                  | Acropolis of Athens  |
| Athens    | Spondi                  | Parthenon            |
| Barcelona | Tickets                 | Sagrada Familia      |

Total: 8 ProximityLink edges, 8 RecommendationManifest records.

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Restaurants(Name, City, Country, Type, ...)`
- `Attractions(Name, City, Country, ...)` — base class for `ArchaeologicalSites`, `Castles`, `Monuments`
- Target: `ProximityLink` edge class (Restaurants → Attractions), with `MatchBasis` property
- Target: `RecommendationManifest(RestaurantName, AttractionName, City, MatchBasis, BatchId)`

## Verification Strategy
- Reject wrong-target outcomes (any cross-city ProximityLink edge).
- Verify `ProximityLink` edge class with mandatory `MatchBasis` property.
- Verify `RecommendationManifest` schema with all five mandatory properties.
- Verify `NOTUNIQUE` index on `RecommendationManifest.City`.
- Verify total edge count = 8.
- Spot-check at least 3 specific restaurant-attraction pairs.
- Verify manifest row count = 8 with correct `BatchId`.

## Edge Cases
- Stonehenge is in Wiltshire (no restaurant in Wiltshire) — should NOT be linked.
- Pompeii is in Naples (no restaurant in Naples) — should NOT be linked.
- Tokyo has a restaurant but no attractions — no links for Tokyo.
- A cross-city link (e.g., Da Enzo al 29 → Eiffel Tower) triggers immediate wrong-target rejection.

## Difficulty
`very_hard` — requires cross-class city matching across graph entity types, edge class creation with properties, manifest record materialization, and strict same-city validation.
