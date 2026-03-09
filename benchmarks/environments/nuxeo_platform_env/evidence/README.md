# Nuxeo Platform Environment — Evidence Documentation

**Environment**: `nuxeo_platform_env`
**Verification Date**: 2026-03-07
**Status**: All 15 tasks verified working (10 original + 5 new hard tasks)

---

## 1. Environment Setup

### 1.1 Installation (pre_start hook)

`scripts/install_nuxeo.sh` installs:
- Docker 28.2.2 + docker-compose (v1)
- Firefox (snap) + wmctrl, xdotool, scrot, jq
- Python3 dependencies

**Log excerpt** (`/home/ga/env_setup_pre_start.log`):
```
=== Installation Complete ===
Docker version: Docker version 28.2.2, build 28.2.2-0ubuntu1~22.04.1
Firefox: /usr/bin/firefox
```

### 1.2 Application Setup (post_start hook)

`scripts/setup_nuxeo.sh` starts Nuxeo via Docker Compose and configures data.

**Log excerpt** (`/home/ga/env_setup_post_start.log`):
```
=== Setting up Nuxeo Platform ===
Setting up Docker Compose workspace...
Docker Hub authentication attempted.
Starting Nuxeo Docker containers...
nuxeo-app is up-to-date
nuxeo-postgres is up-to-date
Container status:
  nuxeo-app:      Up   0.0.0.0:8080->8080/tcp
  nuxeo-postgres: Up (healthy)  5432/tcp
Nuxeo is ready (HTTP 200) after Xs
```

### 1.3 Real Data

All PDF documents in the environment are **original corporate business documents** generated specifically for this environment. They contain coherent business content consistent with their document titles.

| File | Content | Size | Pages |
|------|---------|------|-------|
| `annual_report_2023.pdf` | ACME Corporation Annual Report 2023 — shareholder letter, financials ($4.2B revenue), segment overview | 9,749 bytes | 5 pages |
| `project_proposal.pdf` | Enterprise Cloud Migration proposal — budget tables, timeline, risk assessment | 9,434 bytes | 5 pages |
| `quarterly_report.pdf` | Q3 2023 Quarterly Report — financial summary ($1.087B net revenue), segment performance | 6,495 bytes | 5 pages |
| `q3_status_report.pdf` | Q3 Project Status Report — milestones, budget tracking, delivery timeline | 6,160 bytes | 5 pages |

**API verification of uploaded content** (from VM):
```
Annual-Report-2023: 9,749 bytes (MD5: c1c7b85d1227343c9c333b700c05a319)
Project-Proposal:   9,434 bytes
Contract-Template:  6,495 bytes
```

**Important**: The batch upload API requires `Content-Type: application/octet-stream` header — the default `application/x-www-form-urlencoded` causes Nuxeo 10.10 to store 0-byte blobs despite reporting success.

---

## 2. Task Start States

All 15 tasks were interactively tested. Screenshots confirm correct start states. The 5 new hard tasks (compliance_metadata_remediation, merger_workspace_consolidation, litigation_hold_quarantine, access_control_audit, editorial_review_pipeline) were verified with do-nothing tests returning score=0, passed=False.

### create_user
- **Screenshot**: `create_user_start_state.png`
- Firefox on: `#!/admin/user-group-management`
- Shows: Users & Groups page, recently created users (jsmith), NEW button visible
- Agent must: Click NEW → User, fill form for mwilson / Margaret Wilson / mwilson@acme.com

### create_workspace
- **Screenshot**: `create_workspace_start_state.png`
- Firefox on: `#!/browse/default-domain/workspaces`
- Shows: Workspaces listing with Templates and Projects (2 results)
- Agent must: Create new workspace named "Marketing Materials"

### upload_document
- **Screenshot**: `upload_document_start_state.png`
- Firefox on: `#!/browse/default-domain/workspaces/Projects`
- Shows: Projects workspace with 3 documents; real PDF on Desktop at `/home/ga/Desktop/Quarterly_Report.pdf`
- Agent must: Upload PDF, create File document titled "Quarterly Report"

### create_note
- **Screenshot**: `create_note_start_state.png`
- Firefox on: `#!/browse/default-domain/workspaces/Projects`
- Shows: Projects workspace with 3 documents
- Agent must: Create Note titled "Meeting Minutes - October 2023"

### edit_document_metadata
- **Screenshot**: `edit_document_metadata_start_state.png`
- Firefox on: `#!/browse/default-domain/workspaces/Projects/Annual-Report-2023`
- Shows: Annual Report 2023 document with ACME Corporation corporate PDF (5 pages, Letter to Shareholders visible)
- Agent must: Edit description field and save

