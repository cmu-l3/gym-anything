# Task: dissolve_by_continent

## Overview

**Difficulty**: very_hard
**Occupation**: Cartographers and Photogrammetrists (O*NET 17-1021.00)
**Industry**: Architecture and Engineering
**Environment**: gvSIG Desktop 2.4.0

## Task Description

A cartographer needs to create a continental base map by dissolving all country polygons into continent-level polygons. This is a standard cartographic generalization operation.

**Input**: `/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp` (177 country features)
**Dissolve field**: `CONTINENT`
**Output**: `/home/ga/gvsig_exports/continents_dissolved.shp` (~7-8 continent features)

The output should have drastically fewer features than the input (one per continent), with the `CONTINENT` attribute preserved.

## Why This Is Hard

1. Requires knowing about the Dissolve geoprocessing operation — not a basic layer management task
2. In gvSIG, the Dissolve tool is in the Geoprocessing toolbox, which may require enabling or navigating the Sextante/SAGA integration
3. Must identify the correct dissolve field (`CONTINENT`) from the attribute table
4. The agent must distinguish between:
   - Regular Export (gives 177 features — wrong)
   - Dissolve (gives ~7-8 features — correct)
5. Output must preserve the CONTINENT attribute, not just geometry

## Expected Output

The Natural Earth 110m countries dataset contains these CONTINENT values:
- Africa
- Antarctica
- Asia
- Europe
- North America
- Oceania
- Seven seas (open ocean)
- South America

Total: 8 distinct values → 8 features in output (or 7 if Antarctica is excluded)

## Verification Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists | 20 | Output shapefile must exist |
| Dissolve GATE | — | Feature count > 50 → score capped (not dissolved) |
| Feature count [5, 10] | 25 | Confirms dissolve was applied |
| CONTINENT field present | 25 | Dissolve field preserved in output |
| Africa present | 10 | Key continent confirmed |
| Asia present | 10 | Key continent confirmed |
| Europe present | 10 | Key continent confirmed |
| **Total** | **100** | Pass threshold: 60/100 |

## Real Data Source

Natural Earth 1:110m Cultural Vectors (Admin-0 Countries)
URL: https://www.naturalearthdata.com/downloads/110m-cultural-vectors/
License: Public Domain

## Workflow Note (for task designers)

In gvSIG Desktop, the Dissolve operation can be accessed via:
- Menu: Geoprocesses → Geoprocessing toolbox (Sextante) → Dissolve polygons
- OR: Through the SAGA GIS integration in the Sextante toolbox

The agent must:
1. Load the countries layer
2. Navigate to the Geoprocessing/Sextante dissolve tool
3. Select CONTINENT as the dissolve field
4. Set output path to `/home/ga/gvsig_exports/continents_dissolved.shp`
5. Run the tool
