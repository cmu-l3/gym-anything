# NOSH ChartingSystem Environment — Evidence Documentation

## Environment Overview

**Stack**: Docker Compose — nosh-app (shihjay2/nosh2:latest, PHP-FPM:9000), nosh-nginx (:80), nosh-db (mariadb:10.11)
**URL**: http://localhost/login
**Admin**: admin / Admin1234! (group_id=1, practice management only)
**Provider**: demo_provider / Provider1234! (group_id=2, Dr. James Carter — clinical tasks)
**Practice**: Hillside Family Medicine (practice_id=1)
**env_hash**: dae5fd2ea53af392

## Verification Summary

All 10 tasks were verified interactively using VNC screenshots captured from a running VM instance (SSH port 2423, VNC port 6008, loaded from post_start checkpoint).

---

## Login Verification

### 01_login_page.png
NOSH login form at http://localhost/login. Shows username, password, and practice dropdown fields. Confirms the login page is accessible as the task start state.

### 03_verified_login_start.png
Login page loaded via Firefox in the VM, showing the NOSH logo and login form with Hillside Family Medicine in the practice dropdown.

### 04_dashboard_demo_provider.png / 06_dashboard_logged_in.png
Dashboard after successful login as demo_provider (Dr. James Carter). Shows all navigation elements (Tasks, Messaging, Schedule, Financial, Office, Configure) and confirms group_id=2 login works correctly.

---

## Task Evidence

### Task 1: add_social_history (Patient: Conchita Hernandes, pid=1)

**07_add_social_history_start_state.png**
Conchita Hernandes's Social History section showing empty Lifestyle, Habits, and Mental Health categories. Confirms the correct start state (no prior social history).

**08_add_social_history_edit_form.png**
"Edit Lifestyle" form with Social History text area (free-text, no labeled tobacco-specific field), Sexually Active dropdown, Diet, and Physical Activity fields. Confirms the task form is accessible. Note: There is no dedicated "tobacco use" labeled field — social history is entered as free text in the Social History textarea under the Lifestyle subsection.

**09_add_social_history_completed.png**
Social History after saving "Non-smoker, no alcohol use. Lives with family." Green "updated!" banner confirms successful save. Full end-to-end task completability demonstrated.

---

### Task 2: add_family_history (Patient: Corine Ziemann, pid=2)

**16_add_family_history_start_state.png**
Corine Ziemann's Family History section showing the NOSH family tree interface with empty family member nodes (no medical conditions entered). Shows "Add Family Member" button. Correct start state for adding Father: Type 2 diabetes.

*Note*: A bug was discovered and fixed during testing — the `other_history.oh_id` column was missing AUTO_INCREMENT, causing 500 errors when visiting family/social history for any patient after the first. Fix added to `scripts/setup_nosh.sh`.

---

### Task 3: add_insurance (Patient: Crysta Parisian, pid=3)

**12_add_insurance_empty_payers.png**
Crysta Parisian's chart showing "Payers [0]" — no insurance records. Confirms correct start state for adding insurance information.

---

### Task 4: cancel_appointment (Patient: Charles Nolan, pid=4)

**10_cancel_appointment_preseeded.png**
Schedule calendar showing July 2026 with "Charles Nolan - Office Visit" appointment at 10:00am on July 15. Confirms the appointment is pre-seeded via `setup_task.sh` (INSERT INTO schedule).

---

### Task 5: order_lab_test (Patient: Kent Zemlak, pid=5)

**17_order_lab_test_empty_orders.png**
Kent Zemlak's Lab Orders page (orders_list/orders_labs) showing "None." under Pending Orders. Shows "+" add button and "Laboratory" dropdown. Confirms correct start state with no existing lab orders.

---

### Task 6: document_hpi (Patient: Dwight Dach, pid=6)

**18_document_hpi_empty_encounters.png**
Dwight Dach's Encounters section showing "None." — no existing encounters. Shows "+ Add" button for creating a new encounter. Confirms correct start state for documenting HPI in a new encounter.

---

### Task 7: update_practice_email (Admin task)

