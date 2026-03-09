# Task: Comparative Packaging LCA

## Domain
Life Cycle Assessment — Sustainability Consulting (Sustainability Specialists, ONET 13-1199.05)

## Overview
A beverage company needs to choose between two packaging materials for their flagship product: glass bottles or aluminum cans. As a sustainability consultant, you must conduct a comparative LCA using the openLCA desktop application and the USLCI database to quantify the environmental footprint of each option across multiple impact categories.

## Goal (End State)
A CSV file at `~/LCA_Results/packaging_comparison.csv` containing side-by-side LCIA results for glass bottle manufacturing and aluminum can manufacturing, covering at least Global Warming Potential (GWP), Acidification Potential, and one additional impact category. Each row represents one packaging alternative with its calculated environmental impact scores.

## Why This Is Hard
- The agent must locate relevant packaging processes within the USLCI database (hundreds of processes, organized in category trees)
- Two complete product systems must be built independently
- LCIA must be configured and run for both systems with identical method settings
- Results from two separate calculations must be compiled and compared
- The agent must discover the correct workflow entirely from the openLCA GUI without step-by-step instructions

## Success Criteria
1. USLCI database imported into openLCA
2. LCIA methods imported (TRACI 2.1 or equivalent)
3. Two product systems created (one for glass, one for aluminum packaging)
4. LCIA calculations run for both product systems
5. Comparison CSV exported to ~/LCA_Results/ containing both options and 3+ impact categories

## Verification Strategy
- Derby DB query: `TBL_PRODUCT_SYSTEMS` count >= 2
- Derby DB query: `TBL_IMPACT_CATEGORIES` count > 0 (LCIA methods imported)
- File check: CSV exists in ~/LCA_Results/ directory
- Content check: CSV contains keywords for both packaging materials ("glass", "aluminum"/"aluminium"/"can") and numeric values
- File size check: > 200 bytes (not empty)
- VLM trajectory: Agent navigated from database import → product systems → LCIA calculation → export

## Relevant USLCI Processes
Processes in USLCI related to packaging:
- Glass manufacturing processes (search "glass" or under Manufacturing/Glass categories)
- Aluminum/aluminium can manufacturing (search "aluminum" or "can" under Manufacturing/Metals)
- Primary production of aluminum, glass container production

## Key openLCA Tables (Derby)
- `TBL_PROCESSES`: All processes in the database
- `TBL_PRODUCT_SYSTEMS`: Created product systems
- `TBL_IMPACT_CATEGORIES`: Impact categories from imported LCIA methods
- `TBL_IMPACT_METHODS`: LCIA methods (TRACI, ReCiPe, etc.)

## Notes for Task Creator
- This task requires the agent to create TWO product systems, not just one
- The key difficulty is finding packaging-specific processes in USLCI
- The comparative CSV format is left intentionally open — the agent decides the structure
- Pass threshold: 60% of criteria met, with at least one product system and exported file
