# Task: Supply Chain Hotspot Analysis

## Domain
Life Cycle Assessment — Construction Material Impact (Sustainability Specialists, ONET 13-1199.05; Industrial Ecologists, ONET 19-2041.03)

## Overview
Identifying environmental hotspots — the steps in a supply chain that contribute most to environmental impact — is a core skill in sustainability consulting. This task requires the agent to build a multi-level supply chain model for cement or concrete production and perform a process contribution analysis to determine which upstream activities drive the most global warming potential.

## Goal (End State)
A CSV file at `~/LCA_Results/hotspot_analysis.csv` listing upstream process names and their percentage contribution to the total GWP of cement/concrete production. The product system must include at least 4 resolved upstream supply chain links. Results must be based on an actual LCIA calculation.

## Why This Is Hard
- Agent must navigate the process tree in USLCI to find cement/concrete processes
- Product system creation with upstream supply chain expansion requires deliberate "auto-link" or manual connection of processes
- Contribution analysis is a specific view INSIDE the LCIA results — the agent must navigate from calculation results to the contribution breakdown
- Exporting contribution data as a CSV (not just the main LCIA result) requires finding a specific export option
- The entire workflow (import → product system → LCIA → contribution → export) spans 5+ major application features

## Success Criteria
1. USLCI database and LCIA methods imported
2. Product system created for a cement/concrete process
3. Supply chain expanded (at least 4 upstream processes linked)
4. LCIA calculation performed
5. Contribution analysis exported to CSV with process names and percentages

## Verification Strategy
- Derby: `TBL_PRODUCT_SYSTEMS` count >= 1
- Derby: `TBL_IMPACT_CATEGORIES` count > 0 (LCIA methods present)
- File: CSV in ~/LCA_Results/ with size > 200 bytes
- Content: CSV contains "%" or percentage values and process/supply chain names
- Content: Contains cement/concrete-related keywords ("cement", "concrete", "clinker", "limestone", "kiln", "aggregate")
- VLM: Trajectory shows contribution analysis view (process tree with percentages)

## openLCA Contribution Analysis Workflow
In openLCA 2.x, after running LCIA:
1. The results editor opens showing impact category values
2. Click on a specific impact category → opens detailed view
3. There is a "Process contributions" or "Contribution tree" tab/button
4. This shows a tree of upstream processes with their percentage contributions
5. Right-click or use "Export" button to save as CSV/Excel

Alternative: Use "Sankey diagram" view which shows process contributions visually

## Relevant USLCI Processes
Search terms for cement/concrete in USLCI:
- "cement" → Portland cement production
- "concrete" → ready-mix concrete
- "clinker" → cement clinker production
- "limestone" → raw material for cement
- "fly ash" → used in concrete blending

## Key openLCA Tables
- `TBL_PRODUCT_SYSTEMS`: Created product systems
- `TBL_PROCESSES`: All processes (USLCI has cement/concrete processes)
- `TBL_IMPACT_CATEGORIES`: Loaded LCIA impact categories