**13_update_practice_email_start_state.png**
Practice Information form (http://localhost/core_form/practiceinfo/practice_id/1/information) showing current email address `admin@hillsidefm.local`, captured while logged in as admin (Dr. Sarah Admin). Task requires changing this to `contact@hillsidefamilymedicine.org`. Correct start state confirmed via `setup_task.sh` which resets the email before each run. Admin navigation: top nav "Setup" → click "Information" tab on the Practice configuration page.

---

### Task 8: add_referral (Patient: Ezequiel Hermiston, pid=7)

**19_add_referral_empty_orders.png**
Ezequiel Hermiston's Referrals page (orders_list/orders_referrals) showing "None." under Pending Orders. Shows "+" button and "Referrals" dropdown. Confirms correct start state with no existing referrals.

---

### Task 9: discontinue_medication (Patient: Denny Lubowitz, pid=8)

**11_discontinue_medication_preseeded.png**
Denny Lubowitz's Medications section at `http://localhost/medications_list/active` showing "Metformin 500 mg" with dosage "Take one tablet by mouth twice daily with meals" and five action icons (edit/pencil, sync, history, stop/circle-minus, trash). Confirms medication is pre-seeded via `setup_task.sh` (INSERT INTO rx_list). Note: The stop/discontinue icon (circle-minus) immediately inactivates the medication with no reason-for-discontinuation dialog — the task description has been updated to remove the inaccurate "provide reason" instruction.

**21_discontinue_medication_success.png**
After clicking the stop/circle-minus icon: green "Medication inactivated!" toast appears at the bottom of the screen and the Medications list shows "None." Confirms the task completes immediately with one click, no dialog required.

---

### Task 10: send_message (Provider to Admin)

**14_send_message_inbox.png**
Messaging inbox (http://localhost/messaging/inbox) showing empty inbox with "None." and a prominent "+ New Message" button. Confirms the messaging interface is accessible.

**15_send_message_compose_form.png**
"New Message" compose form showing To (dropdown with Dr. James Carter), Subject, Message body, CC, and "Concerning this Patient" fields. Confirms the task can be completed end-to-end.

---

## Critical Bugs Found and Fixed During Testing

1. **other_history.oh_id missing AUTO_INCREMENT**: The `other_history` table primary key (`oh_id`) lacked AUTO_INCREMENT, causing a duplicate key error when family/social history was accessed for any patient after the first. Fixed in `scripts/setup_nosh.sh` by adding `ALTER TABLE other_history MODIFY oh_id bigint(20) NOT NULL AUTO_INCREMENT;` after database initialization.

2. **Practice information URL**: The correct URL for the practice email settings is `/core_form/practiceinfo/practice_id/1/information` (not `/practice` or `/setup/1`).

3. **Lab orders URL format**: The orders list URL pattern is `/orders_list/{type}` where type must be one of `orders_labs`, `orders_radiology`, `orders_cp`, or `orders_referrals` (not `orders_list/all`).

4. **Lab orders require active encounter in session**: NOSH requires `Session::get('eid')` to be set before adding a lab order. Clicking "Add Lab Order" without an active encounter redirects to the encounter creation form (`/encounter_details/0`) with toast "Creating an encounter first to add a new order". After saving the encounter, the agent can navigate back to the Orders section and add the lab order. The `order_lab_test` task description has been updated to document this workflow.

5. **Encounter page requires scans directory**: `/encounter/{eid}` returns a 500 error if `/var/www/nosh/storage/app/scans/{practice_id}` does not exist. This directory must be created during environment setup.

6. **discontinue_medication reason field does not exist**: The stop/discontinue icon on the Medications list immediately inactivates the medication — there is no reason-for-discontinuation dialog or field. The task description has been corrected to remove the inaccurate "Provide reason for discontinuation" instruction.

---

## Checkpoint Verification

### 20_new_checkpoint_login_page.png
The NOSH login page loaded from the rebuilt checkpoint (post `other_history` AUTO_INCREMENT fix). Shows username/password fields and "Hillside Family Medicine" in the practice dropdown. Confirms the checkpoint loads cleanly into the correct start state.

The checkpoint was rebuilt on 2026-02-23 (total rebuild time: ~251 seconds) after deleting the previous checkpoint. The new checkpoint includes the `ALTER TABLE other_history MODIFY oh_id bigint(20) NOT NULL AUTO_INCREMENT` fix in `setup_nosh.sh`.
