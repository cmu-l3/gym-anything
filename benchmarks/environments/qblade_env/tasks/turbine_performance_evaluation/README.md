# Task: turbine_performance_evaluation

## Overview
A wind energy analyst evaluates the NREL 5MW reference turbine's aerodynamic performance by running a BEM simulation with a TSR sweep, exporting the results, and writing a brief performance report documenting the optimal operating point.

## Domain Context
The NREL 5MW reference turbine is the most widely-used benchmark in wind energy research. Performance evaluation via BEM simulation is a standard workflow: load the turbine model, run a tip-speed-ratio sweep to generate the Cp-TSR curve, identify the optimal TSR (maximum power coefficient), and document the results. The Betz limit (theoretical max Cp = 0.593) is never reached; real turbines achieve Cp between 0.40 and 0.50 at optimal TSR, typically between 6 and 10 for modern 3-bladed HAWTs.

## Goal
Load the NREL 5MW sample project, run a BEM simulation with TSR sweep from 1 to 15, export the Cp vs TSR results, and create a report documenting the optimal TSR and max Cp.

## Starting State
- QBlade is running
- NREL 5MW .wpa file available in /home/ga/Documents/sample_projects/
- No airfoil .dat files in /home/ga/Documents/airfoils/ (this task uses a complete project)
- No BEM results or reports in /home/ga/Documents/projects/

## Success Criteria
- BEM results file exists with multi-column numeric data (>=10 TSR data points)
- Results contain Cp and TSR data labels
- Report file exists documenting optimal TSR and max Cp
- Optimal TSR value is in the realistic range (5-12)
- Max Cp value is in the realistic range (0.30-0.55)

## Verification Strategy
- BEM file existence (15 pts)
- BEM data quality (15 pts)
- BEM Cp/TSR labels (15 pts)
- Report existence (15 pts)
- Optimal TSR in report (15 pts)
- Max Cp in report (15 pts)
- QBlade running (10 pts)
- Pass threshold: 70/100

## Why This Task Is Hard
- Requires chaining multiple operations: load project → configure BEM → run simulation → export results → interpret → write report
- Agent must understand BEM simulation parameters (TSR sweep range)
- Agent must interpret numerical results to identify the optimal operating point
- Agent must create a text report with specific quantitative findings
- The task combines GUI interaction (QBlade), data interpretation, and file creation
- No UI navigation instructions provided
