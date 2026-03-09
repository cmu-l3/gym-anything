# SciNote Environment Evidence Documentation

## Overview
This directory contains evidence of successful environment creation and testing for the SciNote ELN (Electronic Lab Notebook) environment. The environment has **8 tasks** covering project management, experiment design, protocol creation, inventory management, and workflow connections.

## Tasks (8 total)

| # | Task ID | Difficulty | Description |
|---|---------|-----------|-------------|
| 1 | create_project | Easy | Create project "Protein Crystallization Study" |
| 2 | create_experiment | Easy | Create experiment "HPLC Analysis Run 3" in existing project |
| 3 | add_task_to_experiment | Medium | Add task "Run Mass Spec Calibration" to existing experiment |
| 4 | create_protocol | Medium | Create protocol "Western Blot Analysis v2" in repository |
| 5 | create_inventory_item | Medium | Create inventory "Lab Reagents" + add item "Tris-HCl Buffer pH 7.4" |
| 6 | add_protocol_steps | Hard | Add 2 named steps with text content + checklist to protocol |
| 7 | connect_experiment_tasks | Hard | Connect 3 tasks into sequential workflow on canvas |
| 8 | setup_inventory_columns | Hard | Create inventory with custom column + 2 items with catalog numbers |

## Screenshots

### Interactive Testing (Phase 6)
| File | Description |
|------|-------------|
| `interactive_start.png` | SciNote login page after environment boot |
| `dashboard.png` | SciNote dashboard (clean view) |
| `projects_page.png` | Projects list page via sidebar navigation |
| `new_project_dialog.png` | "Create new project" dialog (empty) |
| `before_create.png` | Project dialog with "Protein Crystallization Study" typed |
| `after_create.png` | Project successfully created |

### End-to-End Test Initial Screenshots (Phase 7)
| File | Description |
|------|-------------|
| `e2e_create_project_initial.png` | Initial state for create_project task |
| `e2e_create_experiment_initial.png` | Initial state for create_experiment task |
| `e2e_add_task_to_experiment_initial.png` | Initial state for add_task_to_experiment task |
| `e2e_create_protocol_initial.png` | Initial state for create_protocol task |
| `e2e_create_inventory_item_initial.png` | Initial state for create_inventory_item task |
| `e2e_add_protocol_steps_initial.png` | Initial state for add_protocol_steps task |
| `e2e_connect_experiment_tasks_initial.png` | Initial state for connect_experiment_tasks task |
| `e2e_setup_inventory_columns_initial.png` | Initial state for setup_inventory_columns task |

## Logs

| File | Description |
|------|-------------|
| `e2e_test_log.txt` | Full end-to-end test output (env.reset + env.step) |
| `install_log_*.txt` | pre_start hook (install) logs per task |
| `setup_log_*.txt` | post_start hook (setup) logs per task |
| `task_setup_log_create_project.txt` | pre_task hook log snippet |

## Verification Results

| File | Description |
|------|-------------|
| `verification_create_project.json` | Baseline verification (score=0) |
| `verification_create_experiment.json` | Baseline verification (score=0) |
| `verification_add_task_to_experiment.json` | Baseline verification (score=0) |
| `verification_create_protocol.json` | Baseline verification (score=0) |
| `verification_create_inventory_item.json` | Baseline verification (score=0) |
| `verification_add_protocol_steps.json` | Baseline verification (score=0) |
| `verification_connect_experiment_tasks.json` | Baseline verification (score=0) |
| `verification_setup_inventory_columns.json` | Baseline verification (score=0) |
| `verification_all_tasks.txt` | All 8 tasks verification summary |
| `e2e_all_tasks_summary.json` | Subset of tasks tested end-to-end |

## Key Results

