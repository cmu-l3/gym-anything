# Update Patient Demographics (`update_patient_demographics@1`)

## Overview

This task tests the agent's ability to locate an existing patient record and update their contact information. Updating demographics is one of the most frequent tasks performed by front desk staff in medical practices, as patients regularly change addresses, phone numbers, and other contact details.

## Rationale

**Why this task is valuable:**
- Tests fundamental EHR navigation (finding patients, accessing demographics)
- Validates form editing and data entry skills
- Exercises the patient search functionality
- Requires careful attention to multiple field updates
- Foundation skill used in nearly every patient interaction

**Real-world Context:** A patient calls the clinic to report they have moved to a new apartment and have a new phone number. The front desk receptionist must update the patient's record before their upcoming appointment to ensure correspondence reaches them and emergency contacts are current.

## Task Description

**Goal:** Update the contact information for an existing patient who has moved to a new address.

**Starting State:** OpenEMR is open at the login page in Firefox. The database contains Synthea-generated patient data including the target patient.

**Patient to Update:** Jayson Fadel (DOB: 1992-06-30)

**Current Information (in database):**
- Street: 1056 Harris Lane Suite 70
- City: Chicopee
- State: MA
- Postal Code: 01020
- Phone: (010) 555-1605

**New Information to Enter:**
- Street Address: 742 Evergreen Terrace, Unit 3A
- City: Springfield
- State: MA
- Postal Code: 01103
- Home Phone: 413-555-0842
- Mobile Phone: 413-555-9173

**Expected Actions:**
1. Log in to OpenEMR using credentials admin/pass
2. Navigate to Patient search (Patient/Client → Patients or use search bar)
3. Search for patient "Jayson Fadel" or use DOB 1992-06-30
4. Open the patient's chart/record
5. Navigate to Demographics section (may be under Patient → Demographics or Edit)
6. Click Edit or modify the contact information section
7. Update Street Address to: 742 Evergreen Terrace, Unit 3A
8. Update City to: Springfield
9. Verify State is: MA (should remain unchanged)
10. Update Postal Code to: 01103
11. Update Home Phone to: 413-555-0842
12. Update Mobile/Cell Phone to: 413-555-9173
13. Save the changes

**Final State:** The patient's demographics in the database reflect the new address and phone numbers.

## Verification Strategy

### Primary Verification: Database Query

The verifier directly queries the OpenEMR MySQL database to confirm the demographic fields were updated: