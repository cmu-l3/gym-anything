# Safe Exam Browser Server Environment - Evidence Documentation

## Environment Overview
- **Environment ID**: safe_exam_browser_env@0.1
- **Application**: SEB Server v2.2-stable (Docker-based exam administration platform)
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 8GB RAM, network enabled, privileged (Docker-in-QEMU)

## Architecture
- MariaDB 10.5 + SEB Server (anhefti/seb-server:v2.2-stable) running via Docker Compose inside QEMU VM
- SEB Server accessible at http://localhost:8080 with demo profile (ETH Zürich institution)
- Firefox browser for web UI interaction
- Pre-configured Testing/Mock LMS with sample quizzes (8 demo quizzes available for import)

## Verification Checklist

### [x] Installation script completes without errors
See `env_setup_pre_start.log` - ends with:
```
=== SEB Server installation complete ===
```
Docker images pulled: mariadb:10.5 and anhefti/seb-server:v2.2-stable

### [x] Setup script completes without errors
See `env_setup_post_start.log` - ends with:
```
=== SEB Server setup complete ===
SEB Server accessible at: http://localhost:8080
Default login: super-admin / admin
```
Key milestones: MariaDB ready in 3s, SEB Server GUI HTTP 200 in 10s, Firefox profile configured.

### [x] Application is visible in screenshot
See `vg_task_start_state.png` - SEB Server web UI fully loaded in Firefox, showing:
- SEB Server v2.2-stable logo and header
- Logged in as "super-admin" with Sign out button
- Full left sidebar navigation (Institution, User Account, Configurations, Exam Administration, Monitoring)
- Institutions page showing ETH Zürich (Active)

### [x] Application is in correct initial state with real data loaded
See `vg_task_start_state.png` - Demo data from SEB Server's official demo profile:
- 1 institution: ETH Zürich (real institution, official SEB Server demo data)
- 2 users: sebserver-admin, super-admin
- 1 exam configuration: "test" (SEB Configuration Demo)
- 1 connection configuration: "test" (Active)
- 2 exams: Demo Quiz 1, Demo Quiz 6 (from Mock LMS)
- 8 additional quizzes available for import via Assessment Tool Lookup
- 0 exam templates (clean slate for template creation task)

### [x] Task setup runs without errors
See `task_pre_task.log`:
```
=== Setting up create_exam_configuration task ===
Task start time: 1772065392
SEB Server is accessible (HTTP 200)
Baseline recorded for create_exam_configuration: {
  "exam_config_count": 1, "connection_config_count": 1, "user_count": 2,
  "exam_count": 2, "exam_template_count": 0, "indicator_count": 1
}
Firefox window detected
Logging into SEB Server as super-admin...
=== Task setup complete ===
```

### [x] Task start state is correct (verified via visual_grounding)
Interactive visual_grounding verification confirmed:
- `vg_task_start_state.png`: SEB Server logged in, full navigation visible
- `vg_exam_config_page.png`: Exam Configurations page with existing "test" config
- `vg_add_exam_config_form.png`: Add form with Name, Description, Template, Status fields + Save button
- `vg_user_accounts_page.png`: User Accounts page with 2 existing users
- `vg_add_user_form.png`: Add user form with all required fields (name, username, email, role checkboxes, password)
- `vg_connection_config_page.png`: Connection Configuration page with existing "test" config
- `vg_exam_template_page.png`: Exam Templates page (empty, ready for creation)
- `vg_exam_admin_page.png`: Exam page showing 2 running demo exams
- `vg_assessment_tool_lookup.png`: 8 demo quizzes available for import from Mock LMS

### [x] Sufficient evidence that tasks are completable end-to-end
For each task, the following UI elements were verified via visual_grounding:

1. **create_exam_configuration**: Add form → Save → View SEB Settings → 11 tabs including Browser (reload settings, window policies) and Security (virtual machine detection, kiosk mode) confirmed via `vg_seb_settings_browser_tab.png` and `vg_seb_settings_security_tab.png`
2. **setup_institutional_users**: "Add User Account" form with First Name/Surname/Username/Email/Roles/Password/Timezone fields → Save button confirmed via `vg_add_user_form.png`
3. **configure_connection_config**: "Add Connection Configuration" form with Name/Purpose/Configuration Password/Encrypt/Ping Interval/Exams/With Fallback fields → checking "With Fallback" reveals Fallback Start URL + Connection Attempts + Interval + Timeout + Fallback Password confirmed via `vg_add_connection_config_form.png` and `vg_connection_config_fallback_fields.png`
4. **create_exam_template**: Add form → Save → Indicators section visible → Add Indicator form with 5 types (Battery Status, Error-Log Counter, Info-Log Counter, Last Ping Time, Warning-Log Counter) + threshold color configuration confirmed via `vg_add_exam_template_form.png`, `vg_exam_template_detail_with_indicators.png`, `vg_add_indicator_form.png`, `vg_indicator_types_dropdown.png`
5. **import_configure_exam**: Assessment Tool Lookup shows 8 importable quizzes → "Import as Exam" button confirmed via `vg_assessment_tool_lookup.png`

