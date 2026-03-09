# Evidence Documentation — OpenProject Environment (`openproject_env`)

This folder contains real-run evidence from interactive testing of `openproject_env`.
All screenshots, logs, and metadata are captured from actual QEMU VM executions (2026-02-22).

---

## Environment Summary

| Field | Value |
|-------|-------|
| **Env ID** | `openproject_env@0.1` |
| **Base image** | `ubuntu-gnome-systemd_highres` |
| **Resources** | 4 vCPU, 8 GB RAM |
| **Application** | OpenProject 15.x (all-in-one Docker) |
| **URL** | `http://localhost:8080` |
| **Admin credentials** | `admin` / `Admin1234!` |
| **User credentials** | alice.johnson, bob.smith, carol.williams / `User1234!@` |
| **Backend** | Rails 7, PostgreSQL (bundled in Docker image) |

---

## Verification Checklist

- [x] Installation script (`install_openproject.sh`) completes without errors
- [x] Setup script (`setup_openproject.sh`) completes without errors
- [x] OpenProject accessible at `http://localhost:8080/login` after setup
- [x] 3 projects seeded: ecommerce-platform, mobile-banking-app, devops-automation
- [x] 3 user accounts created: alice.johnson, bob.smith, carol.williams
- [x] 15 work packages seeded with realistic subjects, statuses, and assignments
- [x] Admin API token created at `/home/ga/openproject_api_token.txt`
- [x] All 10 task setup scripts run without errors
- [x] All 10 task start states verified via VNC screenshot + `visual_grounding` MCP tool
- [x] End-to-end demo: `create_project` completed (login -> form fill -> "Customer Support Tracker" created)

**Bugs found and fixed during testing:**
- `add_project_member`: `/settings/members` returns 404 in OpenProject 15 -- fixed to `/members`
- `update_work_package_status`: "Resolved" does not exist in OpenProject 15 defaults -- fixed to "Closed"

---

## Seeded Data

### Projects

| ID | Name | Identifier |
|----|------|-----------|
| 3 | E-Commerce Platform | `ecommerce-platform` |
| 4 | Mobile Banking App | `mobile-banking-app` |
| 5 | DevOps Automation | `devops-automation` |

### Users

| Login | Name | Password |
|-------|------|----------|
| alice.johnson | Alice Johnson | `User1234!@` |
| bob.smith | Bob Smith | `User1234!@` |
| carol.williams | Carol Williams | `User1234!@` |

### Work Packages (from `create_project/env_setup_post_start.log`)

| ID | Subject | Project | Status |
|----|---------|---------|--------|
| 37 | Implement product search with Elasticsearch | ecommerce-platform | In progress |
| 38 | Fix broken checkout on mobile Safari | ecommerce-platform | New |
| 39-41 | (3 more ecommerce-platform WPs) | ecommerce-platform | various |
| 42 | Implement biometric login (Face ID / Fingerprint) | mobile-banking-app | In progress |
| 43-46 | (4 more mobile-banking-app WPs) | mobile-banking-app | various |
| 47 | Set up GitHub Actions CI pipeline | devops-automation | Closed |
| 48 | Kubernetes cluster autoscaling misconfigured | devops-automation | In progress |
| 49 | Implement blue-green deployment strategy | devops-automation | New |
| 50-51 | (2 more devops-automation WPs) | devops-automation | various |

Full list with assignees: see `create_project/env_setup_post_start.log` (JSON seed output).

---

## Folder Structure

```
evidence/
|-- README.md
|-- test_results.json          (10 tasks, all success=true, correct back_url per task)
|-- create_project_demo/       (end-to-end demo, 4 screenshots)
|-- create_project/            (start.png, logs, metadata)
|-- create_work_package/
|-- add_project_member/
|-- create_version/
|-- update_work_package_status/
|-- log_time/
|-- create_wiki_page/
|-- add_work_package_comment/
|-- assign_work_package/
`-- set_work_package_dates/
```

Each task directory contains:
- `start.png` -- VNC screenshot at task start (login page with correct back_url)
- `env_setup_pre_start.log` -- Output of `install_openproject.sh`
- `env_setup_post_start.log` -- Output of `setup_openproject.sh`
- `task_pre_task.log` -- Output of `setup_task.sh`
- `wmctrl_windows.txt`, `firefox_ps.txt`, `xdpyinfo.txt`, `docker_ps.txt`
- `capture_task_start.txt` -- Active window title
- `run_metadata.txt` -- JSON with ssh_port, vnc_port, timestamp

---

## Task Start States (All 10 Verified)

All tasks: Firefox shows `Sign in | OpenProject` with `back_url` pointing to the correct target.
After login the agent is redirected to the task page. This is the intended start state.

| Task | back_url target |
|------|----------------|
| `create_project` | `/projects/new` |
| `create_work_package` | `/projects/ecommerce-platform/work_packages` |
| `add_project_member` | `/projects/devops-automation/members` |
| `create_version` | `/projects/mobile-banking-app/settings/versions` |
| `update_work_package_status` | `/projects/devops-automation/work_packages/48/activity` |
| `log_time` | `/projects/mobile-banking-app/work_packages/42/activity` |
| `create_wiki_page` | `/projects/ecommerce-platform/wiki` |
| `add_work_package_comment` | `/projects/ecommerce-platform/work_packages/38/activity` |
| `assign_work_package` | `/projects/mobile-banking-app/work_packages/44/activity` |
| `set_work_package_dates` | `/projects/devops-automation/work_packages/49/activity` |

---

## End-to-End Demo (`create_project_demo/`)

| File | Description |
|------|-------------|
| `step1_login_page.png` | Login page, back_url=/projects/new |
| `step2_new_project_form.png` | After login -> /projects/new (New project form) |
| `step3_project_name_filled.png` | Name field: "Customer Support Tracker" |
| `step4_project_created.png` | URL: /projects/customer-support-tracker/ -- project created |

---

## Post-Start Log Snippet

```
=== Setting up OpenProject via Docker ===
Docker daemon is ready
Starting OpenProject container...
=== Seeding OpenProject with realistic data ===
Projects: 3
Users: 3
=== OpenProject setup complete ===
OpenProject URL: http://localhost:8080/login
Admin credentials: admin / Admin1234!
Users: alice.johnson, bob.smith, carol.williams (password: User1234!@)
```

---

## Key OpenProject 15 Notes

- API auth: `apikey:<token>` only (no username:password basic auth)
- Member creation: `m.member_roles.build(role: role); m.save!` (roles before save)
- Status names: "In progress" (lowercase p), "Closed" -- "Resolved" does NOT exist
- URL routing: `/projects/:id/settings/members` = 404; use `/projects/:id/members`
- Verifiers: all stubs (VLM evaluation is external per framework design)

*Evidence generated: 2026-02-22. All files from real QEMU VM runs.*
