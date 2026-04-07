# Cancel Patient Appointment (`cancel_appointment@1`)

## Overview

This task tests the agent's ability to cancel a scheduled appointment in OpenEMR's calendar system. Cancellation is a distinct workflow from rescheduling (moving to a new time) or documenting a no-show (patient didn't arrive). This task validates proper appointment status management and the agent's ability to navigate the calendar interface to modify existing appointments.

## Rationale

**Why this task is valuable:**
- Tests appointment lifecycle management (beyond just creation)
- Validates understanding of appointment status workflows
- Requires navigating to existing data and modifying it
- Common front desk operation performed multiple times daily
- Different from rescheduling (no new appointment created)
- Different from no-show documentation (proactive vs reactive)

**Real-world Context:** A patient calls the clinic to cancel their upcoming appointment due to a work conflict. The front desk staff needs to cancel the appointment in the system so the time slot becomes available for other patients, and the cancellation is documented for reporting purposes.

## Task Description

**Goal:** Cancel an existing appointment for patient Sarah Borer, documenting the reason as "Patient requested cancellation - work conflict".

**Starting State:** OpenEMR is open in Firefox with the login page displayed. Patient Sarah Borer (DOB: 1954-07-22) has an existing scheduled appointment on **2024-12-20 at 10:00 AM** that needs to be cancelled.

**Expected Actions:**
1. **Log in** to OpenEMR using credentials admin/pass
2. **Navigate** to the Calendar (Appointment Scheduler)
3. **Find** the appointment for Sarah Borer on December 20, 2024 at 10:00 AM
4. **Open** the appointment details
5. **Change** the appointment status to "Cancelled" (or equivalent)
6. **Add** cancellation reason: "Patient requested cancellation - work conflict"
7. **Save** the changes to complete the cancellation

**Final State:** The appointment record for Sarah Borer on 2024-12-20 shows a cancelled status with the documented reason. The appointment should NOT be deleted - the record should remain for tracking purposes with its status changed.

## Verification Strategy

### Primary Verification: Database State Check

Query the appointments table to verify the cancellation: