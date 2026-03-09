# Asset Inventory Reconciliation

## Domain Context

After a physical inventory audit, maintenance teams must reconcile discrepancies
between the CMMS database and the actual asset inventory. Common discrepancies
include wrong serial numbers, assets that should be decommissioned, missing assets
not yet in the system, and assets assigned to the wrong building/location.

**Occupation:** Maintenance and Repair Workers, General (SOC 49-9071.00)
**Industry:** Facilities Management / Asset Management

## Goal

Reconcile the OpenMaint asset database against an audit report (CSV on desktop).
The agent must:
1. Correct serial numbers on 4 assets with wrong values
2. Decommission (remove or deactivate) 2 assets flagged as decommissioned
3. Create 3 new assets found in the audit but missing from the database
4. Correct building/location assignments for 2 assets in the wrong building
5. Preserve a contamination asset (DECOM-003) that appears in the decommission
   list but is actually a valid asset being transferred — must remain active

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 Serials | 25 | 4 assets have corrected serial numbers |
| C2 Decommission | 20 | 2 decommissioned assets removed or deactivated |
| C3 New Assets | 20 | 3 new assets created with correct codes |
| C4 Locations | 20 | 2 assets relocated to correct building |
| C5 Contamination | 15 | DECOM-003 preserved and active (not wrongly decommissioned) |

**Pass threshold:** 60/100
**Score cap:** If contamination asset is deleted, score capped at 50.

## Verification Strategy

- **Setup** seeds assets with wrong serial numbers, creates decommission candidates,
  notes expected new asset codes, seeds wrong-location assets, and creates the
  contamination asset. Records all IDs and expected values in baseline.
- **Export** reads current state of each tracked asset via API: serial numbers,
  active status, building references, and scans all assets for newly created codes.
- **Verifier** checks each criterion against expected values from baseline.
  Do-nothing detection: if no serials changed, no assets decommissioned,
  no new assets created, and no locations fixed, score = 0.

## Schema Reference

- **Class:** CI or Asset (card class — regular class, not a process)
- **Key fields:** Code, Serial (SerialNumber), Building (reference), _is_active
- **Baseline file:** `/tmp/air_baseline.json`
- **Result file:** `/tmp/air_result.json`

## Task Input File

`/home/ga/Desktop/audit_report.csv` contains the reconciliation audit with
columns for asset code, expected serial, action (fix/decommission/new/relocate),
and target building.

## Edge Cases

- DECOM-003 appears in the decommission section of the audit but has a note
  indicating it is being transferred, not decommissioned. An agent that
  blindly decommissions everything matching "DECOM" will lose 15 points and
  have score capped.
- Agent may decommission via deletion (card removed) or status change
  (set inactive/retired). Both are accepted.
- New assets must have exact matching Code values to be found by the verifier.
