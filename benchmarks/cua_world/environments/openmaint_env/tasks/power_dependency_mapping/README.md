# Power Distribution Dependency Mapping (`power_dependency_mapping@1`)

## Overview

This task evaluates the agent's ability to create inter-CI (Configuration Item) relationships in OpenMaint, documenting a power distribution topology across a building's electrical infrastructure. After a cascading power failure revealed that no dependency chain was recorded, the agent must establish directed relationships between six pre-existing electrical CIs to form the correct power feed topology.

## Rationale

**Why this task is valuable:**
- Tests understanding of OpenMaint's relation/domain management system — a core CMMS feature.
- Requires navigating between multiple CI records and using the "Relations" tab/panel.
- Involves reading a topology specification and translating it into system relationships.
- Real-world criticality: dependency mapping is essential for outage impact analysis.

**Real-world Context:** After a partial blackout in Building A, facilities staff struggled to identify affected downstream equipment because the power chain wasn't documented. You must explicitly map these dependencies in the system to prevent future delays.

## Task Description

**Goal:** Create five dependency relationships between six pre-existing electrical CIs in OpenMaint to document the power distribution chain.

**Starting State:** 
- OpenMaint is running.
- Six electrical CI cards exist (Transformer, Switchgear, two Distribution Panels, ATS, UPS).
- A topology specification file is on the desktop: `/home/ga/Desktop/power_topology.txt`.

**Expected Actions:**
1. Log in to OpenMaint (admin/admin).
2. Read the `power_topology.txt` file to understand the required connections.
3. Locate the source CIs in the Asset/CI module.
4. Create relations to the destination CIs as specified (e.g., Transformer feeds Switchgear).
5. Ensure all 5 links are created.

**Final State:**
- The electrical CIs are linked in the system, forming a connected graph from the Transformer down to the UPS.

## Verification Strategy

### Primary Verification: API-based Relation Check
The verifier queries the CMDBuild REST API to inspect the relations of the six specific CIs. It verifies that:
1. Each specified source-to-destination link exists (checking for the presence of a relation record).
2. All original CIs still exist (none were deleted).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| R1 Transformer→Switchgear | 20 | Relation exists between ELEC-XFMR-001 and ELEC-SWGR-001 |
| R2 Switchgear→Panel F1 | 20 | Relation exists between ELEC-SWGR-001 and ELEC-DP-001 |
| R3 Switchgear→Panel F2 | 15 | Relation exists between ELEC-SWGR-001 and ELEC-DP-002 |
| R4 Switchgear→ATS | 15 | Relation exists between ELEC-SWGR-001 and ELEC-ATS-001 |
| R5 ATS→UPS | 15 | Relation exists between ELEC-ATS-001 and ELEC-UPS-001 |
| Preservation | 15 | All 6 original CIs remain active and unmodified |
| **Total** | **100** | |

**Pass Threshold:** 60 points.