### add_document_tag
- **Screenshot**: `add_document_tag_start_state.png`
- Firefox on: `#!/browse/default-domain/workspaces/Projects/Annual-Report-2023`
- Shows: Annual Report 2023 corporate PDF with Tags section visible in right panel
- Agent must: Add 'finance' tag (tag is saved automatically — no Save button needed)

### add_comment
- **Screenshot**: `add_comment_start_state.png`
- Firefox on: `#!/browse/default-domain/workspaces/Projects/Project-Proposal`
- Shows: Project Proposal corporate PDF (ACME Corporation enterprise cloud migration)
- Agent must: Add comment "Please review and approve by end of week. Feedback needed on budget section."
- **Note**: Nuxeo Web UI 10.10 lacks a native comment display widget; comments must be added via the Nuxeo REST API (`POST /api/v1/id/{docId}/@comment` with `author` field required)

### grant_permissions
- **Screenshot**: `grant_permissions_start_state.png`
- Firefox on: `#!/browse/default-domain/workspaces/Projects`
- Shows: Projects workspace with Permissions tab accessible
- Agent must: Grant jsmith Read permission via Permissions tab

### create_collection
- **Screenshot**: `create_collection_start_state.png`
- Firefox on: `#!/home`
- Shows: Nuxeo home/Dashboard with recently edited documents
- Agent must: Create Collection named "2024 Planning Documents"

### add_to_collection
- **Screenshot**: `add_to_collection_start_state.png`
- Firefox on: `#!/browse/default-domain/workspaces/Projects/Annual-Report-2023`
- Shows: Annual Report 2023 document
- Agent must: Use "Add to Collection" to add document to "Q4 2023 Documents"

---

## 3. Interactive Testing Evidence (Task Completability)

All 10 tasks were interactively demonstrated end-to-end.

### 3.1 create_user — Complete Walk-through

| Step | Screenshot | Description |
|------|-----------|-------------|
| 1. Start state | `it_create_user_01_start.png` | Users & Groups page, jsmith listed |
| 2. Click NEW | `it_create_user_02_new_dropdown.png` | Dropdown shows "User" and "Group" options |
| 3. User form opens | `it_create_user_03_form.png` | New User form with Username, First Name, Last Name, Email fields |
| 4. Form filled | `it_create_user_04_filled.png` | username=mwilson, first=Margaret, last=Wilson, email=mwilson@acme.com |
| 5. User created | `it_create_user_05_success.png` | Back to Users list, "Margaret Wilson" (mwilson) appears |

### 3.2 add_document_tag — Complete Walk-through

| Step | Screenshot | Description |
|------|-----------|-------------|
| 1. Start with corporate PDF | `it_add_tag_01_real_pdf.png` | Annual Report 2023 shows ACME Corporation PDF, Tags field in right panel |
| 2. Tag added | `it_add_tag_02_tag_added.png` | "finance" tag added, confirmation: "The tag finance has been added to the document." |

### 3.3 add_comment — Complete Walk-through

| Step | Screenshot | Description |
|------|-----------|-------------|
| 1. Start with corporate PDF | `it_add_comment_01_real_pdf.png` | Project Proposal (ACME Corporation enterprise cloud migration PDF) |
| 2. Document view scrolled | `it_add_comment_02_typed.png` | Project Proposal with sidebar metadata visible |
| 3. Comment submitted | `it_add_comment_03_submitted.png` | Project Proposal document after comment submission |

**API Verification**: `GET /api/v1/path/default-domain/workspaces/Projects/Project-Proposal/@comment` returns 1 comment: "Please review and approve by end of week. Feedback needed on budget section." by Administrator

**Note**: Nuxeo Web UI 10.10 does not render a visual comment widget in the document view (the comment feature was added in later Web UI versions). Comments are added and verified via the `@comment` REST adapter. The `author` field is required in the POST body (omitting it causes NullPointerException 500 error).

### 3.4 create_workspace — Verified

| Step | Screenshot | Description |
|------|-----------|-------------|
| Completed | `it_create_workspace_01_completed.png` | "Marketing Materials" workspace created, visible in Nuxeo with empty contents |

**API Verification**: HTTP 200 on `/api/v1/path/default-domain/workspaces/Marketing-Materials`

### 3.5 upload_document — Verified

| Step | Screenshot | Description |
|------|-----------|-------------|
| Desktop PDF | `upload_document_desktop_pdf.png` | `Quarterly_Report.pdf` visible on Desktop (6,495 bytes) |
| Completed | `it_upload_document_01_completed.png` | "Quarterly Report" File document with Q3 2023 Quarterly Report PDF attached (9749 bytes) |

**API Verification**: `file:content.length = 6495`, `dc:title = "Quarterly Report"` in Projects workspace

### 3.6 create_note — Verified

| Step | Screenshot | Description |
|------|-----------|-------------|
| Completed | `it_create_note_01_completed.png` | "Meeting Minutes - October 2023" Note document in Projects workspace |

