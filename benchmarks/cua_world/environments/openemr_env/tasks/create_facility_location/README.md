# Create Facility Location (`create_facility_location@1`)

## Overview

This task tests the agent's ability to perform administrative configuration in OpenEMR by adding a new clinic facility location. This is essential for multi-site healthcare practices that need to track which location patients visit and where services are rendered for billing purposes.

## Rationale

**Why this task is valuable:**
- Tests administrative/configuration workflows (distinct from clinical tasks)
- Exercises the Administration menu navigation
- Validates form completion for non-patient entities
- Reflects real operational need for growing healthcare organizations
- Database verification is straightforward and unambiguous

**Real-world Context:** A primary care practice has just opened a satellite clinic location and needs to add it to their EHR system before they can schedule patients or bill for services at the new site.

## Task Description

**Goal:** Add a new satellite clinic facility to OpenEMR with complete address and contact information.

**Starting State:** OpenEMR is open in Firefox at the login page. No additional facilities beyond the default have been configured.

**Facility Details to Enter:**
- **Facility Name:** Riverside Family Medicine - East
- **Street Address:** 450 Harbor View Drive, Suite 200
- **City:** Springfield
- **State:** Massachusetts
- **ZIP Code:** 01109
- **Country:** USA
- **Phone:** (413) 555-0192
- **Fax:** (413) 555-0193
- **Federal Tax ID:** 04-3892156
- **Facility NPI:** 1234567893
- **Service Location:** Yes (this is a location where services are rendered)
- **Billing Location:** Yes (this location can appear on claims)

**Expected Actions:**
1. Log in to OpenEMR using credentials admin/pass
2. Navigate to Administration menu
3. Select Facilities (or Practice > Facilities depending on menu structure)
4. Click "Add Facility" or equivalent button
5. Fill in all required facility information as specified above
6. Save the new facility record
7. Verify the facility appears in the facility list

**Final State:** A new facility named "Riverside Family Medicine - East" exists in the facilities table with correct address and contact information.

## Verification Strategy

### Primary Verification: Database Query

The verifier queries the OpenEMR database to confirm the facility was created: