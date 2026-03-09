# Task: EPD Multi-Impact Category Analysis

## Domain
Life Cycle Assessment — Environmental Product Declarations (Sustainability Specialists, ONET 13-1199.05)

## Overview
Environmental Product Declarations (EPDs) are standardized documents (based on ISO 14044 and PCRs) that report a product's environmental impact across multiple categories. Unlike a simple carbon footprint, EPDs require at least 5 impact categories. This task requires the agent to set up, calculate, and export a complete multi-category LCIA suitable for an EPD for a transportation or agricultural process.

## Goal (End State)
A CSV file at `~/LCA_Results/epd_results.csv` containing rows for each impact category (minimum 5: GWP, Acidification, Eutrophication, Ozone Depletion, plus at least one more), with columns for category name, unit, and calculated numeric value. This represents the environmental profile section of an EPD.

## Why This Is Hard
- The agent must configure LCIA to calculate MULTIPLE impact categories simultaneously (not just GWP)
- Requires understanding which LCIA method (TRACI 2.1 is the US standard for EPDs) covers all required categories
- Must navigate the openLCA results view to see all categories at once
- Exporting ALL categories to a structured CSV requires knowing the export format options
- Must identify and use a transport/agricultural process (different domain than other tasks)
- Requires domain knowledge: what impact categories are required for EPDs, what units are used (kg CO2-eq, mol H+ eq, kg N-eq, kg CFC-11-eq, etc.)

## Success Criteria
1. USLCI database and LCIA methods imported
2. Product system created for a transport or agricultural process
3. LCIA run with at least 5 distinct impact categories
4. All categories exported to CSV with name, unit, and value

## Verification Strategy
- Derby: `TBL_PRODUCT_SYSTEMS` count >= 1
- Derby: `TBL_IMPACT_CATEGORIES` count >= 5 (LCIA method has 5+ categories)
- File: CSV in ~/LCA_Results/ with size > 500 bytes (multiple rows expected)
- Content: CSV contains at least 3 of: "global warming", "acidification", "eutrophication", "ozone", "smog", "human health", "ecotoxic"
- Content: CSV contains multiple numeric values (multiple impact categories)
- Row count: CSV has at least 5 data rows

## openLCA Multi-Category LCIA Workflow
1. After building product system, click "Calculate"
2. In Calculation Setup:
   - Select TRACI 2.1 (covers: GWP, Acidification, Eutrophication, Ozone Depletion, Smog Formation, Carcinogens, Non-carcinogens, Ecotoxicity, Fossil Fuel Depletion)
   - Select "LCIA" calculation type
3. Run calculation → results show ALL impact categories at once
4. In results editor, see table with all categories
5. Export: Right-click → Export results → CSV or Excel
   - This creates a file with ALL categories automatically

## EPD Impact Categories (TRACI 2.1 for North American EPDs)
| Category | Unit |
|----------|------|
| Global Warming Potential | kg CO2-eq |
| Acidification | mol H+ eq |
| Eutrophication | kg N-eq |
| Ozone Depletion | kg CFC-11-eq |
| Smog Formation | kg O3-eq |
| Human Health - Carcinogens | CTUh |
| Human Health - Non-carcinogens | CTUh |
| Ecotoxicity | CTUe |
| Fossil Fuel Depletion | MJ surplus |

## Relevant USLCI Processes (Transport & Agriculture)
**Transport:**
- "transport, truck" or "freight, lorry" — diesel road transport
- "transport, rail" — freight by rail
- "transport, barge" — inland waterway
- "transport, pipeline" — pipeline transport

**Agriculture:**
- "corn production" or "maize" — field crop
- "soybean" — oilseed crop
- "wheat" — grain crop
- "rice" or "cotton" — other crops
