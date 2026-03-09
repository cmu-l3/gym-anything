# draw_desktop_env - Evidence Documentation

## Environment Summary

| Field | Value |
|-------|-------|
| **Environment** | `draw_desktop_env` |
| **Application** | draw.io Desktop v26.0.9 (Electron-based diagramming tool) |
| **Base Image** | `ubuntu-gnome-systemd_highres` (1920x1080) |
| **OS** | Ubuntu 22.04.5 LTS (Jammy Jellyfish) |
| **Binary** | `/opt/drawio/drawio` (installed via dpkg, alt `/usr/bin/drawio`) |
| **Tasks** | `edit_uml_class_diagram`, `export_diagram_as_png`, `create_er_diagram` (original); `chinook_database_erd`, `aws_saas_architecture`, `purchase_to_pay_swimlane`, `oauth2_flow_sequence`, `microservices_dependency_audit` (added 2026-02-28) |
| **Evidence collected** | 2026-02-11 (original 3 tasks); 2026-02-28 (5 new very_hard tasks) |

---

## Verification Checklist

### 1. Installation script completes without errors

**Status**: PASS

The `install_drawio.sh` pre_start hook downloads draw.io v26.0.9 .deb from GitHub and installs it with dependencies.

**Log snippet** (from `pre_start_log.txt`, last 15 lines):

```
Selecting previously unselected package draw.io.
(Reading database ... 150875 files and directories currently installed.)
Preparing to unpack drawio-amd64-26.0.9.deb ...
Unpacking draw.io (26.0.9) ...
Setting up draw.io (26.0.9) ...
update-alternatives is /usr/bin/update-alternatives
update-alternatives: using /opt/drawio/drawio to provide /usr/bin/drawio (drawio) in auto mode
Processing triggers for mailcap (3.70+nmu1ubuntu1) ...
Processing triggers for gnome-menus (3.36.0-1ubuntu3) ...
Processing triggers for desktop-file-utils (0.26-1ubuntu3) ...
Processing triggers for shared-mime-info (2.1-2) ...
Processing triggers for hicolor-icon-theme (0.17-2) ...
Verifying draw.io installation...
draw.io installed successfully: /usr/bin/drawio
=== draw.io Desktop installation completed ===
```

### 2. Setup script completes without errors

**Status**: PASS

The `setup_drawio.sh` post_start hook creates directories, copies diagram assets, creates desktop shortcut, and pre-launches draw.io to initialize config.

**Full log** (from `post_start_log.txt`):

```
=== Setting up draw.io Desktop environment ===
Creating working directories...
  - Copied diagram assets to ~/Diagrams/
Using draw.io binary: drawio
  - Created desktop shortcut
Requirement already satisfied: plyvel in /usr/local/lib/python3.10/dist-packages (1.5.1)
Pre-launching draw.io to initialize config...
  - Config directory created after 1 seconds
```

### 3. Application is visible in screenshot

**Status**: PASS

All three task setup screenshots show draw.io launched, maximized, and in the correct initial state:
- `edit_uml_task_start.png` - UML diagram with Customer, Order, Product classes loaded
- `export_png_task_start.png` - Hospital ER diagram with Patient, Doctor, Appointment tables loaded
- `create_er_task_start.png` - Blank canvas with shape palette (Entity Relation, UML sections visible)

### 4. Application is in correct initial state (all 3 tasks)

**Status**: PASS

**`edit_uml_class_diagram`** (see `edit_uml_task_start.png`):
- draw.io is launched and maximized
- The "Open Existing Diagram" button is clicked in the startup dialog
- The UML diagram file is opened via file dialog (Ctrl+L -> path -> Enter)
- Window title: `ecommerce_uml_classes.drawio - draw.io`
- All three original classes (Customer, Order, Product) are visible with attributes and methods

**`export_diagram_as_png`** (see `export_png_task_start.png`):
- draw.io is launched and maximized
- The "Open Existing Diagram" button is clicked in the startup dialog
- The hospital ER diagram is opened via file dialog
- Window title: `hospital_er_base.drawio - draw.io`
- Patient, Doctor, and Appointment tables visible with all attributes and connections

**`create_er_diagram`** (see `create_er_task_start.png`):
- draw.io is launched and maximized
- The startup dialog is dismissed with Escape (creates blank canvas)
- Window title: `Untitled Diagram.drawio - draw.io`
- Shape palette visible: General, Misc, Advanced, Basic, Arrows, Flowchart, Entity Relation, UML

### 5. Task setup runs without errors

**Status**: PASS

The setup_task.sh for file-opening tasks uses the reliable "Click Open Existing Diagram" pattern:
1. Launch draw.io (without file argument - startup dialog always appears)
2. Wait for window (up to 30 seconds)
3. Maximize window
4. Click "Open Existing Diagram" button at coordinates (993, 489)
5. Ctrl+L -> type path -> Enter to open file in file dialog
6. Verify file loaded (check window title for filename)
7. Retry with fallback (Escape -> Ctrl+O -> Ctrl+L) if first attempt fails

**Actual setup output for `edit_uml_class_diagram`**:
```
=== Setting up edit_uml_class_diagram task ===
Recording initial state...
Initial diagram state:
  - Shapes: 12
  - Edges: 2
  - Size: 5787 bytes
Launching draw.io...
Waiting for draw.io window...
draw.io window detected after 4 seconds
Clicking 'Open Existing Diagram' button in startup dialog...
Diagram loaded successfully!
draw.io is running
Window: 0x00800004  0 ga-base ecommerce_uml_classes.drawio - draw.io
=== edit_uml_class_diagram task setup completed ===
```

**Actual setup output for `export_diagram_as_png`**:
```
=== Setting up export_diagram_as_png task ===
Launching draw.io...
Waiting for draw.io window...
draw.io window detected after 4 seconds
Clicking 'Open Existing Diagram' button in startup dialog...
Diagram loaded successfully!
draw.io is running
Window: 0x00800004  0 ga-base hospital_er_base.drawio - draw.io
=== export_diagram_as_png task setup completed ===
```

**Actual setup output for `create_er_diagram`**:
```
=== Setting up create_er_diagram task ===
Launching draw.io...
Waiting for draw.io window...
draw.io window detected after 4 seconds
Dismissing startup dialog (creating blank diagram)...
draw.io is running
Window: 0x00800004  0 ga-base Untitled Diagram.drawio - draw.io
=== create_er_diagram task setup completed ===
```

### 6. Export script produces valid JSON

**Status**: PASS

The `export_result.sh` for `edit_uml_class_diagram` produces valid JSON with all expected fields. Baseline (no modifications made):

```json
{
    "found": true,
    "file_exists": true,
    "file_path": "/home/ga/Diagrams/ecommerce_uml_classes.drawio",
    "file_size": 5787,
    "file_modified": false,
    "num_shapes": 12,
    "num_edges": 2,
    "new_connections": 0,
    "has_payment_class": false,
    "has_payment_id": false,
    "has_amount": false,
    "has_payment_date": false,
    "has_method_attr": false,
    "has_process_payment": false,
    "has_refund": false,
    "timestamp": "2026-02-11T19:54:47+00:00"
}
```

The `export_result.sh` for `create_er_diagram` correctly detects no diagram file at baseline:

```json
{
    "found": false,
    "file_exists": false,
    "file_path": "/home/ga/Desktop/library_er_diagram.drawio",
    "file_size": 0,
    "num_shapes": 0,
    "num_connections": 0,
    "raw_edge_count": 0,
    "has_book": false,
    "has_author": false,
    "has_member": false,
    "has_loan": false,
    "has_book_id": false,
    "has_title": false,
    "has_isbn": false,
    "has_email": false,
    "has_loan_date": false,
    "total_attributes": 0,
    "initial_file_count": 0,
    "current_file_count": 0,
    "timestamp": "2026-02-11T19:55:53+00:00"
}
```