## Tasks (5 total, all difficulty: hard)

| Task | Description | Completability Verified |
|------|-------------|------------------------|
| create_exam_configuration | Create 'CS101 Final Exam Configuration' with browser/security settings | Yes - Add form, Save, View SEB Settings with Browser/Security tabs confirmed |
| setup_institutional_users | Create 3 users (prof.martinez, ta.chen, admin.thompson) | Yes - Add user form with all role/timezone options confirmed |
| configure_connection_config | Create 'Campus Lockdown Browser Config' connection configuration | Yes - Add form, With Fallback checkbox reveals Fallback Start URL field confirmed |
| create_exam_template | Create 'Midterm Proctored Exam Template' with Last Ping Time indicator | Yes - Add form, Indicators section, Add Indicator with 5 types + thresholds confirmed |
| import_configure_exam | Import exam from Testing LMS, add monitoring indicator | Yes - 8 quizzes available, Import button, indicator types confirmed |

## Evidence Files

### Visual Grounding Screenshots (interactive testing)
- `vg_task_start_state.png` - Initial state: SEB Server Institutions page, logged in
- `vg_exam_config_page.png` - Exam Configuration list with existing config
- `vg_add_exam_config_form.png` - Add Exam Configuration form (Name, Description, Template, Status)
- `vg_seb_settings_general.png` - SEB Settings page with all 11 tabs (General, User Interface, Browser, Down/Uploads, Exam, Applications, Network, Security, Registry, Hooked Keys, Proctoring)
- `vg_seb_settings_browser_tab.png` - Browser tab: reload settings, window policies, user agent, media playback options
- `vg_seb_settings_security_tab.png` - Security tab: SEB Service, kiosk mode, virtual machine detection, screen capture, macOS settings
- `vg_user_accounts_page.png` - User Accounts list (2 existing users)
- `vg_add_user_form.png` - Add User Account form (all fields including role checkboxes)
- `vg_connection_config_page.png` - Connection Configuration list
- `vg_add_connection_config_form.png` - Add Connection Configuration form (Name, Purpose, Configuration Password, Encrypt, Ping Interval, Exams, With Fallback)
- `vg_connection_config_fallback_fields.png` - With Fallback checked: reveals Fallback Start URL, Connection Attempts, Interval, Connection Timeout, Fallback Password fields
- `vg_exam_template_page.png` - Empty Exam Templates page
- `vg_add_exam_template_form.png` - Add Exam Template form (Name, Description, Institutional Default, Assessment Tool Integration, Exam Type, Config Template, Connection Config, Exam Supporter)
- `vg_exam_template_detail_with_indicators.png` - Saved template detail view showing Indicators section (Name/Type/Thresholds table) and Add Indicator button
- `vg_add_indicator_form.png` - Add Indicator form (Name, Type, Type Description, Default Color, Thresholds table)
- `vg_indicator_types_dropdown.png` - Indicator types dropdown: Battery Status, Error-Log Counter, Info-Log Counter, Last Ping Time, Warning-Log Counter
- `vg_exam_admin_page.png` - Exam admin with 2 running demo exams
- `vg_assessment_tool_lookup.png` - 8 demo quizzes available for import from LMS

### Setup Logs
- `env_setup_pre_start.log` - Full Docker installation + image pull log
- `env_setup_post_start.log` - SEB Server startup, data seeding, Firefox configuration
- `task_pre_task.log` - Task setup: baseline recording, login, screenshot

### Task-Specific Evidence (from do-nothing export tests)
- `*_start.png` - Screenshot after task setup (SEB Server logged in, ready for agent)
- `*_final.png` - Screenshot after export
- `*_result.json` - Raw export result from database query
- `*_evidence.json` - Verifier output

## Docker Container Status (during testing)
```
NAMES                STATUS                    PORTS
seb-server           Up 31 minutes             0.0.0.0:8080->8080/tcp
seb-server-mariadb   Up 31 minutes (healthy)   3306/tcp
```

## Boot Timing
- First boot (install+setup): ~280s total
- Cached boot (loadvm + post_start + pre_task): ~115s
- Task setup (pre_task only): ~35s
