# Task: airfoil_polar_comparison

## Overview
A wind energy engineer must compare aerodynamic performance of three candidate NACA airfoils to select the best profile for a small wind turbine. This requires importing all three airfoils, running XFoil viscous analysis on each at the same Reynolds number, and exporting the polar data for comparison.

## Domain Context
Airfoil selection is a critical early step in wind turbine blade design. Engineers compare lift-to-drag ratios (Cl/Cd), maximum lift coefficients, and stall behavior across candidate profiles. A symmetric airfoil (NACA 0015) provides baseline comparison, while cambered profiles (NACA 2412, 4412) are evaluated for their superior lift characteristics.

## Goal
Import three NACA airfoil coordinate files into QBlade, run XFoil viscous analysis on each at Re=1,000,000 (AoA -5° to 20°), and export the resulting polar data as three separate text files.

## Starting State
- QBlade is running
- Three airfoil .dat files available in /home/ga/Documents/airfoils/
- No polar data files exist

## Success Criteria
- Three polar files exist at expected paths with correct names
- Each file contains multi-column aerodynamic data (Alpha, Cl, Cd, etc.)
- Data covers the requested AoA range (including negative angles)
- At least 10 data points per polar (indicating a real XFoil run, not stub data)

## Verification Strategy
- Check existence and content of each polar file independently (3 × 25 pts)
- Verify sufficient data density across polars (15 pts)
- Verify AoA range coverage (10 pts)
- Pass threshold: 70/100

## Why This Task Is Hard
- Requires repeating a multi-step workflow (import → analyze → export) three times with different inputs
- Agent must manage multiple airfoils and their associated polars within QBlade
- Agent must correctly configure XFoil parameters (Reynolds number, AoA range) for each run
- No UI navigation instructions provided — agent must discover the import, analysis, and export workflows
