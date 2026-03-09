# StudioTax 2024 Environment — Evidence Documentation

## Verification Checklist Results

All items verified via clean `env.reset(seed=42, use_cache=False)` on 2026-02-26.

| # | Check | Status | Evidence |
|---|-------|--------|----------|
| 1 | Installation script completes without errors | PASS | pre_start log shows "StudioTax installed successfully" |
| 2 | Setup script completes without errors | PASS | post_start log shows "StudioTax 2024 setup complete" |
| 3 | Application is visible in screenshot | PASS | `final_clean_start_task_state.png` — StudioTax 2024 window visible |
| 4 | Application in correct initial state | PASS | Start Page showing, no pre-existing returns |
| 5 | Real data loaded and visible | PASS | 5 CRA tax scenario files in TaxScenarios folder on Desktop |
| 6 | Task setup runs without errors | PASS | pre_task hook completed in 36.2 seconds |
| 7 | Task start state correct (visual_grounding) | PASS | All 6 visual checks passed (see below) |
| 8 | Evidence task is completable | PASS | Agent can click "Create a new return" and enter data from scenario |

## Visual Grounding Verification (MCP tool: visual_grounding)

Ran on `final_clean_start_task_state.png`:

1. **StudioTax 2024 is the main visible application** — YES, title bar shows "StudioTax 2024"
2. **Start Page with create/open options** — YES, three main buttons visible
3. **Recent Returns area empty** — YES, no pre-existing returns
4. **No error dialogs or popups** — YES, interface is clean
5. **TaxScenarios folder on desktop** — YES, visible at bottom-left
6. **StudioTax 2024 shortcut on desktop** — YES, visible on left side

## Log Snippets

### Pre-start hook (install_studiotax.ps1)

```
=== Installing StudioTax 2024 ===
StudioTax not found. Downloading installer...
Download complete: C:\Windows\Temp\StudioTax2024Install.exe
Installer size: 65058520 bytes
Launching installer in interactive desktop session...
Installer launched. Waiting for GUI to appear...
Running installer automation via PyAutoGUI...
Automation script exit code: 0
StudioTax installed successfully at: C:\Program Files\BHOK IT Consulting Inc\StudioTax 2024\StudioTax.exe
Install path saved to C:\Users\Docker\studiotax_path.txt
=== StudioTax installation phase complete ===
```

### Post-start hook (setup_studiotax.ps1)

```
=== Setting up StudioTax 2024 environment ===
Copying tax scenario data files...
Scenario files copied to C:\Users\Docker\Desktop\TaxScenarios
StudioTax executable: C:\Program Files\BHOK IT Consulting Inc\StudioTax 2024\StudioTax.exe
Performing warm-up launch of StudioTax...
Dismissing startup dialogs...
Closing StudioTax after warm-up...
=== StudioTax 2024 setup complete ===
```

### Pre-task hook (enter_t4_employment_income/setup_task.ps1)

```
=== Setting up enter_t4_employment_income task ===
StudioTax running (PID: 944)
=== Task setup complete ===
```

### Timing (from env.reset profiling)

```
Env setup took 250.18 seconds:
  - pre_start + post_start: 213.97s (download + install + setup)
  - pre_task: 36.21s (task setup + StudioTax launch)
```

## Screenshots

| File | Description |
|------|-------------|
| `installer_gui_language_page.png` | StudioTax installer wizard — language selection page |
| `installer_ready_to_install.png` | Installer wizard — Ready to Install page |
| `installer_complete.png` | Installer wizard — Setup Complete page |
| `studiotax_start_page.png` | StudioTax 2024 start page (first interactive test) |
| `task_setup_ready.png` | StudioTax after task setup (first interactive test) |
| `final_clean_start_task_state.png` | **Final clean test** — StudioTax start state after full env.reset() |

## Scenario Data (Real CRA Educational Data)

All scenario data comes from the Canada Revenue Agency's "Learn About Your Taxes" educational program:

| File | Taxpayer | Province | Income | Key Forms |
|------|----------|----------|--------|-----------|
| scenario_jonah_smith.txt | Jonah Smith | NL | $18,205 | T4 (CPP/EI/RPP/union) |
| scenario_terry_lee.txt | Terry Lee | BC | $12,005 + tips | T4, cash tips, RRSP |
| scenario_farah_awan.txt | Farah Awan | ON | Student | T4, T5007, T4A, T2202 |
| scenario_investment.txt | Maria Chen | ON | $65,000 + investments | T4, T5, T5008 |
| scenario_multi_employer.txt | Han Park | ON | $60,500 (2 employers) | 2×T4, medical, donations |

## Environment Configuration

- **Base**: Windows 11 Enterprise Evaluation (QEMU/KVM)
- **Resources**: 4 CPU, 8GB RAM, networking enabled
- **Resolution**: 1280x720 (PyAutoGUI native)
- **Install path**: `C:\Program Files\BHOK IT Consulting Inc\StudioTax 2024\StudioTax.exe`
- **Save format**: `.24t` files in `C:\Users\Docker\Documents\StudioTax\`
