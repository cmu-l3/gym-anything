# GNU Health Environment - Evidence Documentation

## Test Summary
- **Date**: 2026-02-17
- **Environment**: `gnu_health_env@0.1`
- **Base image**: `ubuntu-gnome-systemd_highres`
- **SSH port**: 2271, **VNC port**: 6050
- **Result**: SUCCESS - GNU Health 5.0 running with full demo database

## Checklist Verification

- [x] Installation script completes (trytond 7.0.45 + gnuhealth-all-modules 5.0.x)
- [x] Setup script completes (demo DB restored, passwords rehashed to scrypt, server started)
- [x] Application visible in screenshot (Firefox showing GNU Health Sao web client)
- [x] Application in correct initial state (Patients list with 10 real demo patients)
- [x] Task setup runs without errors (register_patient pre_task ran in 55s)
- [x] Task start state correct (Marcus Delgado absent, Ana Betz present with PUID GNU777ORG)
- [x] Evidence of task completability (new patient form opens with "Create..." flow tested)
- [x] Doctor fields corrected (Cordara, Cameron — actual health professional in DB)
- [x] Appointment date corrected (2027-03-15, future date)
- [x] Task 5 description corrected (Socioeconomics tab, party record for contacts)
- [x] HbA1c test type added to DB for Task 4
- [x] Fake patients removed (dodo, Trịnh Trung Kiên 1993) via setup_gnuhealth.sh

## Screenshots

### Initial Session Screenshots
**File**: `00_login_page.png` - GNU Health Sao login page
**File**: `01_logged_in_dashboard.png` - Logged in successfully as admin/gnusolidario
**File**: `02_dashboard.png` - Full GNU Health dashboard
**File**: `03_patients_list.png` - Patient list with real demo data

### Task 1: register_patient
**File**: `task1_register_patient_start_state.png`
**State**: Patients list showing 10 real demo patients. Marcus Delgado is absent. Agent needs to click + to create new patient.

**File**: `task1_blood_type_field.png`
**State**: New patient form showing DoB, PUID, Blood Type, Hospitalized, Hb, Active fields at the bottom of the Main Info section. Blood Type dropdown is present and functional.

**File**: `new_patient_form_step1.png`
**State**: After clicking +, new patient form opens (showing General Info tab with Conditions section).

**File**: `new_patient_form_step2_create.png`
**State**: Typing "Marcus Delgado" shows "Create..." dropdown — patient creation flow confirmed working.

### Task 2: schedule_appointment
**File**: `task2_schedule_appointment_start_state.png`
**State**: Appointments list showing existing demo appointments. No appointment for Ana Betz on 2027-03-15. Doctor: Cordara, Cameron (verified health professional in DB).

### Task 3: create_prescription
**File**: `task3_create_prescription_start_state.png`
**State**: Prescriptions list showing 12 existing prescriptions from demo data. Agent needs to create new Metformin prescription for Ana Betz with doctor Cordara, Cameron.

### Task 4: record_lab_result
**File**: `task4_lab_test_requests_start_state.png`
**State**: Lab Test Requests list showing existing requests from demo data.

**File**: `task4_lab_request_form_hba1c.png`
**State**: New lab test request form filled with:
- Patient: Ana Isabel Betz (Female, 45y)
- Test Type: GLYCATED HEMOGLOBIN (HbA1c) — added to DB in setup_gnuhealth.sh
- Health Prof: Cordara, Cameron
- State: Draft
Agent would save this, then Order it, then enter the HbA1c result value 7.2%.

### Task 5: update_patient_info
**File**: `task5_update_patient_info_start_state.png`
**State**: Patients list. Agent needs to open Ana Betz and update info.

**File**: `task5_socioeconomics_tab.png`
**State**: Socioeconomics tab of the patient health record form (gnuhealth.patient model), showing:
- Occupation field (dropdown linked to gnuhealth_occupation table)
- Education Level field (selection: None/Primary/Secondary/University)
- Housing conditions, SES fields
- Assessments table
Agent sets Occupation="Software engineer", Education Level="University" here.
Then navigates to the party record (via patient name link) to add Mobile/Email contacts.

## Database State Verification
See `db_state_verification.txt` for SQL query results confirming:
- 10 real demo patients loaded (fake test patients removed in setup_gnuhealth.sh)
- Marcus Delgado absent (clean state for register_patient task)
- 12 prescriptions from demo data
- 18+ lab test requests from demo data
- 3501 historical appointment/work-schedule slots from demo data (all 2013–2017)
  - NOTE: These are a mix of real patient appointments AND physician work schedule slots
  - No appointments exist for date 2027-03-15 (far future — clean state for schedule_appointment task)

## Environment Details

### Software Stack
- **GNU Health**: 5.0.x (via PyPI `gnuhealth==5.0.*`)
- **All GNU Health modules**: `gnuhealth-all-modules==5.0.*` (REQUIRED)
- **Trytond**: 7.0.45 (application server)
- **Tryton Sao**: 7.0.x (JavaScript web client)
- **PostgreSQL**: 15 (database, peer auth via Unix socket)
- **Demo Database**: gnuhealth-50-demo.sql.gz (35MB compressed, 271MB uncompressed)

