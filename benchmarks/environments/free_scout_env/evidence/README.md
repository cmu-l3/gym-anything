# FreeScout Environment - Evidence Documentation

## Verification Checklist

### Installation & Setup

- [x] **Installation script completes without errors**
  - `install_freescout.sh` installs Docker, docker-compose, Firefox, wmctrl, xdotool, imagemagick, jq, PyMySQL
  - Pre-pulls `mariadb:10.11` and `tiredofit/freescout:latest` images

- [x] **Setup script completes without errors**
  - `setup_freescout.sh` starts docker-compose, waits for MariaDB and FreeScout HTTP 200
  - Configures Firefox snap profile with sidebar disabled
  - Launch -> kill -> configure -> relaunch pattern for snap Firefox

- [x] **Application is visible in screenshot**
  - See `01_login_page.png` - FreeScout login page at http://localhost:8080/login

- [x] **Application is in correct initial state**
  - See `02_dashboard.png` - Logged in as Admin, FreeScout Dashboard with "Manage Mailboxes" button (no mailbox created yet at this point)

---

### Task 1: assign_conversation (Score: 100/100)

- [x] **Task setup runs without errors**
  - Creates customer Frank Sherman with email floresbryan@example.net
  - Creates "Payment issue" conversation in Support mailbox, unassigned
- [x] **Conversation visible in Unassigned folder**
  - See `10_assign_task_start.png` - "Payment issue" from Frank Sherman in Unassigned
- [x] **Conversation opened and viewed**
  - See `11_assign_conv_opened.png` - Conversation detail with "Anyone" dropdown
- [x] **Assignment succeeds**
  - See `12_assign_conv_assigned.png` - Dropdown shows "Me" (Admin User)
- [x] **Export script produces valid JSON**

```json
{
    "conversation_found": true,
    "conversation_id": "3",
    "conversation_subject": "Payment issue",
    "is_assigned": true,
    "assignee_user_id": "1",
    "assignee_first_name": "Admin",
    "assignee_last_name": "User",
    "assignee_email": "admin@helpdesk.local",
    "timestamp": "2026-02-11T16:31:35+00:00"
}
```

- [x] **Verifier returns 100/100**

```
Score: 100/100
Passed: True
Feedback: Conversation found in database | Correct conversation:
          'Payment issue' |
          Conversation is assigned to an agent |
          Assigned to correct agent: 'Admin User'
```

---

### Task 2: update_customer_profile (Score: 100/100)

