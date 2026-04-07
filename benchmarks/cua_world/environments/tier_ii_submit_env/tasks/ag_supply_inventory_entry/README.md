# Agricultural Supply Inventory Entry (`ag_supply_inventory_entry@1`)

## Overview
This task evaluates the agent's ability to create a new facility report in EPA Tier2 Submit 2025 and populate specific details across multiple tabs, including Facility Identification, Contacts, and Chemical Inventory. 

## Rationale
**Why this task is valuable:**
- **Primary Use Case:** Entering facility and chemical data is the core function of Tier2 Submit.
- **Cross-module Navigation:** Requires the agent to interact with three distinct modules within the application: Facility Identification, Contacts, and Chemical Inventory.
- **Data Precision:** Verifies accurate updates to numeric fields (occupants, days on site, chemical weights) that directly impact regulatory compliance.

**Real-world Context:** An Environmental Engineer (SOC 17-2081) is preparing the 2025 EPCRA Tier II report for "Central Valley Ag Supply", an agricultural chemical depot. The facility must report its inventory of Ammonium Nitrate, a commonly used fertilizer that requires reporting under EPCRA. The engineer must enter the facility details, designate the emergency contact, and record the specific chemical quantities and storage durations.

## Task Description

**Goal:** Create a new submission for Central Valley Ag Supply, enter facility and contact details, and add a chemical inventory record for Ammonium Nitrate before saving the file.

**Starting State:** 
- EPA Tier2 Submit 2025 is open to a blank state.

**Expected Actions:**
1. In the **Facility Identification** section, set the Facility Name to `Central Valley Ag Supply`.
2. Change the **Reporting Year** to `2025`.
3. Set the **Max Number of Occupants** to `27`.
4. Navigate to the **Contacts** section, add an Emergency Contact named `Sarah Jenkins`, and set her **24-Hour Phone** number to `559-555-0288`.
5. Navigate to the **Chemical Inventory** section and add a new chemical entry for **Ammonium Nitrate** (CAS `6484-52-2`).
6. Under the Quantities/Storage section for this chemical, set the **Number of Days On Site** to `94`.
7. Set the **Average Daily Amount** to `853` (lbs).
8. Use **File > Save As** to save the submission as `agri_depot_2025.t2s` on the Desktop (`C:\Users\Docker\Desktop\agri_depot_2025.t2s`).

**Final State:** 
- A new file named `agri_depot_2025.t2s` exists on the Desktop.
- The file contains all the specified data points.

## Verification Strategy

### Primary Verification: File Content Extraction (File-based)
EPA Tier2 Submit `.t2s` files are zipped archives containing SQLite databases or XML files. The verifier will:
1. Check for the existence of `C:\Users\Docker\Desktop\agri_depot_2025.t2s`.
2. Extract the contents of the `.t2s` file programmatically using Python's `zipfile` and `sqlite3`.
3. Parse the underlying database structure to verify the presence of the expected exact values.

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| File Creation | 20 | `agri_depot_2025.t2s` exists |
| Facility & Year | 20 | "Central Valley Ag Supply" and "2025" found in export |
| Occupants | 10 | Max Number of Occupants (27) found in export |
| Contact Update | 20 | "Sarah Jenkins" and "559-555-0288" found in export |
| Chemical Identity | 10 | CAS "6484-52-2" found in export |
| Chemical Quantities| 20 | "94" days and "853" lbs found in export |
| **Total** | **100** | |

**Pass Threshold:** 70 points.