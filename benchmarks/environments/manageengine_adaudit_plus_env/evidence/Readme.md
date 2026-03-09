# ManageEngine ADAudit Plus Environment - Evidence Documentation

## Environment Verification Checklist

### Installation (pre_start hook)
- [x] **Installation script completes without errors** - Total time: ~1250s (~21 min)
  - Download: 247MB installer from ManageEngine CDN (BITS/WebClient fallback)
  - GUI wizard automation via PyAutoGUI (8 InstallShield steps)
  - Service installation and startup (HTTP 200 on port 8081)
  - Password change from default admin/admin to admin/Admin@2024 via browser automation
  - Password verification: HTTP 200 on j_security_check with new credentials
  - See: `pre_start_log.txt`

### Setup (post_start hook)
- [x] **Setup script completes without errors**
  - Audit data generated: 5 users, 3 groups, failed logon events, file audit folder
  - Audit policies configured via auditpol
  - **Workgroup server (localhost) added** via PyAutoGUI browser automation - required for navigation to work (without it, all pages redirect to Domain Settings)
  - Desktop shortcut created
  - See: `post_start_log.txt`

### Application State
- [x] **Application visible in screenshot** - ADAudit Plus login page in Microsoft Edge
  - See: `ts_01_task_start_state.png`
- [x] **Application in correct initial state with real data loaded**
  - Login page accessible at http://localhost:8081/
  - Login works with admin / Admin@2024
  - 5 local Windows users created (jsmith, mjohnson, rwilliams, abrown, dlee)
  - 3 security groups created (IT_Support, Security_Team, Server_Admins)
  - Failed logon events generated (Event ID 4625)
  - C:\AuditTestFolder with NTFS auditing enabled
  - Workgroup server (localhost) configured and visible in Server Audit > Workgroup Servers

### Task Setup
- [x] **Task setup runs without errors**
  - Edge launched to ADAudit Plus login page (clean profile via --user-data-dir)
  - All 5 tasks start from login page
- [x] **Task start state is correct** - verified via visual_grounding MCP tool
  - Login page shows "admin" username field
  - Password field ready for input
  - ADAudit Plus Authentication selected
  - See: `ts_01_task_start_state.png`

### Evidence Screenshots
| File | Description | URL Shown |
|------|-------------|-----------|
| `ts_01_task_start_state.png` | Task start state - ADAudit Plus login page (1280x720) | `localhost:8081` |
| `ts_02_dashboard.png` | Dashboard after login - Graphical View with alerts panel | `localhost:8081/#/home` |
| `ts_03_admin_notifications.png` | Admin > Notifications page (configure_notification_settings task target) | `localhost:8081/#/admin/alertme` |
| `ts_04_admin_technicians.png` | Admin > Technicians page with "Add technicians" button (create_technician task target) | `localhost:8081/#/admin/technician` |
| `ts_05_admin_logon_settings.png` | Admin > Logon Settings page with SSO/2FA tabs (configure_logon_settings task target) | `localhost:8081/#/admin/logonsettings` |
| `ts_06_admin_schedule_reports.png` | Admin > Schedule Reports page with existing schedules (schedule_report task target) | `localhost:8081/#/admin/schedulereports` |
| `ts_07_workgroup_server_configured.png` | Server Audit > Workgroup Servers showing "localhost" configured (confirms workgroup server was successfully added) | `localhost:8081/#/serveraudit/audit/listworkgroup/4194304` |

### Log Files
| File | Description |
|------|-------------|
| `pre_start_log.txt` | Full pre_start hook log: installer download, wizard automation, service startup, password change + verification |
| `post_start_log.txt` | Full post_start hook log: audit data generation, workgroup server addition, desktop shortcut |

### Tasks (5 total)
| Task | Admin Page | Description |
|------|-----------|-------------|
| `configure_email_settings` | Admin > Notifications > [Configure Mail Server] | Configure SMTP settings (smtp.company.local:587/TLS) |
| `create_technician` | Admin > Technicians > + Add technicians | Create operator account (secanalyst) |
| `configure_notification_settings` | Admin > Notifications | Enable Event Collection Failure alerts |
| `configure_logon_settings` | Admin > Logon Settings | Set max invalid attempts, lockout duration |
| `schedule_report` | Admin > Schedule Reports > + Schedule New Reports | Create Weekly Security Summary report |

### Ports
- SSH: Dynamic (assigned by runner)
- VNC: Dynamic (5900 + display number)
- HTTP: 8081 (ADAudit Plus web UI)
- PostgreSQL: 33307 (bundled database)
- PyAutoGUI: 5555 (guest side)
