# urban_sim_env Evidence Documentation

**Date:** 2026-02-07
**Tested by:** Automated evidence collection via `test_urban_sim_env.py --all`

## All 5 Tasks: End-to-End Test Results

| Task | Status | Screenshot | Notebook | Jupyter | Firefox | Export |
|------|--------|------------|----------|---------|---------|--------|
| explore_zoning_data | PASS | task_explore_zoning_data.png | zoning_exploration.ipynb | Running | Running | Valid JSON |
| run_hedonic_regression | PASS | task_run_hedonic_regression.png | hedonic_model.ipynb | Running | Running | Valid JSON |
| estimate_development_feasibility | PASS | task_estimate_development_feasibility.png | development_feasibility.ipynb | Running | Running | Valid JSON |
| run_location_choice_model | PASS | task_run_location_choice_model.png | location_choice.ipynb | Running | Running | Valid JSON |
| run_simulation_year | PASS | task_run_simulation_year.png | simulation.ipynb | Running | Running | Valid JSON |

## Environment Boot Verification

### Pre-start Hook (install_urbansim.sh)
- **Status:** SUCCESS
- **Duration:** ~105-134 seconds
- **Python:** 3.10.12
- **UrbanSim:** 3.2
- **Statsmodels:** 0.14.6
- **Matplotlib:** 3.10.8
- **ipykernel:** 7.2.0
- **Jupyter kernel registered:** `urbansim` at `/usr/local/share/jupyter/kernels/urbansim`

### Data Verification
HDF5 tables in `sanfran_public.h5` (9.8MB):
| Table | Rows | Columns |
|-------|------|---------|
| /buildings | 152,605 | 9 |
| /households | 345,588 | 5 |
| /jobs | 225,439 | 2 |
| /parcels | 153,341 | 7 |
| /zones | 1,454 | 4 |
| /zoning | 6,962 | 19 |
| /zoning_for_parcels | 148,318 | 1 |

**Note:** Parcels has only 7 columns. `zoning_id` is NOT a direct column on parcels. The `zoning_for_parcels` intermediary table must be used. Task description for `estimate_development_feasibility` has been updated with fallback guidance.

Zoning table columns: `name, max_height, city, max_far, coverage, type1-type14`

### Post-start Hook (setup_urbansim.sh)
- **Status:** SUCCESS
- **Jupyter Lab:** Running on port 8888
- **Firefox:** Running, window visible with JupyterLab

## Screenshot Evidence (All 5 Tasks)

### task_explore_zoning_data.png (163KB)
- Firefox maximized showing JupyterLab
- URL: `http://localhost:8888/lab/tree/notebooks/zoning_exploration.ipynb`
- Title: "San Francisco Zoning Data Exploration"
- Requirements: Load zoning data, display first 10 rows, calculate summary statistics, count districts, create FAR histogram, save CSV
- Kernel: "UrbanSim (Python 3) | Idle"
- Code cell: `# Write your code here`

### task_run_hedonic_regression.png (165KB)
- Firefox maximized showing JupyterLab
- URL: `http://localhost:8888/lab/tree/notebooks/hedonic_model.ipynb`
- Title: "Hedonic Pricing Model for San Francisco Buildings"
- Requirements: Load buildings data, use 3+ predictors, handle missing values, save coefficients CSV, save scatter plot
- Kernel: "UrbanSim (Python 3) | Idle"
- Code cell: `# Write your code here`

### task_estimate_development_feasibility.png (170KB)
- Firefox maximized showing JupyterLab
- URL: `http://localhost:8888/lab/tree/notebooks/development_feasibility.ipynb`
- Title: "Development Feasibility Analysis"
- Requirements: Load parcels/buildings/zoning, calculate density, identify feasible parcels (<50% of max), save top 100 CSV, save chart
- Kernel: "UrbanSim (Python 3) | Idle"
- Code cell: `# Write your code here`

### task_run_location_choice_model.png (161KB)
- Firefox maximized showing JupyterLab
- URL: `http://localhost:8888/lab/tree/notebooks/location_choice.ipynb`
- Title: "Household Location Choice Model"
- Requirements: Load households/buildings, merge on building_id, use 3+ features, save coefficients CSV, save bar chart
- Kernel: "UrbanSim (Python 3) | Idle"
- Code cell: `# Write your code here`

### task_run_simulation_year.png (159KB)
- Firefox maximized showing JupyterLab
- URL: `http://localhost:8888/lab/tree/notebooks/simulation.ipynb`
- Title: "UrbanSim Simulation: Year 2010"
- Requirements: Load data, register tables with orca, define 2+ steps, run year 2010, save summary CSV, save chart
- Kernel: "UrbanSim (Python 3) | Idle"
- Code cell: `# Write your code here`

## Export Script Baseline (All 5 Tasks)

All export scripts produce valid JSON with correct baseline values (agent hasn't written code yet):
- `notebook_exists: true`
- `notebook_modified: true`
- `num_executed_cells: 0`
- `csv_exists: false`
- `plot_exists: false`
- Task-specific analysis fields all `false` (correct for empty notebook)

Individual result files:
- `explore_zoning_data_result.json`
- `run_hedonic_regression_result.json`
- `estimate_development_feasibility_result.json`
- `run_location_choice_model_result.json`
- `run_simulation_year_result.json`

## Pre-task Log Verification

Each task's setup script runs successfully, confirming:
- Data files are accessible and loadable
- Correct tables/columns identified per task
- Notebook created with proper content
- Task start time recorded

Example logs:
- **explore_zoning_data:** "Zoning table: 6962 rows, columns: ['name', 'max_height', 'city', 'max_far', ...]"
- **run_hedonic_regression:** "Buildings table: 152605 rows, columns: ['parcel_id', 'residential_units', ...]"
- **estimate_development_feasibility:** "Parcels: 153341 rows", "Buildings: 152605 rows", "Zoning: 6962 rows"
- **run_location_choice_model:** "Households: 345588 rows", "Buildings: 152605 rows"
- **run_simulation_year:** Lists all 7 HDF5 tables with row counts

## Window Title Confirmation

Each task shows the correct notebook in Firefox window title:
- `zoning_explo... - JupyterLab -- Mozilla Firefox`
- `hedonic_mode... - JupyterLab -- Mozilla Firefox`
- `development_... - JupyterLab -- Mozilla Firefox`
- `location_cho... - JupyterLab -- Mozilla Firefox`
- `simulation.i... - JupyterLab -- Mozilla Firefox`

## Known Issues (Minor)
1. Jupyter notification popup ("Would you like to get notified about official Jupyter news?") appears at bottom-right on all tasks. Minor -- can be dismissed by agent clicking "No".
2. Python one-liner commands via `exec_capture` have quoting issues with nested quotes through SSH. Use heredoc or script files for complex Python commands in test scripts.
