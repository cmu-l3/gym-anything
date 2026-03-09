# Task: Monte Carlo Uncertainty Quantification

## Domain
Life Cycle Assessment — Industrial Ecology & Uncertainty Analysis (Industrial Ecologists, ONET 19-2041.03)

## Overview
Carbon footprint studies require quantifying uncertainty to be scientifically rigorous. This task requires an industrial ecologist to use openLCA's Monte Carlo simulation capability to propagate parameter uncertainties through a full LCA of coal-fired electricity generation, producing statistically meaningful results with confidence intervals.

## Goal (End State)
A CSV file at `~/LCA_Results/monte_carlo_results.csv` containing Monte Carlo simulation results for the GWP of coal electricity, including mean, standard deviation, and 95% confidence interval. The database must contain a product system with at least 3 defined parameters with uncertainty distributions.

## Why This Is Hard
- Monte Carlo simulation is a non-obvious feature in openLCA (found in Calculation Setup dialog, not standard LCIA)
- Parameter uncertainty setup requires navigating the parameter editor and specifying statistical distributions
- Finding the correct coal electricity process in USLCI requires domain knowledge and search skills
- Requires understanding of probability distributions (log-normal, normal) for environmental data
- Exporting Monte Carlo statistics requires interacting with a dedicated results dialog
- Must chain: DB import → process search → product system → parameter setup → Monte Carlo config → run (slow) → export

## Success Criteria
1. USLCI database imported, LCIA methods available
2. Product system built for a coal electricity generation process
3. At least 3 parameters defined with uncertainty distributions
4. Monte Carlo simulation run (500+ iterations for GWP)
5. Results exported to CSV with statistical summary

## Verification Strategy
- Derby query: `TBL_PRODUCT_SYSTEMS` count >= 1
- Derby query: `TBL_PARAMETERS` count >= 3 (parameters defined)
- File check: CSV/Excel in ~/LCA_Results/ with Monte Carlo statistics keywords
- Content check: File contains "mean", "standard deviation", "confidence" or equivalent statistical terms
- VLM trajectory: Progression through parameter editor → Monte Carlo dialog → results

## openLCA Monte Carlo Workflow
In openLCA 2.x:
1. Open product system → Click "Calculate" (or use menu)
2. In Calculation Setup dialog, select "Monte Carlo Simulation" as calculation type
3. Set number of iterations (e.g., 500 or 1000)
4. Select impact method (TRACI 2.1 for GWP)
5. Click "Run" → wait for simulation (may take minutes)
6. In Monte Carlo Results view: see statistics table
7. Export via "Export results" button → CSV

## Parameter Setup in openLCA
Parameters can be defined at:
- Global level: Database > Parameters (applies to all processes)
- Process level: Inside a process editor > Parameters tab
Each parameter can have: name, value, uncertainty type (normal, log-normal, etc.), standard deviation/geometric std dev

## Key openLCA Tables
- `TBL_PARAMETERS`: Defined parameters with uncertainty settings
- `TBL_PRODUCT_SYSTEMS`: Product systems
- `TBL_IMPACT_CATEGORIES`: Impact method categories
