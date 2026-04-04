# Task: extrapolate_polar_360

## Overview
A wind turbine engineer must prepare airfoil polar data for BEM (Blade Element Momentum) simulation. BEM requires aerodynamic coefficients across the full 360° angle of attack range, but XFoil can only reliably compute data over a limited range. QBlade provides a polar extrapolation module that extends XFoil results to 360° using the Viterna/Montgomery method.

## Domain Context
In wind turbine design, blades can experience extreme angles of attack during startup, shutdown, yaw misalignment, and turbulent gusts. BEM codes need full 360° polar data to handle these operating conditions. The standard workflow is: import airfoil → run XFoil at design Reynolds number → extrapolate to 360° → use in BEM. This task covers the first three stages of this pipeline.

## Goal
Starting from a NACA 6412 airfoil coordinate file, chain three distinct QBlade modules: (1) import the airfoil, (2) run XFoil analysis at Re=500,000 covering AoA -10° to 25°, and (3) extrapolate the resulting polar to the full 360° range. Export the extrapolated polar.

## Starting State
- QBlade is running
- Only naca6412.dat available in /home/ga/Documents/airfoils/ (other airfoils removed)
- No polar or analysis data exists

## Success Criteria
- Exported file exists at expected path
- Contains multi-column aerodynamic data with >= 30 data points
- Contains AoA values beyond ±90° (evidence of 360° extrapolation, not just raw XFoil)
- Base XFoil range (-10° to 25°) is present within the extrapolated data
- File references the NACA 6412 airfoil

## Verification Strategy
- File existence and data validation (20 + 15 pts)
- Data density check >= 30 points (15 pts)
- 360° extrapolation evidence: AoA beyond ±90° (25 pts)
- Airfoil reference (10 pts)
- Base polar range coverage (15 pts)
- Pass threshold: 70/100

## Why This Task Is Hard
- Requires chaining 3 distinct QBlade modules sequentially (Foil Design → XFoil Analysis → 360° Extrapolation)
- Each module has its own UI, parameters, and workflow
- Agent must understand the pipeline dependency: extrapolation requires an existing XFoil polar
- No UI navigation instructions provided
- The 360° extrapolation module is not an obvious feature — agent must explore the toolbar/menus
