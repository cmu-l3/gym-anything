# Task: design_hawt_blade_multisection

## Overview
A blade engineer designs a small HAWT blade with a realistic multi-section layout: thick symmetric airfoils at the root for structural integrity, transitioning to thin cambered airfoils at the tip for aerodynamic performance. The blade must have at least 6 radial stations with a tapering chord distribution.

## Domain Context
Real wind turbine blades are not uniform — they use different airfoil profiles along their span. The root section, which carries the highest bending loads, uses thick symmetric or near-symmetric airfoils (15-30% thickness) for structural strength. The tip section, where aerodynamic efficiency matters most, uses thin cambered airfoils (12-18% thickness) optimized for high lift-to-drag ratio. The chord tapers from wide at the root to narrow at the tip following the Betz optimum distribution.

## Goal
Import two airfoil profiles, navigate to the HAWT Blade Design module, create a blade with 6+ stations spanning 0.5m to 5.0m radius using NACA 0015 inboard and NACA 4412 outboard, set a tapering chord distribution, and save the project.

## Starting State
- QBlade is running
- naca0015.dat and naca4412.dat available in /home/ga/Documents/airfoils/ (other airfoils removed)
- No existing blade projects in /home/ga/Documents/projects/

## Success Criteria
- .wpa project file exists at expected path
- File is NOT a copy of any sample project (hash-verified)
- File is substantial (>5KB) indicating real blade geometry data
- Project contains complex content (>20KB preferred) for multi-station blade

## Verification Strategy
- File existence (25 pts)
- Anti-copy check against all sample projects (20 pts)
- File size > 5KB (20 pts)
- New work detected (10 pts)
- Complex content > 20KB (15 pts)
- QBlade running (10 pts)
- Pass threshold: 70/100

## Why This Task Is Hard
- Requires chaining multiple QBlade modules: Foil Design (import 2 airfoils) → HAWT Blade Design (create blade)
- Agent must understand multi-section blade design: assign different airfoils to different stations
- Agent must configure numeric parameters: station positions, chord values, twist angles
- Agent must use the blade design table interface to add stations and set per-station properties
- No UI navigation instructions provided
- The blade design module has a complex table-based interface requiring precise data entry
