# Task: Schedule Hypertension Follow-up Appointment

## Overview

**Difficulty**: Hard
**Estimated Steps**: 15-25
**Domain Knowledge Required**: Clinical guidelines for hypertension management, EHR navigation

## Clinical Scenario

You are a medical assistant at a primary care clinic. A patient with hypertension needs a follow-up appointment scheduled according to clinical guidelines.

**Patient**: Jayson Fadel (DOB: 1992-06-30)
**Condition**: Hypertension (diagnosed 2010-08-24, SNOMED: 59621000)
**Current Medication**: amLODIPine 5 MG / Hydrochlorothiazide 12.5 MG / Olmesartan medoxomil 20 MG (combination antihypertensive)

### Clinical Context

According to JNC 8 (Joint National Committee on Prevention, Detection, Evaluation, and Treatment of High Blood Pressure) guidelines:
- Patients with controlled hypertension should be seen every 3-6 months
- Patients on combination therapy require closer monitoring
- Follow-up visits should include blood pressure check and medication review

The patient's last encounter was 2019-10-15. He is overdue for a follow-up and needs an appointment scheduled.

## Task Description

1. **Log in** to OpenEMR (admin/pass)
2. **Search for and open** patient Jayson Fadel's chart
3. **Review** the patient's:
   - Problem list (confirm hypertension diagnosis)
   - Current medications (confirm antihypertensive regimen)
   - Last encounter date
4. **Navigate** to the appointment scheduler (Calendar)
5. **Schedule** a follow-up appointment with the following requirements:
   - **Date**: Within the next 2 weeks from today
   - **Time**: Any available morning slot (9 AM - 12 PM)
   - **Duration**: 30 minutes
   - **Category/Type**: Follow-up or Office Visit
   - **Reason**: "Hypertension follow-up - medication review"

## Success Criteria

The task is considered successful if:

1. **Appointment exists** in the calendar for patient Jayson Fadel
2. **Correct patient** linked (pid = 3)
3. **Appointment date** is within 14 days of task execution
4. **Appointment time** is between 09:00 and 12:00
5. **Duration** is at least 15 minutes
6. **Reason/comment** mentions hypertension or blood pressure or medication

## Verification Method

The verifier will:
1. Query `openemr_postcalendar_events` table for appointments matching pid=3
2. Verify appointment datetime falls within expected range
3. Check that appointment category and comments are appropriate
4. Confirm appointment was created after task start time (newly created)

## Database Schema Reference

```sql
-- Appointments table
SELECT pc_eid, pc_catid, pc_pid, pc_title, pc_time, pc_eventDate,
       pc_startTime, pc_endTime, pc_duration, pc_hometext
FROM openemr_postcalendar_events
WHERE pc_pid = 3;

-- Patient verification
SELECT pid, fname, lname, DOB FROM patient_data WHERE pid = 3;

-- Condition verification
SELECT * FROM lists WHERE pid = 3 AND type = 'medical_problem'
AND title LIKE '%Hypertension%';
```

## Ground Truth Data

**Patient Details** (from sample_patients.sql):
- pid: 3
- Name: Jayson Fadel
- DOB: 1992-06-30
- Address: 1056 Harris Lane Suite 70, Chicopee, MA 01020
- Phone: (010) 555-1605

**Condition** (from lists table):
- Hypertension (SNOMED: 59621000)
- Start date: 2010-08-24
- Ongoing (no end date)

**Current Medications** (from prescriptions table):
- amLODIPine 5 MG / Hydrochlorothiazide 12.5 MG / Olmesartan medoxomil 20 MG
- Multiple refills documented (2010-2019)
- RxNorm: 999967

## Why This Task is Complex

1. **Multi-step navigation**: Requires finding patient, reviewing chart, then navigating to calendar
2. **Clinical reasoning**: Must understand why this patient needs follow-up (hypertension on combo therapy)
3. **Data interpretation**: Must review existing conditions and medications to confirm appropriateness
4. **Time-based constraints**: Appointment must be within specific timeframe and hours
5. **Form completion**: Multiple fields must be filled correctly in appointment dialog
6. **Context switching**: Moving between patient chart and calendar modules

## OpenEMR Navigation Path

1. Login → Dashboard
2. Patient → Finder (search "Jayson Fadel")
3. Click patient name → Patient Summary
4. Medical Problems tab → Review Hypertension
5. Medications tab → Review current prescriptions
6. Calendar (top menu) → Navigate to appropriate date
7. Click time slot → New Appointment dialog
8. Select patient (or patient pre-selected if accessed from chart)
9. Fill appointment details → Save

## Edge Cases to Consider

- What if the patient already has an upcoming appointment? (should still create new one per instructions)
- What if no morning slots are available on desired day? (pick next available morning slot)
- How to handle timezone differences in datetime verification

## Realistic Medical Rationale

This task mirrors real clinical workflow where:
- Medical assistants schedule follow-ups based on clinical protocols
- Chronic disease management requires regular monitoring intervals
- Documentation of visit reason is essential for billing and care coordination
- Combination antihypertensive therapy indicates more complex hypertension management