### 7. Verifier can read and process the result

**Status**: PASS

All three verifiers correctly parse JSON from `/tmp/task_result.json` via `copy_from_env()`.

### 8. Verification returns expected result

**Status**: PASS (baseline produces correct 0-score results for unmodified state)

The verifiers correctly score 0 when no agent modifications have been made, and the scoring criteria align with the task requirements. Content verification and structural validation are in place.

---

## System Information

From `system_info.txt` (collected 2026-02-11):

```
OS: Ubuntu 22.04.5 LTS
User: ga
draw.io binary: /usr/bin/drawio
draw.io version: 26.0.9

/home/ga/Diagrams/:
  ecommerce_uml_classes.drawio (5,787 bytes) - UML class diagram (Customer, Order, Product)
  hospital_er_base.drawio (19,168 bytes) - Hospital ER diagram (Patient, Doctor, Appointment)
  exports/ - empty directory for PNG exports

/home/ga/Desktop/:
  drawio.desktop - Desktop shortcut for draw.io
```

---

## Screenshots

| File | Task | Description |
|------|------|-------------|
| `edit_uml_task_start.png` | edit_uml_class_diagram | UML diagram loaded with 3 classes (Customer, Order, Product) |
| `export_png_task_start.png` | export_diagram_as_png | Hospital ER diagram loaded (Patient, Doctor, Appointment) |
| `create_er_task_start.png` | create_er_diagram | Blank canvas with Entity Relation and UML shape palettes visible |

---

## Key Technical Findings

### Startup Dialog Problem
draw.io Desktop v26.0.9 ALWAYS shows a "Create New / Open Existing" startup dialog on launch, regardless of:
- File argument passed on command line
- `showStartScreen` setting in LocalStorage/LevelDB
- `DRAWIO_DISABLE_UPDATE=true` environment variable

**Solution (current)**: Click "Open Existing Diagram" button directly at (993, 489) in 1920x1080 -> Ctrl+L (location bar) -> type path -> Enter. Falls back to Escape -> Ctrl+O -> Ctrl+L chain if first attempt fails.

**Previous solution (unreliable)**: Escape -> Ctrl+O -> Ctrl+L -> type path -> Enter. This sometimes failed, producing a blank canvas instead of the expected diagram.

### Structural Validation
- `create_er_diagram`: Entity names (Book, Author, Member, Loan) must appear in vertex shapes (`vertex="1"`), not just in edge labels. Uses XML parsing via `xml.etree.ElementTree`.
- `edit_uml_class_diagram`: Uses word boundary regex (`\bPayment\b`) to prevent false positives (e.g., "Payment" vs "paymentId").
- `export_diagram_as_png`: Verifies PNG content has >20 unique colors (blank image has ~1) and checks for embedded draw.io XML in PNG tEXt chunks.

### GPU Errors in QEMU
dbus/GPU errors are harmless in QEMU VM - draw.io renders correctly via software rendering.

---

## Log Files

| File | Source | Description |
|------|--------|-------------|
| `pre_start_log.txt` | `/home/ga/env_setup_pre_start.log` | Full apt-get + dpkg installation output |
| `post_start_log.txt` | `/home/ga/env_setup_post_start.log` | Post-start setup (dirs, assets, config init) |
| `system_info.txt` | Runtime collection | OS, binary paths, file listings |

---

## New Tasks: 5 Very Hard Tasks (Added 2026-02-28)

### Summary

