# Task: Appointment Schedule Audit and Conflict Resolution

## Domain Context

Appointment scheduling conflicts are a common operational challenge in clinic management. When multiple patients are booked for the same provider at the same time, a clinic coordinator must perform a schedule audit, identify the conflicts, and reschedule patients appropriately — preserving the earliest patient's slot and distributing others to avoid waiting. In Bahmni's Appointments module (used at district hospitals in Ethiopia, India, and Bangladesh), this involves navigating the appointments calendar, identifying same-slot bookings, editing individual appointments, and documenting the reason for changes. This is a realistic workflow for a clinic manager or medical secretary.

## Goal

Resolve an appointment overbooking conflict in the Bahmni Appointments module. Three patients (Emily Chen BAH000011, Rosa Martinez BAH000010, Priya Patel BAH000005) were all booked at the same time slot tomorrow. By end of task:

1. **All three appointments identified** — agent must navigate to the Appointments module and locate the conflicts
2. **Emily Chen rescheduled** — her appointment moved to 1 hour after the original conflict time
3. **Rosa Martinez rescheduled** — her appointment moved to 2 hours after the original conflict time
4. **Priya Patel kept at original time** — no change to her appointment
5. **All three appointments are at different time slots** — no two share the same start time

## Success Criteria

| Criterion | Points | Verifier Check |
|-----------|--------|----------------|
| Emily Chen's appointment time changed (+1 hour) | 30 | Appointment time vs original seeded time |
| Rosa Martinez's appointment time changed (+2 hours) | 30 | Appointment time vs original seeded time |
| Priya Patel's appointment unchanged | 20 | Appointment time matches original seeded time |
| All three appointments at different times | 20 | No two share start_time |
| **Pass threshold** | **70** | Score ≥ 70 |

## Verification Strategy

1. `setup_task.sh` creates 3 appointments all at the same time tomorrow (e.g., 09:00 AM) via the Bahmni Appointments REST API. Saves the original time to `/tmp/asa_original_appointment_time`.

2. `export_result.sh` queries the Bahmni Appointments REST API for all current appointments for these three patients and extracts their start times.

3. `verifier.py` compares against the original seeded time:
   - Wrong-patient gate: all three identifiers must appear in results
   - Emily = original + ~60 minutes
   - Rosa = original + ~120 minutes
   - Priya = unchanged

## Schema Reference

Bahmni Appointments REST API:
- Base: `https://localhost/openmrs/ws/rest/v1/appointments`
- List: `GET /appointments?forDate=YYYY-MM-DD`
- Get by patient: `GET /appointments/appointmentsSummary?forDate=YYYY-MM-DD`
- Appointment service: `GET /appointmentscheduling/appointmentservice`

Appointments DB table: `appointmentscheduling_appointment` in `openmrs` database (if module is installed)
OR in a separate `appointments` schema.

## Starting State

- Three conflicting appointments seeded via Appointments API:
  - Emily Chen (BAH000011): tomorrow at 09:00 AM, General OPD
  - Rosa Martinez (BAH000010): tomorrow at 09:00 AM, General OPD
  - Priya Patel (BAH000005): tomorrow at 09:00 AM, General OPD
- All appointments active (not cancelled)
- Original appointment time stored in `/tmp/asa_original_appointment_time`

## Edge Cases

- Bahmni Appointments module uses a different API path than OpenMRS core
- The conflict is with the same service/provider, not just the same calendar time
- "1 hour later" is interpreted as ±15 minutes flexibility by the verifier
- Agent must understand tomorrow's date correctly
- Agent may need to navigate through the appointments calendar view to see conflicts