- **Installation**: Docker-ce + SciNote Docker build completes (~10 min first time)
- **Setup**: All 3 containers start (scinote_web, scinote_jobs, scinote_db)
- **HTTP**: SciNote responds with 200/302 at localhost:3000
- **Firefox**: Login page displayed correctly
- **Baseline verification**: All 8 tasks return score=0, passed=false
- **Post-completion verification**: All 8 tasks return max score with passed=true
  - Tasks 1-5,7: max score=100
  - Tasks 6,8: max score=80 (4-6 criteria x weighted pts)
  - Tasks 6,7,8 live-tested on 2026-02-13 with full env boot + DB simulation + verifier run

## Reliability Improvements

- Docker health checks + HTTP readiness wait loop added to `ensure_firefox_running()` in `task_utils.sh`
- `user_assignments` records created for all SQL-inserted prerequisite data (projects, experiments, tasks) to ensure visibility in SciNote UI
- Projects created with `visibility=1` (visible to all team members) instead of `visibility=0`
- Firefox profile updated with comprehensive first-run dialog suppression (Privacy Notice, data reporting, telemetry)

## Test Methodology

1. **Interactive testing**: Used ask_cua.py for coordinate detection + xdotool for mouse/keyboard actions via SSH to QEMU VM
2. **Verifier testing**: Direct SQL manipulation to simulate task completion, then ran export_result.sh + verifier.py
3. **End-to-end test**: `env.reset(seed=42, use_cache=False)` followed by `env.step([], mark_done=True)` through the framework

---

## New Tasks (5 added)

| # | Task ID | Difficulty | Domain | Description |
|---|---------|-----------|--------|-------------|
| 9 | crispr_knockout_screen | very_hard | Molecular Biology | Build complete CRISPR knockout screen ELN from scratch: project, 2 experiments, 5 tasks with connections, ≥6-step protocol, reagent inventory |
| 10 | western_blot_workflow | hard | Biochemistry | Complete pre-seeded western blot workflow: add 2 tasks, connect all 4 in chain, add protocol, create reagent inventory with catalog numbers |
| 11 | elisa_assay_setup | hard | Immunology | Extend pre-seeded ELISA project: create experiment, 4 connected tasks, protocol, expand inventory with new columns and real antibody items |
| 12 | rnaseq_qc_documentation | very_hard | Genomics | Build RNA-seq QC pipeline ELN from scratch: project, 2 experiments (wet-lab + bioinformatics), 7 tasks, connections, protocol, reagent inventory |
| 13 | cell_culture_drug_treatment | hard | Cancer Biology | Complete pre-seeded drug study: add 2 tasks, connect all 4, add drug treatment protocol, expand drug stock inventory with real anticancer compounds |

## New Task Testing (performed 2026-03-05)

All 5 new tasks passed the following validation tests:

| Test Type | Method | All Pass? |
|-----------|--------|-----------|
| Bash syntax check | `bash -n *.sh` | ✅ Yes |
| Python compile check | `python3 -m py_compile verifier.py` | ✅ Yes |
| JSON validity | `python3 -m json.tool task.json` | ✅ Yes |
| Do-nothing test | Local verifier with empty result | ✅ score=0, passed=False |
| Wrong-target test | Local verifier with wrong-entity result | ✅ passed=False for all |
| Partial completion test | Local verifier with partial result | ✅ 0 < score < 100, passed=False |

### Partial Scores (by task)
- crispr_knockout_screen: 40/100 (partial: project + 1 exp + 2 tasks + 1 connection)
- western_blot_workflow: 29/100 (partial: 1 new task + 3 tasks total + 1 connection)
- elisa_assay_setup: 50/100 (partial: experiment + 2 tasks + 1 connection + 1 column + 1 item)
- rnaseq_qc_documentation: 48/100 (partial: project + 1 exp + 3 tasks + 2 connections)
- cell_culture_drug_treatment: 58/100 (partial: 1 new task + 2 connections + partial protocol + 1 column + 1 item)

### Evidence Files
- `evidence_crispr_knockout_screen.json`
- `evidence_western_blot_workflow.json`
- `evidence_elisa_assay_setup.json`
- `evidence_rnaseq_qc_documentation.json`
- `evidence_cell_culture_drug_treatment.json`
- `new_tasks_local_tests.json` (combined test results)
