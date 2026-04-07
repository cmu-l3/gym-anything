# Import Focal Mechanism Solution (`import_focal_mechanism_scml@1`)

## Overview
This task evaluates the agent's ability to manage advanced seismological data objects in SeisComP. The agent must create and import a Focal Mechanism (Moment Tensor) solution for an existing earthquake event. This involves working with the SeisComP Data Model (SCML) to encode fault plane solutions and linking them to the correct event in the database.

## Rationale
**Why this task is valuable:**
- **Advanced Data Modeling**: Tests understanding of the specialized `FocalMechanism` and `MomentTensor` data objects, which are distinct from standard Origins and Magnitudes.
- **Database integrity**: Requires correctly linking new data objects (Child) to existing database events (Parent) via PublicIDs.
- **Interoperability**: Simulates the real-world workflow of importing external solutions (e.g., from GCMT or USGS) into a local catalog.
- **XML/Scripting Skill**: Validates the ability to construct complex SeisComP XML (SCML) files either manually or using the SeisComP Python API.

**Real-world Context:** A seismologist has received the official Global CMT (GCMT) moment tensor solution for the 2024 Noto Peninsula earthquake. The local SeisComP database currently contains only the hypocenter and magnitude. To enable further analysis (such as stress drop or tsunami modeling), the focal mechanism parameters must be added to the event record in the database.

## Task Description

**Goal:** Create a SeisComP XML (SCML) file containing the Focal Mechanism parameters for the Noto earthquake, import it into the database, and verify the event has been updated.

**Starting State:**
- SeisComP is running with the `scmaster` messaging system active.
- The database contains the **2024 Noto Peninsula** earthquake.
- The event currently has a preferred Origin and Magnitude, but **NO** Focal Mechanism from GCMT.
- The user is logged in as `ga`.

**Input Data (GCMT Parameters):**
The agent must encode the following parameters:
- **Nodal Plane 1:**
  - Strike: `53.0` degrees
  - Dip: `79.0` degrees
  - Rake: `94.0` degrees
- **Moment Tensor:**
  - Scalar Moment ($M_0$): `2.22e+20` Nm
  - Moment Magnitude ($M_w$): `7.5`
- **Creation Info:**
  - Agency ID: `GCMT`

**Expected Actions:**
1.  **Identify the Event:** Query the database to find the `preferredOriginID` of the Noto earthquake event.
2.  **Create SCML File:** Generate a valid SCML file (`/home/ga/noto_mechanism.scml`) that contains:
    - A `FocalMechanism` object.
    - A `MomentTensor` child object containing the scalar moment.
    - A `NodalPlanes` object populated with the Strike/Dip/Rake values.
    - Correct linkages: The `FocalMechanism` must reference the existing event's preferred Origin as its `triggeringOriginID`.
3.  **Import:** Use `scdb` to import the file into the database.

**Final State:**
- The SeisComP database table `FocalMechanism` contains a record with agencyID `GCMT`.
- The SeisComP database table `MomentTensor` contains the correct scalar moment.
- The file `/home/ga/noto_mechanism.scml` exists on disk.

## Verification Strategy

### Primary Verification: Database Content
The verifier will perform SQL queries against the `seiscomp` database:
1.  **Existence**: Check `FocalMechanism` table for an entry with `creationInfo_agencyID` = 'GCMT'.
2.  **Values**: Verify the `strike`, `dip`, and `rake` columns match the input (tolerance ±1.0).
3.  **Moment**: Verify the `scalarMoment_value` in the `MomentTensor` table matches `2.22e+20` (tolerance ±0.05e20).
4.  **Linkage**: Verify the `triggeringOriginID` in the `FocalMechanism` table matches the `preferredOriginID` of the Noto event.

### Secondary Verification: File Evidence
- Checks that the agent actually produced the file `/home/ga/noto_mechanism.scml` during the session (anti-gaming).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **SCML File Created** | 15 | File generated during task |
| **Focal Mechanism Created** | 20 | `FocalMechanism` record exists in DB |
| **Origin Linkage** | 15 | Mechanism is correctly linked to the Origin |
| **Nodal Plane Accuracy** | 30 | Strike, Dip, and Rake match expected (10 pts each) |
| **Moment Tensor Accuracy** | 20 | Moment tensor object created with correct scalar moment |
| **Total** | **100** | |

**Pass Threshold:** 70 points