### Access Credentials
- **URL**: http://localhost:8000/
- **Database**: health50
- **Admin user**: admin / gnusolidario
- **Demo doctor**: cmegolsa / gnusolidario

### Demo Patient Data
Key patients from the official "GNU Solidario Hospital" demo:
- **Ana Isabel Betz** (PUID: GNU777ORG) — T1D, BRCA1+, allergies, 10 prescriptions, 18 lab tests, multiple appointments; party_id=2, patient_id=1
- **Matt Zenon Betz** — family member patient
- **Luna** — patient (first name only)
- **Roberto Carlos** — patient
- **Bonifacio Caput** — patient
- 5 other patients

### Health Professionals in DB
Only 3 health professionals exist (gnuhealth_healthprofessional table):
- **Cordara, Cameron** (party_id=5) — used as doctor in all tasks
- **Rainone** (party_id=38)
- **Wilson Greg** (party_id=39)
Ana Isabel Betz is a PATIENT only, NOT a health professional — tasks correctly use Cordara, Cameron.

### 5 Tasks
1. `register_patient` — Create Marcus Delgado as new patient (doctor: Cordara, Cameron)
2. `schedule_appointment` — Schedule Ana Betz appointment on 2027-03-15 09:30 (doctor: Cordara, Cameron)
3. `create_prescription` — Prescribe Metformin 500mg for Ana Betz (doctor: Cordara, Cameron)
4. `record_lab_result` — Order GLYCATED HEMOGLOBIN (HbA1c) lab test for Ana Betz, record result 7.2%
5. `update_patient_info` — Update Ana Betz Socioeconomics (Occupation, Education) + party contacts (Mobile, Email)

## Critical Issues Found During Testing

### 1. bcrypt→scrypt Password Hashes
**Problem**: Demo DB has bcrypt hashes (`$2b$12$...`) but trytond 7.0.45 uses passlib scrypt.
Login raises `AttributeError: type object 'res.user' has no attribute 'check_'`.
**Fix**: `setup_gnuhealth.sh` runs Python psycopg2 script to rehash all 13 user passwords.

### 2. PostgreSQL Peer Auth (Unix Socket)
**Problem**: `postgresql://gnuhealth@localhost/health50` fails with `fe_sendauth: no password supplied`.
**Fix**: `postgresql://gnuhealth@/health50` (no `localhost` = Unix socket = peer auth).

### 3. gnuhealth-all-modules Required
**Problem**: Demo DB activates all 50+ modules; installing only base gnuhealth fails Pool init.
**Fix**: `pip install 'gnuhealth-all-modules==5.0.*'`

### 4. party_party Schema
**Problem**: Initial queries used `pp.name ILIKE '%Ana%Betz%'` assuming full name in `name` column.
**Fix**: GNU Health stores first name in `name` and last name in `lastname` separately. Use: `pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'`

### 5. gnuhealth_patient.party vs .name
**Problem**: Initial queries used `gp.name = pp.id` (JOIN column).
**Fix**: The FK column is `gnuhealth_patient.party` (not `name`).

### 6. Pre_start SSH Timeout
**Problem**: Install script takes 12-18 minutes; framework SSH timeout (~10 min) cuts it off.
**Status**: Script continues in background. `post_start` recreates the systemd service.

### 7. Ana Betz Not a Health Professional (Audit Finding)
**Problem**: Tasks 1-3 specified "Ana Betz" as the doctor — she is only a patient, not a health professional.
**Fix**: Changed all doctor references to "Cordara, Cameron" (actual HP in DB).

### 8. Appointment Date in Past (Audit Finding)
**Problem**: schedule_appointment task used 2025-03-15 (past date as of 2026-02-17).
**Fix**: Changed to 2027-03-15 (well into the future).

### 9. Socioeconomics Tab Navigation (Audit Finding)
**Problem**: Task 5 description unclear about navigation; initial fix incorrectly removed "Socioeconomics tab".
**Clarification**: The gnuhealth.patient form (accessed via Patient module in left sidebar, then patient list) HAS a "Socioeconomics" tab with Occupation and Education Level fields. Contacts (Mobile, Email) are in the party.party record.
**Fix**: Task description now correctly references "Socioeconomics tab" and explains both navigation steps.

### 10. Occupation/Education Reset in setup_task.sh (Audit Finding)
**Problem**: `setup_task.sh` only deleted from `gnuhealth_ses_assessment`. But occupation/education are stored directly on `party_party.occupation` and `party_party.education`.
**Fix**: Added `UPDATE party_party SET occupation = NULL, education = NULL WHERE id = $ANA_PARTY_ID`.

### 11. HbA1c Test Type Missing from DB (Audit Finding)
**Problem**: "HbA1c" test type does not exist in the demo database.
**Fix**: `setup_gnuhealth.sh` now creates "GLYCATED HEMOGLOBIN (HbA1c)" test type with product and component.

### 12. Fake Patients in DB (Audit Finding)
**Problem**: "dodo" (party_id=44) and "Trịnh Trung Kiên 1993" (party_id=45) exist as test entries.
**Fix**: `setup_gnuhealth.sh` now DELETEs these from gnuhealth_patient and party_party after DB restore.
