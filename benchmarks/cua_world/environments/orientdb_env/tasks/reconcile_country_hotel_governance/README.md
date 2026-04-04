# Reconcile Country-Hotel Governance Drift

## Scenario
A travel platform's governance pipeline introduced inconsistent country values in both the master country dictionary and flagship hotel records. This is now breaking downstream analytics and compliance reports.

You are acting as the database architect responsible for restoring referential consistency and documenting the remediation.

## Occupation Grounding
- Product: `OrientDB`
- Source context from `task_creation_notes`: `Cloud database services`, `Database System`, `Spatial database software`
- Primary occupation signal: `Database Architects (SOC 15-1243.00)` with high software importance in `master_dataset.csv`
- Real workflow fit: enforcing canonical dimensions, schema constraints, and auditable remediation trails after data quality incidents.

## Objective
In `demodb`, repair the UK/Netherlands governance drift so that:

- `Countries` has correct classifications for:
  - `United Kingdom` -> `European`
  - `Netherlands` -> `European`
- `Hotels` has canonical country values for:
  - `The Savoy` -> `United Kingdom`
  - `Intercontinental Amsterdam` -> `Netherlands`
- `Countries.Name` is protected with a `UNIQUE` index.
- A remediation audit class exists and is populated:
  - Class: `GovernanceFixLog` (vertex class)
  - Required properties: `IssueKey`, `ResolvedBy`, `ResolvedAt`
  - Mandatory properties: `IssueKey`, `ResolvedBy`
  - Required issue keys (one record each):
    - `COUNTRY_UK_TYPE`
    - `COUNTRY_NL_TYPE`
    - `HOTEL_SAVOY_COUNTRY`
    - `HOTEL_ICA_COUNTRY`
  - `ResolvedBy` must be `data_governance` for all four records.

## Access
- OrientDB Studio: `http://localhost:2480/studio/index.html`
- Server credentials: `root` / `GymAnything123!`
- Database: `demodb`

## Schema Reference
- `Countries(Name, Type)`
- `Hotels(Name, Country, City, Stars, ...)`
- `GovernanceFixLog(IssueKey, ResolvedBy, ResolvedAt, ...)`
- `Countries.Name` index metadata

## Verification Strategy
- Reject wrong-target outcomes if flagship hotel country values are not exactly repaired.
- Verify canonical country type repair in `Countries`.
- Verify `Countries.Name` uniqueness hardening via a `UNIQUE` index.
- Verify `GovernanceFixLog` schema shape and mandatory flags.
- Verify all required issue-key audit rows exist with the expected owner identity.

## Edge Cases
- Partial remediation (countries fixed but index missing) should not pass.
- Correct values on wrong entities should fail.
- Missing or malformed audit rows should fail even if data values are repaired.

## Difficulty
`very_hard` — this requires coordinated schema work, index hardening, and targeted data remediation without a step-by-step UI path.
