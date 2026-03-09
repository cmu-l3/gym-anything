# FreeMED Environment — Evidence Documentation

Verified working on: 2026-02-22
FreeMED version: 0.9.0-rc1
Stack: LAMP (Ubuntu 22.04, Apache 2.4, MySQL 8.0, PHP 7.4, Dojo UI)
URL: http://localhost/freemed/ (port 80)
Admin credentials: admin / admin
Patient data: 20 Synthea-generated patients (Massachusetts cohort)

## Environment Overview

FreeMED is an open-source Electronic Medical Records (EMR) system. This environment runs
the LAMP version (NOT Docker — Docker manifest v1 format is unsupported in containerd 1.7+).
PHP 7.4 is required (PHP 8.x breaks `${var}` variable-variable syntax used in FreeMED 0.9.0).

### Patient Dataset

20 synthetic patients from Synthea v3 (https://github.com/synthetichealth/synthea):

| ID | Name | DOB | Sex |
|----|------|-----|-----|
| 1 | Conchita Hernandes | 2006-12-04 | F |
| 2 | Corine Ziemann | 2000-11-29 | F |
| 3 | Crysta Parisian | 2005-03-26 | F |
| 4 | Charles Nolan | 2003-11-02 | M |
| 5 | Kent Zemlak | 2001-02-16 | M |
| 6 | Dwight Dach | 1998-03-21 | M |
| 7 | Ezequiel Hermiston | 2002-05-19 | M |
| 8 | Denny Lubowitz | 2000-07-04 | F |
| 9 | Kelle Crist | 2002-10-18 | F |
| 10 | Sherill Botsford | 1995-01-24 | F |
| 11 | Hobert Wuckert | 2000-10-27 | M |
| 12 | Malka Hartmann | 1994-11-26 | F |
| 13 | Cordie King | 1995-03-11 | F |
| 14 | Coreen Treutel | 1990-07-20 | F |
| 15 | Tracey Crona | 1981-07-02 | M |
| 16 | Myrtis Armstrong | 1985-04-08 | F |
| 17 | Arlie McClure | 1971-03-06 | M |
| 18 | Crystal Schroeder | 1972-07-19 | F |
| 19 | Luann Sanford | 1977-03-26 | F |
| 20 | Horacio Santacruz | 1954-02-19 | M |

## Screenshots

### Environment Evidence

| File | Description | Notes |
|------|-------------|-------|
| `00_initial_state.png` | FreeMED login page (initial VM state) | URL: `http://localhost/freemed/controller.php/dojo/org.freemedsoftware.ui.login`; login with admin/admin |
| `demo_02_after_login.png` | FreeMED Dashboard after login | Shows Dashboard page with left sidebar: Day Schedule, Book Appointment, Scheduler, Messaging; Patients section at bottom left; "Logoff" button confirms user is authenticated |
| `nav_03_freemed_main.png` | FreeMED main navigation | System Configuration view with Patient Entry, Call-in menu items |
| `nav_06_patients_module.png` | Patients module - Today's Patients view | Shows "Today's Patients" with table headers: Time, Duration, Patient, Provider, Status; left nav shows Patients>Search, Patient Entry, Call-in |
| `nav_11_armstrong_results.png` | Patient search - "Patient Search: 20 Patient(s) in the System" | Smart Search shows autocomplete: "Armstrong, Myrtis Gladys \| 1985-04-08" confirming Synthea patient is in system |
| `nav_19_patient_chart_final.png` | Myrtis Armstrong patient chart | Full chart view for "Patient: Armstrong, Myrtis Gladys [1985-04-08]" with Clinical Information, Patient Tags, Patient Tasks panels; confirms Synthea DOB matches task metadata |
| `demo_patient_list.txt` | Complete patient database list | 20 Synthea patients with IDs, names, DOBs, sex verified via MySQL query |

### Task Start-State Screenshots

All 10 tasks verified with exit code 0. Each task starts with the FreeMED login page,
requiring the agent to log in and navigate to the appropriate patient.

| File | Task | Patient | Clinical Details |
|------|------|---------|-----------------|
| `01_add_immunization_start.png` | add_immunization | Malka Hartmann (ID 12) | Add Td (adult) vaccine, 2024-11-15, Lot TD2024-892, Sanofi Pasteur |
| `02_add_allergy_start.png` | add_allergy | Myrtis Armstrong (ID 16) | Add Ibuprofen allergy, Skin rash and hives, Moderate severity |
| `03_record_vital_signs_start.png` | record_vital_signs | Tracey Crona (ID 15) | BP 119/73 mmHg, HR 70/min, Temp 98.4°F, Wt 160lbs, Ht 61in (Synthea 2023-10-19 encounter) |
| `04_register_new_patient_start.png` | register_new_patient | Garfield Lebsack (new) | DOB 1962-05-16, M, 393 Mertz Crossing Apt 28, Ludlow MA 01056; Synthea patient NOT in DB |
| `05_schedule_appointment_start.png` | schedule_appointment | Coreen Treutel (ID 14) | 2025-06-20, 09:00 AM, Office Visit, 30 min |
| `06_add_problem_diagnosis_start.png` | add_problem_diagnosis | Arlie McClure (ID 17) | Chronic Low Back Pain, ICD-9 724.2, SNOMED 278860009, onset 2014-02-03 |
| `07_write_prescription_start.png` | write_prescription | Crystal Schroeder (ID 18) | Naproxen Sodium 220mg, 1 tablet twice daily, 30 tablets, 0 refills |
| `08_update_patient_demographics_start.png` | update_patient_demographics | Luann Sanford (ID 19) | Change phone to 617-555-9283, email to luann.s.updated@healthmail.test, address to 127 Franklin St, Springfield MA |
| `09_add_clinical_note_start.png` | add_clinical_note | Horacio Santacruz (ID 20) | Post-MI SOAP note; A: Ischemic heart disease post-MI (Synthea: MI on 2026-01-02) |
| `10_add_referral_start.png` | add_referral | Hobert Wuckert (ID 11) | Orthopedic Surgery referral (Dr. Kevin Ramirez), right knee meniscal tear, 2025-05-10 |

### Setup Logs

| File | Task | Exit Code |
|------|------|-----------|
| `01_add_immunization_setup.log` | add_immunization | 0 (PASS) |
| `02_add_allergy_setup.log` | add_allergy | 0 (PASS) |
| `03_record_vital_signs_setup.log` | record_vital_signs | 0 (PASS) |
| `04_register_new_patient_setup.log` | register_new_patient | 0 (PASS) |
| `05_schedule_appointment_setup.log` | schedule_appointment | 0 (PASS) |
| `06_add_problem_diagnosis_setup.log` | add_problem_diagnosis | 0 (PASS) |
| `07_write_prescription_setup.log` | write_prescription | 0 (PASS) |
| `08_update_patient_demographics_setup.log` | update_patient_demographics | 0 (PASS) |
| `09_add_clinical_note_setup.log` | add_clinical_note | 0 (PASS) |
| `10_add_referral_setup.log` | add_referral | 0 (PASS) |

**All 10/10 tasks pass setup with exit code 0.**

### Clean Test Screenshots (Fresh VM - use_cache=False)

| File | Task | Verified |
|------|------|---------|
| `clean_01_add_immunization.png` | add_immunization | Login page (FreeMED 0.9.0-rc1) |
| `clean_02_add_allergy.png` | add_allergy | Login page |
| `clean_03_record_vital_signs.png` | record_vital_signs | Login page |
| `clean_04_register_new_patient.png` | register_new_patient | Login page |
| `clean_05_schedule_appointment.png` | schedule_appointment | Login page |
| `clean_06_add_problem_diagnosis.png` | add_problem_diagnosis | Login page |
| `clean_07_write_prescription.png` | write_prescription | Login page |
| `clean_08_update_patient_demographics.png` | update_patient_demographics | Login page |
| `clean_09_add_clinical_note.png` | add_clinical_note | Login page |
| `clean_10_add_referral.png` | add_referral | Login page |

Clean test environment: PHP 7.4.33, Apache/2.4.52, MySQL 8.0.45 — full install from `use_cache=False` in ~110s.

## Task Start State

All tasks begin with the FreeMED login page:
```
URL: http://localhost/freemed/controller.php/dojo/org.freemedsoftware.ui.login
Credentials: admin / admin
```

The `ensure_firefox_running` function in `task_utils.sh` opens Firefox to the FreeMED
homepage which redirects to the login page. This is a deterministic start state.

## Clinical Data Sources

Patient records use real Synthea v3 clinical data:
- **Myrtis Armstrong (ID 16)**: Synthea record includes Ibuprofen allergy → `add_allergy` task
- **Tracey Crona (ID 15)**: Synthea 2023-10-19 encounter: BP 119/73, HR 70/min, wt 72.7kg → `record_vital_signs`
- **Arlie McClure (ID 17)**: Synthea condition: Chronic low back pain (SNOMED 278860009, onset 2014-02-03) → `add_problem_diagnosis`
- **Crystal Schroeder (ID 18)**: Synthea medication: Naproxen sodium 220mg oral tablet (2024-02-10) → `write_prescription`
- **Malka Hartmann (ID 12)**: Synthea immunization records → `add_immunization`
- **Horacio Santacruz (ID 20)**: Synthea conditions: ischemic heart disease, MI → `add_clinical_note`
- **Garfield Lebsack**: Synthea patient #21 (NOT pre-loaded, ID assigned on creation) → `register_new_patient`

## Key Implementation Notes

### PHP 7.4 Required
FreeMED 0.9.0-rc1 uses `${var}` variable-variable syntax removed in PHP 8.3:
```php
// Works in PHP 7.4, breaks in PHP 8.3
if (!isset($$var_name)) { $$var_name = ...; }
```
PHP 7.4 is installed from `ppa:ondrej/php` and set as default.

### API.php Fix
`get_magic_quotes_runtime()` and `define_syslog_variables()` are PHP built-ins that
conflict with FreeMED's declarations. Fixed with `function_exists()` guard.

### Schema Loading
SQL files contain `SOURCE` directives causing recursive failures. Fixed with:
```bash
grep -v '^SOURCE' file.sql | mysql freemed
```

### Dojo UI (NOT GWT)
FreeMED has two UIs: Dojo (PHP-based, works) and GWT (requires Maven + GWT SDK Java
compilation, `ui/gwt/www/` doesn't exist in repo). Only Dojo UI is usable.

### XAUTHORITY
All xdotool/wmctrl/import commands must use:
```bash
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority
```
`~/.Xauthority` is 0 bytes and silently breaks GUI commands.

### Snap Firefox
Firefox installed via snap; profile at:
`/home/ga/snap/firefox/common/.mozilla/firefox/freemed.profile/`
Snap directory permissions: `chown -R ga:ga /home/ga/snap/` before launch.
