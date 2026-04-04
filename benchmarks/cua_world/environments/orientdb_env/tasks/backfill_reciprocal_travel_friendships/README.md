# Backfill Reciprocal Travel Friendships

## Scenario
A graph migration left one-way friendship links in a high-value traveler cohort. Product recommendations now assume reciprocal friendship semantics when users co-stay at the same hotel.

You are the graph data engineer responsible for repairing this migration and creating affinity metadata edges for the repaired links.

## Occupation Grounding
- Product: `OrientDB`
- Source context from `task_creation_notes`: `Cloud database services` and `Database System`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)`
- Real workflow fit: post-migration graph integrity backfills with relationship-derived metadata for recommendation systems.

## Objective
In `demodb`, for the cohort:

- `john.smith@example.com`
- `david.jones@example.com`
- `emma.white@example.com`
- `maria.garcia@example.com`
- `sophie.martin@example.com`

perform the reciprocal-backfill workflow:

1. Create edge class `TravelAffinity` with properties:
   - `SharedHotels` (INTEGER, mandatory)
   - `CountryOverlap` (INTEGER, mandatory)
   - `RuleVersion` (STRING, mandatory)
2. Identify one-way `HasFriend` links in this cohort where the reverse edge is missing **and** both users share at least one stayed hotel.
3. Create the missing reverse `HasFriend` edges.
4. For each newly created reverse edge, create one matching `TravelAffinity` edge in the same direction with:
   - `SharedHotels >= 1`
   - `CountryOverlap >= 1`
   - `RuleVersion = 'v2026q1'`

Expected reverse edges that must exist after remediation:

- `david.jones@example.com -> john.smith@example.com`
- `david.jones@example.com -> emma.white@example.com`
- `sophie.martin@example.com -> maria.garcia@example.com`

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Profiles(Email, ...)`
- `HasFriend` edge class
- `HasStayed` edge class
- `TravelAffinity(SharedHotels, CountryOverlap, RuleVersion)`

## Verification Strategy
- Reject wrong-target outcomes unless all required reverse `HasFriend` edges exist.
- Verify `TravelAffinity` schema existence and mandatory properties.
- Verify edge payload constraints (`SharedHotels`, `CountryOverlap`, `RuleVersion`).
- Verify no off-target `TravelAffinity` edges are introduced.
- Verify edge cardinality matches migration scope.

## Edge Cases
- Creating reciprocal edges for non-target pairs should fail.
- Missing `TravelAffinity` metadata on repaired pairs should fail.
- Creating only one or two reverse edges should fail.

## Difficulty
`very_hard` — this requires graph reasoning, cohort-limited targeting, and schema + edge migration consistency.
