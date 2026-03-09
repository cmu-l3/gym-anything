# Microsoft Excel Env - Evidence (Live Run)

This folder contains screenshots and logs captured from a real Windows 11 VM run of `microsoft_excel_env@0.1`.

## Run Metadata

See `run_metadata.txt` for the exact ports, env hash, and timestamps.

## Checklist Evidence

- Environment boots and is reachable:
  - `run_metadata.txt` (SSH/VNC/PyAutoGUI ports)
- `post_start` completes and data is present on the Desktop:
  - `env_setup_post_start.log`
  - `desktop_exceltasks_listing.txt`
- Excel is installed:
  - `env_setup_pre_start.log` (install script transcript shows EXCEL.EXE detected)
- Task start states are correct (Excel opened to the right workbook):
  - `01_sum_formula_start.png`
  - `03_create_chart_start.png`
  - `04_conditional_formatting_start.png`
- Sum-formula task was exercised via live UI actions (keyboard/mouse through PyAutoGUI server):
  - `02_sum_formula_after_actions.png`
- Task setup hook logs (PowerShell transcripts):
  - `task_pre_task_sum_formula.log`
  - `task_pre_task_create_chart.log`
  - `task_pre_task_conditional_formatting.log`
- Final state screenshot:
  - `05_final_desktop.png`

## Notes

- The environment was started from the cached `pre_start` checkpoint (Excel already installed). Because `pre_start` is skipped when loading this checkpoint, `install_excel.ps1` was executed once during the run to capture `env_setup_pre_start.log` for evidence.

