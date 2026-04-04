# Task: multi_reynolds_analysis

## Overview
A wind turbine aerodynamicist must characterize how the NACA 4412 airfoil performs across a range of Reynolds numbers. Different positions along a turbine blade experience different local Reynolds numbers due to varying chord lengths and velocities, so understanding Re-dependent performance is essential for accurate blade design.

## Domain Context
Reynolds number effects are a fundamental concern in wind turbine aerodynamics. At low Re (near root, or on small turbines), laminar separation bubbles form earlier, reducing maximum lift and increasing drag. At high Re (near tip, or on large turbines), the boundary layer transitions earlier, producing higher maximum lift and lower drag. Engineers run parametric XFoil studies at multiple Re to capture this behavior before feeding polars into BEM codes.

## Goal
Import the NACA 4412 airfoil and run three separate XFoil analyses at Re = 200,000 / 500,000 / 1,000,000, each covering AoA -5° to 15°. Export three polar datasets to separate files.

## Starting State
- QBlade is running
- Only naca4412.dat available in /home/ga/Documents/airfoils/ (other airfoils removed)
- No polar data exists

## Success Criteria
- Three polar files exist at expected paths with correct Re-specific names
- Each contains multi-column aerodynamic data
- Sufficient data density (>=10 points per polar)
- AoA range includes negative angles

## Verification Strategy
- Each polar checked independently (3 × 25 pts)
- Data density across polars (15 pts)
- AoA coverage (10 pts)
- Pass threshold: 70/100

## Why This Task Is Hard
- Requires running the same analysis workflow 3 times with different Reynolds number parameters
- Agent must correctly reconfigure XFoil's Reynolds number between each run
- Agent must manage 3 separate polar datasets and export each to a differently-named file
- Agent must understand what Reynolds number is and where to set it in the UI
- No UI navigation instructions provided
