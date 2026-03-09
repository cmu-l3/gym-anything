# Eramba GRC Environment — Evidence Documentation

## Environment Overview

- **Application**: Eramba Community v3.28.2 (GRC platform)
- **Stack**: Docker Compose — eramba-app (CakePHP/Apache, :8080/:8443), eramba-db (MySQL 8.4), eramba-cache (Redis 7), eramba-cron
- **Admin credentials**: login=`admin`, password=`Admin2024!`
- **URL**: `http://localhost:8080`

## Task Inventory

| # | Screenshot | Task Directory | Description |
|---|-----------|---------------|-------------|
| 1 | `03_task_add_risk.png` | `add_risk/` | Add a new risk entry in Risk Management |
| 2 | `04_task_add_third_party.png` | `add_third_party/` | Register a new third-party vendor |
| 3 | `05_task_create_security_policy.png` | `create_security_policy/` | Create a new security policy document |
| 4 | `06_task_add_compliance_exception.png` | `add_compliance_exception/` | Add a policy exception |
| 5 | `07_task_create_internal_control.png` | `create_internal_control/` | Create an internal control (MFA Enforcement) |
| 6 | `08_task_add_user.png` | `add_user/` | Add a new user account (Alexandra Chen) |
| 7 | `09_task_create_security_incident.png` | `create_security_incident/` | Log a security incident |
| 8 | `10_task_update_risk_treatment.png` | `update_risk_treatment/` | Update treatment strategy for a risk |
| 9 | `11_task_create_project.png` | `create_project/` | Create a new GRC project |
| 10 | `12_task_add_asset.png` | `create_security_questionnaire/` | Add an IT asset (Corporate Email System) |

## Screenshot Legend

- `00_dashboard.png` — Eramba dashboard after background job renders (shows task lists and chart placeholders)
- `01_login_page.png` — Login page on initial browser open
- `02_dashboard.png` — Dashboard immediately after login (may show loading spinner on first visit)
- `03_task_add_risk.png` — Risk Management page showing 3 seeded risks (Phishing, Ransomware, Insider Threat)
- `04_task_add_third_party.png` — Third Parties page showing AWS and Salesforce
- `05_task_create_security_policy.png` — Security Policies page showing 2 seeded policies
- `06_task_add_compliance_exception.png` — Policy Exceptions page (empty — correct start state for create task)
- `07_task_create_internal_control.png` — Internal Controls page showing 2 seeded controls (EDR, Vulnerability Management)
- `08_task_add_user.png` — Users page showing admin user (agent must add Alexandra Chen)
- `09_task_create_security_incident.png` — Security Incidents page (empty — correct start state)
- `10_task_update_risk_treatment.png` — Risk Management page showing risks for treatment update
- `11_task_create_project.png` — Projects page (empty — correct start state for create task)
- `12_task_add_asset.png` — Asset Management > Assets page (empty — correct start state for add_asset task)

## Architecture Notes

### Two-Layer Filter System (Critical)
Eramba Community v3.28.2 has two separate filter tables:
- **`advanced_filters`** (CakePHP layer) — default filter definitions seeded via `bin/cake advanced_filters seed`
- **`filters`** (Laravel/Vue SPA layer) — what the Vue SPA reads to render tables

The Vue SPA reads only the `filters` table. Without migrated entries, all GRC pages render blank.

**Fix applied in `setup_eramba.sh`**:
1. `bin/cake advanced_filters seed --table <ModelName>` for each model
2. PHP script using `FilterMigrationService::migrate()` to populate `filters` table
3. `bin/cake access_control sync` to configure permissions

### Dashboard Loading
The Eramba dashboard renders asynchronously via a queue worker. On first visit, it shows:
> "We are loading the dashboard in the background, you can use the system it will later on show up."

The queue worker (`bin/cake queue run`) must process the `Reports.Report` job. A null check was added to `MultipleRiskMatrixChart.php` to handle empty `risk_classification_types` (which is expected on fresh installs).

### Welcome Screen Bypass
Four `user_account_requirements` DB rows are inserted at setup time to bypass the first-run wizard:
- `welcome`, `App.ResetPassword`, `CommunityPack.Verification`, `AdvancedFilters.AdvancedFilters`

### Enterprise-only Features
The following are Enterprise-only and NOT available in Community:
- Awareness Programs
- Online Assessments (Vendor Assessments / Security Questionnaires)
- Account Reviews

Task `create_security_questionnaire/` was repurposed to `add_asset` (adds 'Corporate Email System' IT asset).

## Verification Checklist

- [x] All 10 tasks have corresponding task.json and verifier.py
- [x] All 10 tasks have task start-state screenshots in evidence/
- [x] All verifiers use real DB queries (no stub pass-through)
- [x] SQL operator precedence fixed in create_internal_control verifier
- [x] add_user setup_task.sh uses correct URL (`/settings/access-management/users`)
- [x] GRC pages render with data (filter migration applied in setup_eramba.sh)
- [x] Dashboard renders after queue worker processes the report job
- [x] Background data seeded: 3 risks, 2 policies, 2 third parties, 2 internal controls
