# OpenMRS O3 Environment — Evidence Documentation

## Environment Overview
- **Application**: OpenMRS Reference Application 3.0 (O3)
- **Type**: Docker-in-QEMU (4 containers behind nginx gateway)
- **URL**: http://localhost/openmrs/spa
- **Admin credentials**: admin / Admin123
- **REST API**: http://localhost/openmrs/ws/rest/v1/

## Container Status (during testing)
```
NAME                 IMAGE                                                    STATUS
openmrs-backend-1    openmrs/openmrs-reference-application-3-backend:3.0.0   Up (healthy)
openmrs-db-1         mariadb:10.11.7                                          Up (healthy)
openmrs-frontend-1   openmrs/openmrs-reference-application-3-frontend:3.0.0  Up (healthy)
openmrs-gateway-1    openmrs/openmrs-reference-application-3-gateway:3.0.0   Up
```

## Setup Screenshots

| File | Description |
|------|-------------|
| 01_login_page.png | OpenMRS O3 login page (username step) |
| 02_login_with_username.png | Login page with "admin" username entered |
| 03_password_entry.png | Password entry step of two-step login |
| 04_location_selection.png | Location selection page (Outpatient Clinic) |
| 05_dashboard.png | OpenMRS home dashboard with active visits and appointments |

## Task Start State Screenshots

All 10 task start state screenshots captured from live VM (SSH port 2338, VNC :184):

| File | Task | Patient | Verified |
|------|------|---------|----------|
| task_01_register_patient.png | register_patient | Patient registration form | Patient registration form visible with First Name, Family Name, Sex, DOB fields |
| task_02_record_vitals.png | record_vitals | Larissa Kuhic (31F) | Patient chart open, Active Visit badge, vitals section EMPTY ("No vital signs to display") |
| task_03_start_visit.png | start_visit | Shalanda Parker (30F) | Patient chart open, "Start a visit" button in top right |
| task_04_end_visit.png | end_visit | Dwana West (39F) | Patient chart open, Active Visit badge, "End visit" button in top right |
| task_05_add_allergy.png | add_allergy | Clarinda Rolfson (45F) | Allergies tab open, "Record allergy intolerances" link visible |
| task_06_order_lab_test.png | order_lab_test | Paul Tremblay (48M) | Patient Summary, Active Visit, vitals visible |
| task_07_add_diagnosis.png | add_diagnosis | Ezekiel Walter (27M) | Patient Summary, Active Visit badge visible |
| task_08_record_medication.png | record_medication | Eliseo Nader (52M) | Medications tab open, Active Visit badge, both medication sections empty |
| task_09_update_patient_info.png | update_patient_info | Angel Barrows (50F) | Patient edit form with Basic Info section, Contact Details in sidebar |
| task_10_add_appointment.png | add_appointment | Jona Botsford (67F) | Patient chart open with demographics (Female, 67 yrs, DOB 02-Apr-1958) clearly shown |

## Seeded Patients (10 Synthea-derived patients)

Generated via `java -jar /tmp/synthea.jar -p 20 --exporter.csv.export=true -s 42`, selecting 10 demographically diverse patients.

| Patient | DOB | Gender | Task Role |
|---------|-----|--------|-----------|
| Ezekiel Walter | 1998-05-31 | M | add_diagnosis (Hypertension, BP 144/92) |
| Larissa Kuhic | 1994-09-10 | F | record_vitals |
| Shalanda Parker | 1995-11-04 | F | start_visit |
| Dwana West | 1986-03-30 | F | end_visit |
| Paul Tremblay | 1977-07-03 | M | order_lab_test (CBC) |
| Eliseo Nader | 1973-05-31 | M | record_medication (Aspirin 81mg) |
| Clarinda Rolfson | 1980-11-16 | F | add_allergy (Bee venom → Hives, Mild) |
| Angel Barrows | 1975-03-10 | F | update_patient_info (phone 617-555-0143) |
| Jona Botsford | 1958-04-02 | F | add_appointment (General Medicine, 30 min) |
| (Meredith Voss) | 1989-03-22 | F | register_patient target (not pre-created) |

## Setup Log Snippets

### Seed script success (seed_openmrs.py)
```
=== Seeding OpenMRS O3 with Synthea-derived patient data ===
Loading Synthea patient data from /workspace/data/...
Checking Ezekiel Walter... Creating...  -> UUID: a3e9146a-db44-4f34-8c0f-d608c9b0eb6f
Checking Larissa Kuhic... Creating...   -> UUID: 952e492b-b0e4-4f90-b3aa-712ce79d3221
Checking Shalanda Parker... Creating... -> UUID: 2b52e378-9d55-4c5f-8a84-7d5ac3200043
Checking Dwana West... Creating...      -> UUID: d5a1965a-505c-44bd-a397-e5717934d8cd
Checking Paul Tremblay... Creating...   -> UUID: 3f7726da-438e-45f0-8ab6-4be8e7f50e18
Checking Eliseo Nader... Creating...    -> UUID: aa7c9079-db52-4b34-a72c-40c1301062ce
Checking Clarinda Rolfson... Creating.. -> UUID: c3816408-059a-4b04-b815-b93bf707df48
Checking Angel Barrows... Creating...   -> UUID: a342d3eb-d40d-493e-98bd-3cee5afeba39
Checking Jona Botsford... Creating...   -> UUID: 664d1d6a-4524-42cd-b92b-bbb11c22fb57
...
Created past visit with vitals for Ezekiel Walter
Created past visit with vitals for Larissa Kuhic
...
=== Seeding complete ===
```

### Task setup script success (example: record_vitals)
```
=== Setting up record_vitals task ===
Locating Larissa Kuhic...
Patient UUID: 952e492b-b0e4-4f90-b3aa-712ce79d3221
Closing any existing open visits...
Creating active visit...
Active visit UUID: d702e3f5-5af1-49aa-83f3-56137e77df10
Starting Firefox on http://localhost/openmrs/spa/login ...
Waiting for window: firefox|mozilla|OpenMRS (30s max)...
  Window found after 0s
  Login complete. Navigating to task URL: http://localhost/openmrs/.../chart/Patient%20Summary
Screenshot: /tmp/task_start_screenshot.png

=== record_vitals task setup complete ===

TASK: Record vitals for Larissa Kuhic
  Weight: 76.5 kg | Height: 163 cm | Temp: 37.1°C
  Pulse: 68 | BP: 119/81 | SpO2: 98%
```

## Key UUIDs (from system)
- OpenMRS ID Type: `05a29f94-c0ed-11e2-94be-8c13b969e334`
- idgen Source: `8549f706-7e85-4c1d-9424-217d50a2988b`
- Outpatient Clinic Location: `44c3efb0-2583-4c80-a79e-1f756a03c0a1`
- Facility Visit Type: `7b0f5697-27e3-40c4-8bae-f4049abfb4ed`
- Vitals Encounter Type: `67a71486-1a54-468f-ac3e-7091a9a79584`