(Renamed from `create_customer` — task is actually an UPDATE of an existing customer's name fields)

- [x] **Task setup runs without errors**
  - Pre-creates customer with email only (no name), navigates to edit page
- [x] **Customer edit page loads with email pre-filled, name fields empty**
  - See `13_customer_edit_empty_start.png` - Empty First Name and Last Name fields, email pre-populated
- [x] **Agent fills in First Name and Last Name via GUI**
  - See `03_customer_edit_filled.png` - Christina Dillon filled in
- [x] **Save Profile succeeds**
  - See `04_customer_saved_success.png` - Green "Customer saved successfully" banner
- [x] **Export script produces valid JSON**

```json
{
    "initial_count": 0,
    "current_count": 1,
    "customer_found": true,
    "customer_id": "1",
    "customer_first_name": "Christina",
    "customer_last_name": "Dillon",
    "customer_email": "bradleyolson@example.org",
    "timestamp": "2026-02-11T05:46:28+00:00"
}
```

- [x] **Verifier returns 100/100**

```
Score: 100/100
Passed: True
Feedback: Customer found in database | First name matches: 'Christina' |
          Last name matches: 'Dillon' | Email unchanged: 'bradleyolson@example.org'
```

---

### Task 3: create_user (Score: 100/100)

- [x] **Task setup runs without errors**
  - Records initial user count, navigates to homepage
- [x] **Navigate to Manage > Users > New User**
  - See `05_new_user_form.png` - Form with Role, First Name, Last Name, Email fields
- [x] **Agent fills in user details via GUI**
- [x] **Create User succeeds**
  - See `06_user_created_success.png` - Redirected to user profile page
- [x] **Export script produces valid JSON**

```json
{
    "initial_count": 1,
    "current_count": 2,
    "user_found": true,
    "user_id": "2",
    "user_first_name": "Rebecca",
    "user_last_name": "Fleming",
    "user_email": "rebecca.fleming@helpdesk.local",
    "user_role": "user",
    "timestamp": "2026-02-11T05:54:09+00:00"
}
```

- [x] **Verifier returns 100/100**

```
Score: 100/100
Passed: True
Feedback: User count increased: 1 -> 2 | User found in database |
          First name matches: 'Rebecca' | Last name matches: 'Fleming' |
          Email matches: 'rebecca.fleming@helpdesk.local' |
          Role correctly set to 'user'
```

---

### Task 4: create_conversation (Score: 100/100)

- [x] **Task setup runs without errors**
  - Ensures mailbox exists, records initial conversation count
- [x] **Navigate to mailbox > New Conversation**
- [x] **Agent fills in To, Subject, and message body via GUI**
- [x] **Send succeeds**
  - See `08_conversation_sent.png` - Green "Email Sent" banner with View/Undo options
- [x] **Export script produces valid JSON**

```json
{
    "initial_count": 1,
    "current_count": 2,
    "conversation_found": true,
    "conversation_id": "2",
    "conversation_number": "2",
    "conversation_subject": "Peripheral compatibility",
    "conversation_status": "2",
    "conversation_mailbox_id": "1",
    "thread_count": 1,
    "customer_email": "clarkeashley@example.com",
    "timestamp": "2026-02-11T05:59:32+00:00"
}
```

- [x] **Verifier returns 100/100**

```
Score: 100/100
Passed: True
Feedback: Conversation count increased: 1 -> 2 | Conversation found in database |
          Subject matches: 'Peripheral compatibility' |
          Customer email matches: 'clarkeashley@example.com' |
          Message body written (1 thread(s)) | Mailbox assigned (id=1)
```

---

### Task 5: create_mailbox (Score: 100/100)

- [x] **Task setup runs without errors**
  - Records initial mailbox count, navigates to homepage
- [x] **Navigate to Manage > Mailboxes > New Mailbox**
- [x] **Agent fills in Email Address and Mailbox Name via GUI**
- [x] **Create Mailbox succeeds**
  - See `09_mailbox_created.png` - Green "Mailbox created successfully" banner
- [x] **Export script produces valid JSON**

```json
{
    "initial_count": 1,
    "current_count": 2,
    "mailbox_found": true,
    "mailbox_id": "2",
    "mailbox_name": "Technical Support",
    "mailbox_email": "techsupport@helpdesk.local",
    "timestamp": "2026-02-11T06:03:19+00:00"
}
```

- [x] **Verifier returns 100/100**

```
Score: 100/100
Passed: True
Feedback: Mailbox count increased: 1 -> 2 | Mailbox found in database |
          Name matches: 'Technical Support' | Email matches: 'techsupport@helpdesk.local'
```

---

## Screenshots Index

| File | Description |
|------|-------------|
| `01_login_page.png` | FreeScout login page after environment setup |
| `02_dashboard.png` | Dashboard after admin login, "Manage Mailboxes" button (pre-mailbox state) |
| `03_customer_edit_filled.png` | Customer edit form with Christina/Dillon filled in (update_customer_profile) |
| `04_customer_saved_success.png` | Customer saved success banner (update_customer_profile) |
| `05_new_user_form.png` | New User form filled with Rebecca Fleming (create_user) |
| `06_user_created_success.png` | User profile page after creation (create_user) |
| `07_create_user_verified.png` | End state after create_user export (create_user) |
| `08_conversation_sent.png` | Email Sent banner (create_conversation) |
| `09_mailbox_created.png` | Mailbox created success banner (create_mailbox) |
| `10_assign_task_start.png` | Inbox with "Payment issue" unassigned (assign_conversation) |
| `11_assign_conv_opened.png` | Conversation detail with "Anyone" assignee (assign_conversation) |
| `12_assign_conv_assigned.png` | Conversation assigned to "Me" (Admin User) (assign_conversation) |
| `13_customer_edit_empty_start.png` | Customer edit form with empty name fields, task-start state (update_customer_profile) |

## Environment Details

- **Base Image**: `ubuntu-gnome-systemd_highres` (1920x1080)
- **Docker Containers**: `freescout-app` (port 8080:80) + `freescout-db` (MariaDB 10.11)
- **Admin Credentials**: admin@helpdesk.local / Admin123!
- **Database**: freescout / freescout123 (MariaDB)
- **Resolution**: 1920x1080
- **SSH Key**: `~/.ssh/ga_qemu_key` (user: ga)

## Data Sources

Task data uses realistic names and emails sourced from the **Kaggle Customer Support Ticket Dataset** (`chiapudding/kaggle-customer-service`):

| Task | Customer/User Data |
|------|-------------------|
| assign_conversation | Frank Sherman, floresbryan@example.net, "Payment issue" |
| update_customer_profile | Christina Dillon, bradleyolson@example.org |
| create_user | Rebecca Fleming, rebecca.fleming@helpdesk.local |
| create_conversation | clarkeashley@example.com, "Peripheral compatibility" |
| create_mailbox | Technical Support, techsupport@helpdesk.local |

## Audit Fixes Applied

The following issues from independent audits were addressed:

1. **assign_conversation data mismatch** (CRITICAL): Verifier had stale default "Billing discrepancy on invoice #4521" from a previous task version. Fixed to "Payment issue" to match task.json metadata and setup_task.sh. Re-tested end-to-end.
2. **create_customer renamed to update_customer_profile** (SEVERE): Task ID was misleading — it's actually updating an existing customer's name, not creating a new one. Directory renamed, task.json ID updated, hooks paths updated, constants.py fallback updated.
3. **Verifier hardcoded defaults mismatched metadata**: create_conversation had stale defaults ('Cannot access account after password reset'/'sarah.johnson@example.com'), create_user had stale defaults ('Emily'/'Rodriguez'/'emily.rodriguez@helpdesk.local'). All fixed to match current task metadata.
4. **assign_conversation wrong-assignee partial credit**: Verifier gave 15 points for wrong assignee, allowing incorrect answers to pass at threshold 60. Fixed: 0 points for wrong assignee, threshold raised to 75.
5. **create_customer free email points**: 30 points awarded for email match were free (email pre-populated by setup). Rebalanced: email check now 10 points (verification only), first/last name now 40 points each, pass threshold raised to 80.
6. **create_user missing role verification**: Added Criterion 6 checking user_role='user' (15 points), rebalanced other criteria.
7. **Nonce dead code removed**: `generate_result_nonce`/`get_result_nonce` calls removed from all 5 setup and 5 export scripts. Nonce was never validated by verifiers.
8. **Task descriptions over-specificity**: Removed step-by-step GUI navigation instructions from all 5 task descriptions.
9. **Garbled conversation body text** (MODERATE): assign_conversation setup had CSV-reading code that produced JavaScript code fragments in conversation body. Replaced with clean hardcoded fallback body.
10. **Verifier function naming** (MINOR): `verify_create_customer` renamed to `verify_update_customer_profile` to match renamed task.
11. **create_conversation threshold** (MINOR): Raised from 65 to 70 for consistency with other tasks.
12. **Screenshot numbering collisions** (MINOR): Removed 7 stale screenshots from first testing round (old 02-08 prefix) that conflicted with current screenshots.
13. **README screenshot description** (MINOR): Fixed `02_dashboard.png` description — correctly states "Manage Mailboxes" button, not "Support mailbox visible."
14. **Missing task-start screenshot** (MODERATE): Added `13_customer_edit_empty_start.png` showing empty name fields before agent interaction.

## Interactive Testing Method

Testing performed using xdotool for GUI interaction:
1. Screenshots captured via `DISPLAY=:1 import -window root` (ImageMagick)
2. Actions executed via `xdotool mousemove X Y click 1` and `xdotool type`
3. Each task tested end-to-end: setup -> GUI interaction -> export -> verify