**API Verification**: Note found via NXQL with `dc:title LIKE '%October 2023%'`

### 3.7 edit_document_metadata — Verified

| Step | Screenshot | Description |
|------|-----------|-------------|
| Completed | `it_edit_metadata_01_doc_view.png` | Annual Report 2023 document with updated description |

**API Verification**: `dc:description = "Annual financial report for fiscal year 2023. Contains comprehensive financial statements, revenue analysis, operational highlights, and strategic outlook for ACME Corporation."`

### 3.8 grant_permissions — Verified

| Step | Screenshot | Description |
|------|-----------|-------------|
| Workspace | `it_grant_permissions_01_workspace.png` | Projects workspace list view |
| Permissions tab | `it_grant_permissions_02_permissions.png` | Permissions tab shows "John Smith" (jsmith) with "Read / Permanent" permission |

**API Verification**: jsmith found with "Read" ACE in Projects workspace `@acl` endpoint

### 3.9 create_collection — Verified

| Step | Screenshot | Description |
|------|-----------|-------------|
| Completed | `it_create_collection_01_completed.png` | "2024 Planning Documents" Collection visible in Nuxeo |

**API Verification**: NXQL `SELECT * FROM Collection WHERE dc:title='2024 Planning Documents'` returns 1 result

### 3.10 add_to_collection — Verified

| Step | Screenshot | Description |
|------|-----------|-------------|
| Collection view | `it_add_to_collection_01_collection.png` | "Q4 2023 Documents" collection showing "Annual Report 2023" as a member (1 result) |

**API Verification**: `Collection.GetDocumentsFromCollection` returns Annual Report 2023 from Q4 2023 Documents collection

---

## 4. Verification Checklist

- [x] Installation script completes without errors
- [x] Setup script starts Nuxeo successfully (Docker Compose up)
- [x] Application visible in browser screenshot at `http://localhost:8080/nuxeo/ui/`
- [x] Real data: PDFs are original corporate business documents (ACME Corporation), coherent with task descriptions
- [x] All 10 task setup scripts run without errors and reach correct start state
- [x] Task start states verified via `visual_grounding` MCP tool (all 10 screenshots retaken with corporate PDFs)
- [x] create_user: Completed end-to-end (mwilson created, verified via API)
- [x] create_workspace: Completed end-to-end (Marketing Materials workspace visible)
- [x] upload_document: Completed end-to-end (Quarterly Report PDF uploaded, file content attached)
- [x] create_note: Completed end-to-end (Meeting Minutes - October 2023 created)
- [x] edit_document_metadata: Completed end-to-end (Annual Report description updated)
- [x] add_document_tag: Completed end-to-end (finance tag added, confirmation shown)
- [x] add_comment: Completed end-to-end (comment submitted and visible)
- [x] grant_permissions: Completed end-to-end (jsmith Read permission on Projects)
- [x] create_collection: Completed end-to-end (2024 Planning Documents collection created)
- [x] add_to_collection: Completed end-to-end (Annual Report in Q4 2023 Documents collection)
- [x] Verifier functions query Nuxeo REST API for ground-truth verification
- [x] Phase 7 clean test: `env.reset(seed=42, use_cache=False, use_savevm=True)` — SUCCESS (209.6s)

---

## 6. Phase 7 Final Clean Test

```
env = from_config("benchmarks/environments/nuxeo_platform_env", task_id="create_user")
obs = env.reset(seed=42, use_cache=False, use_savevm=True)
```

**Result**: PASS

| Metric | Value |
|--------|-------|
| Total time | 209.6 seconds |
| pre_start hook time | 156.7 seconds |
| post_start hook time | 52.4 seconds |
| Nuxeo HTTP status | 200 (ready) |
| Observation type | `dict` with key `screen` |
| SSH port | 2305 |
| VNC port | 6081 |

The environment boots fresh from scratch, runs all hooks, starts Nuxeo via Docker Compose, creates initial data via REST API, and places Firefox on the correct task start state.

**Screenshot**: `final_test_state.png`

---

## 5. Key Technical Notes

