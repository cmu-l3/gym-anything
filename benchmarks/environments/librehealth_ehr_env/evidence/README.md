# LibreHealth EHR Environment — Evidence Documentation

## Environment Overview

- **Application**: LibreHealth EHR v2.0.0 (open-source Electronic Health Records)
- **Deployment**: Docker-in-QEMU (PHP 7.2 + Apache2 + MariaDB 10.11), port 8000
- **Patient Data**: 9,375 real NHANES patients (National Health and Nutrition Examination Survey)
  - Source: `LibreHealthIO/lh-ehr` GitHub repository, `sql/nhanes/libreehr_nhanes.sql.gz`
- **Admin credentials**: `admin` / `password`
- **NHANES DB import log snippet**:
  ```
  Importing NHANES data into MariaDB...
  NHANES import complete. Patients loaded: 9375
  Updated admin password: 1 rows
  Verify: YES - login ready
  LibreHealth EHR is ready after 15s (HTTP 200)
  ```

## Target Patients (NHANES Real Data)

| Task | Patient | PID | DOB |
|------|---------|-----|-----|
| `update_patient_demographics` | Erin Warren | 2 | 2013-09-13 |
| `add_medical_problem` | Allan Thomas | 782 | 1984-07-15 |
| `add_appointment` | Clifford Taylor | 8471 | 1984-08-15 |

## Screenshots

### `00_login_page.png`
LibreHealth EHR login page at `http://localhost:8000/interface/login/login.php?site=default`.
Shows the clean login form with Username/Pass Phrase fields and the LibreHealth logo.
This is the start state for all tasks (Firefox opens to this URL).

### `01_register_new_patient_start.png`
Main dashboard after login (`admin`/`password`).
- Left panel: **Patient Finder** with NHANES patient list (Abbott, Acevedo visible — 9,375 total)
- Right panel: **Calendar** showing February 2026, one appointment ("University of Central Florida" at 12:30pm)
- Top nav: Calendar, Flow Board, Messages, Patient/Client, Fees, etc.
- This is the start state for the `register_new_patient` task.

### `02_add_appointment_start.png`
Calendar/appointment view (Calendar tab → full calendar).
- Shows **February 18, 2026** day view with time slots
- Two columns: "A Student" and "Administrator Administrator"
- Pre-existing NHANES appointment: "University of Central Florida" at 12:30pm
- Left panel: calendar controls with user filter (All Users, Administrator, Hoyt Robert, Student A)
- This is the start state for the `add_appointment` task (agent searches for "Taylor" → Clifford Taylor, PID=8471).

### `03_add_medical_problem_start.png`
Patient search/select page (Patient/Client tab).
- **Patient Finder** table with Last Name, First Name, Home Phone, SSN, Date of Birth, Patient ID columns
- Search boxes at top of each column for filtering
- NHANES patients listed alphabetically (Abbott, Acevedo visible)
- This is the start state for the `add_medical_problem` task (agent searches "Thomas" → Allan Thomas, PID=782).

### `04_update_demographics_start.png`
Patient search/select page (identical layout to 03).
- Same Patient Finder interface
- This is the start state for the `update_patient_demographics` task (agent searches "Warren" → Erin Warren, PID=2).

### `05_write_prescription_start.png`
Patient search/select page (identical layout to 03-04).
- Same Patient Finder interface
- This is the start state for the `write_prescription` task.

## Key Technical Notes

- **Firefox navigation**: Snap Firefox (Ubuntu). Navigate using header tabs (Calendar, Patient/Client) from the logged-in dashboard. Direct URL typing via address bar causes redirect loops (LibreHealth uses relative redirects).
- **Session persistence**: Firefox session cookies are in-memory only; restarting Firefox requires re-login.
- **Admin password**: NHANES SQL dump contains a different bcrypt hash for admin. The `setup_librehealth.sh` post_start hook resets it via `docker exec librehealth-app php -r '...'`.
- **NHANES import**: Must run BEFORE starting `lh-ehr` app container. The SQL is a complete dump (DROP TABLE + CREATE TABLE), so no schema pre-init is needed.

## Database Verification

```sql
-- Patient count
SELECT COUNT(*) FROM patient_data;  -- 9375

-- Target patients
SELECT pid, CONCAT(fname,' ',lname), dob FROM patient_data WHERE pid IN (2, 782, 8471);
-- 2    Erin Warren      2013-09-13
-- 782  Allan Thomas     1984-07-15
-- 8471 Clifford Taylor  1984-08-15

-- Admin password verified
-- password_verify("password", hash) -> YES
```

## Docker Container Status

```
CONTAINER ID   IMAGE             STATUS          PORTS
librehealth-app  librehealth/ehr   Up (healthy)    0.0.0.0:8000->80/tcp
librehealth-db   mariadb:10.11     Up (healthy)    3306/tcp
librehealth-adminer adminer       Up              0.0.0.0:8001->8080/tcp
```