| Task | Difficulty | Occupation | Starting State | Evidence |
|------|-----------|-----------|----------------|---------|
| `chinook_database_erd` | very_hard | Computer Systems Analyst | Blank canvas + chinook_schema.sql on Desktop | [json](chinook_database_erd_evidence.json) [png](chinook_database_erd_screenshot.png) |
| `aws_saas_architecture` | very_hard | Solutions Architect | Blank canvas + saas_arch_requirements.txt on Desktop | [json](aws_saas_architecture_evidence.json) [png](aws_saas_architecture_screenshot.png) |
| `purchase_to_pay_swimlane` | very_hard | Management Analyst | Blank canvas + p2p_process_spec.txt on Desktop | [json](purchase_to_pay_swimlane_evidence.json) [png](purchase_to_pay_swimlane_screenshot.png) |
| `oauth2_flow_sequence` | very_hard | InfoSec Engineer | Blank canvas + oauth2_rfc_reference.txt on Desktop | [json](oauth2_flow_sequence_evidence.json) [png](oauth2_flow_sequence_screenshot.png) |
| `microservices_dependency_audit` | very_hard | Systems Analyst | Partial diagram (3/9 services) opened + service_catalog.yaml on Desktop | [json](microservices_dependency_audit_evidence.json) [png](microservices_dependency_audit_screenshot.png) |

### Verification Results (2026-02-28)

All 5 tasks validated with 3-tier testing:

**1. Do-nothing tests** (run via `test_draw_desktop_new_tasks.py`):
- All 5 tasks: score=0, passed=False ✅

**2. Wrong-target & partial completion tests** (run via `test_draw_desktop_validation.py`):
- 25/25 validation checks pass ✅
- Missing-file → score=0, passed=False (for all 5)
- Copy-of-partial → score=0, passed=False (microservices_dependency_audit)
- Partial inputs → partial scores, passed=False (verified per-task)
- Full inputs → score≥95, passed=True (verified per-task)

**3. Evidence collection** (run via `collect_draw_desktop_evidence.py`):
- Screenshots captured for all 5 tasks showing correct starting state
- Baseline JSONs captured (all show file_exists=False — correct for do-nothing state)

### Task Starting States

**chinook_database_erd** (`chinook_database_erd_screenshot.png`):
- draw.io launched, maximized, blank canvas (Untitled Diagram.drawio)
- `~/Desktop/chinook_schema.sql` present (3,485 bytes — real Chinook DDL)
- draw.io window title: `Untitled Diagram.drawio - draw.io`

**aws_saas_architecture** (`aws_saas_architecture_screenshot.png`):
- draw.io launched, maximized, blank canvas
- `~/Desktop/saas_arch_requirements.txt` present (2,475 bytes — AWS SaaS spec)

**purchase_to_pay_swimlane** (`purchase_to_pay_swimlane_screenshot.png`):
- draw.io launched, maximized, blank canvas
- `~/Desktop/p2p_process_spec.txt` present (4,187 bytes — APQC P2P spec)

**oauth2_flow_sequence** (`oauth2_flow_sequence_screenshot.png`):
- draw.io launched, maximized, blank canvas
- `~/Desktop/oauth2_rfc_reference.txt` present (5,773 bytes — RFC 6749/7636 reference)

**microservices_dependency_audit** (`microservices_dependency_audit_screenshot.png`):
- draw.io opened with partial diagram (`~/Diagrams/microservices_partial.drawio`)
- Partial diagram has 3/9 services with deliberate WRONG labels on incorrect connections
- `~/Desktop/service_catalog.yaml` present (6,251 bytes — 9-service catalog)
- `/tmp/partial_md5` records MD5 of partial file for anti-copy-paste verification

### Baseline Export JSONs (Do-Nothing State)

All 5 tasks correctly export `file_exists: false` as the baseline, confirming the verifier cannot score points without actual agent work:

```
chinook_database_erd:  {"file_exists": false, "tables_found": 0, "num_edges": 0, ...}
aws_saas_architecture: {"file_exists": false, "aws_components_found": 0, ...}
purchase_to_pay_swimlane: {"file_exists": false, "has_swimlanes": false, "num_decisions": 0, ...}
oauth2_flow_sequence:  {"file_exists": false, "participants_found": 0, "has_fragments": false, ...}
microservices_dependency_audit: {"file_exists": false, "is_copy_of_partial": false, "services_found": 0, ...}
```