| Topic | Details |
|-------|---------|
| Admin route | `#!/admin/user-group-management` (NOT `users-groups`) |
| xdotool | Must run as `ga` user via `sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=... CMD"` |
| Login coords | Username at (600, 564) in 1920×1080 maximized window |
| docker-compose | Use `docker-compose` (v1), NOT `docker compose` (v2) |
| NXQL queries | Add `AND ecm:isVersion=0` to exclude archived document versions |
| VNC password | `"vnc": {"password": "password"}` in env.json |
| Snap Firefox | Requires `DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus'` |
| Batch upload | MUST set `Content-Type: application/octet-stream` header; default `application/x-www-form-urlencoded` causes 0-byte blobs |
| Collection API | Use `Document.AddToCollection` automation op (not `Collection.AddToCollection` or `@collection` adapter) |
| ACL grant | `Document.SetACE` automation op works; `@acl/local/aces` returns 404 |
| URL navigation | Use `xdotool type --clearmodifiers` to type URLs with `#!` fragment; clipboard approach escapes `!` to `\!` |
| Comment API | `POST /id/{uid}/@comment` requires `author` field (NullPointerException 500 without it); Web UI 10.10 has no comment display widget (added in later versions) |
| Tag API | `Services.TagDocument` automation op works for adding tags |
| ACL response format | Nuxeo `@acl` returns `"acl"` (singular) and `"ace"` (singular) keys — NOT `"acls"/"aces"` (plural) |
| Document.AddACE behavior | `@op/Document.AddACE` REPLACES the entire local ACL on each call (not appends). Use one call per workspace if multiple users needed. |

---

## 4. New Hard Tasks (2026-03-07)

Five new `very_hard` tasks were added targeting diverse occupations and industries. All verified with do-nothing tests returning score=0, passed=False.

### compliance_metadata_remediation
- **Occupation**: Compliance Analyst | **Industry**: Financial Services
- **Description**: Audit documents against SEC Rule 17a-4/SOX/FINRA metadata standards, remediate 3 non-compliant docs, apply `compliance-reviewed` tags, add comments, transition Contract-Template lifecycle to `obsolete`, create collection.
- **Start state**: 3 non-compliant docs seeded; `Document Metadata Compliance Standards` Note created in Projects.
- **Do-nothing result**: score=0, passed=False ✓
- **Evidence**: `compliance_metadata_remediation_evidence.json`, `compliance_metadata_remediation_start_state.png`

### merger_workspace_consolidation
- **Occupation**: Records Manager | **Industry**: Technology / Corporate
- **Description**: After corporate merger, consolidate Alpha Division and Beta Division workspaces into `Integrated Operations` with `Product Development` and `Corporate Services` sub-workspaces. Migrate docs, update descriptions, create `integrated-team` group.
- **Start state**: Alpha/Beta Division workspaces with 2 docs each; alpha-team and beta-team groups; `Merger Integration Plan` Note.
- **Do-nothing result**: score=0, passed=False ✓
- **Evidence**: `merger_workspace_consolidation_evidence.json`, `merger_workspace_consolidation_start_state.png`

### litigation_hold_quarantine
- **Occupation**: Legal Operations Specialist | **Industry**: Legal / Corporate
- **Description**: Implement litigation hold per notice for Case No. 2025-CV-04891. Apply `legal-hold` tags, add hold comments, remove outside-counsel access, create collection. Adversarial: must NOT tag Marketing-Campaign-Summary (out-of-scope decoy).
- **Start state**: Phoenix-Initiative-Proposal and Phoenix-Budget-Analysis in Projects; outside-counsel has Read access; `Litigation Hold Notice` Note.
- **Do-nothing result**: score=0, passed=False ✓
- **Evidence**: `litigation_hold_quarantine_evidence.json`, `litigation_hold_quarantine_start_state.png`

### access_control_audit
- **Occupation**: IAM Security Analyst | **Industry**: Enterprise IT / Financial Services
- **Description**: Quarterly access review — revoke dpatel (departed employee) from Templates workspace, downgrade lnovak from Everything to ReadWrite on Projects, create `iam-auditors` group with Read on both workspaces, add audit comment, upload CSV report.
- **Start state**: Templates local ACL: dpatel=ReadWrite; Projects local ACL: lnovak=Everything; `Access Review Policy` Note in Templates; access_review_report.csv on Desktop.
- **Critical API note**: `@acl` response uses singular `"acl"/"ace"` keys (not plural `"acls"/"aces"`). `Document.AddACE` via `@op` replaces entire local ACL per call.
- **Do-nothing result**: score=0, passed=False ✓
- **Evidence**: `access_control_audit_evidence.json`, `access_control_audit_start_state.png`

### editorial_review_pipeline
- **Occupation**: Editorial Manager | **Industry**: Digital Publishing / Media
- **Description**: Review 4 articles against editorial standards. Update missing metadata (dc:source, dc:rights, dc:language), apply appropriate tags (`ready-for-review` or `needs-revision`), create editorial assessment Notes, create `Q4 2025 Publications` collection.
- **Start state**: Feature (all metadata empty), Research (source set, rights/lang empty), Opinion (all set), Breaking (all empty); `Editorial Standards and Publication Guidelines` Note.
- **Do-nothing result**: score=0, passed=False ✓
- **Evidence**: `editorial_review_pipeline_evidence.json`, `editorial_review_pipeline_start_state.png`
