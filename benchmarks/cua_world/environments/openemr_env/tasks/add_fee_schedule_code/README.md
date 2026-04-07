# Add Procedure Code to Fee Schedule (`add_fee_schedule_code@1`)

## Overview

This task tests the agent's ability to configure billing infrastructure by adding a new procedure code to the practice's fee schedule. The agent must navigate OpenEMR's administrative interface to add a CPT code with its associated fee, a fundamental task for practice setup and revenue cycle management.

## Rationale

**Why this task is valuable:**
- Tests administrative/configuration navigation (not clinical workflow)
- Verifies understanding of medical billing code systems (CPT/HCPCS)
- Requires precise data entry with specific formatting requirements
- Essential skill for practice management and billing setup
- Completely different from clinical documentation tasks

**Real-world Context:** A practice administrator needs to configure billing for a newly offered telehealth service. Medicare and commercial payers have specific CPT codes for telephone evaluation and management services, and these must be added to the fee schedule before claims can be submitted.

## Task Description

**Goal:** Add a new CPT procedure code to the OpenEMR fee schedule with the correct description and fee amount.

**Starting State:** OpenEMR is open with the login page displayed. The fee schedule does not currently contain CPT code 99441.

**Scenario:**
Your medical practice has started offering telephone evaluation and management services for established patients. Before the billing department can charge for these services, you need to add the appropriate CPT code to the fee schedule.

Add the following procedure code to the fee schedule:
- **Code Type:** CPT4
- **Code:** 99441
- **Description:** Telephone E/M by physician, 5-10 min
- **Fee:** $45.00

**Expected Actions:**
1. Log in to OpenEMR (Username: admin, Password: pass)
2. Navigate to Administration > Codes
3. Select to add a new code
4. Enter the code type as CPT4
5. Enter code 99441
6. Enter the description: "Telephone E/M by physician, 5-10 min"
7. Set the fee to $45.00
8. Save the new code entry

**Final State:** The CPT code 99441 exists in the codes table with the correct fee amount configured.

## Verification Strategy

### Primary Verification: Database Query

The verifier will query the OpenEMR database to confirm the code was added: