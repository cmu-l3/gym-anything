# Task: buffer_world_capitals

## Overview

**Difficulty**: very_hard
**Occupation**: Urban and Regional Planners (O*NET 19-3051.00)
**Industry**: Life, Physical, and Social Science
**Environment**: gvSIG Desktop 2.4.0

## Task Description

An urban planning consultant needs to generate influence/reach zones around world capital cities for a comparative governance analysis. The task requires:

1. Loading the populated places layer
2. Either pre-filtering to Admin-0 capitals OR buffering all points and letting the task description guide selection
3. Applying a 2-degree radius buffer around each capital
4. Exporting the buffer polygons with original attributes

**Input**: `/home/ga/gvsig_data/cities/ne_110m_populated_places.shp`
**Filter**: `FEATURECLA = 'Admin-0 capital'`
**Buffer radius**: 2 geographic degrees
**Output**: `/home/ga/gvsig_exports/capital_buffers.shp`

## Why This Is Hard

1. Requires loading a new shapefile not present in the default project
2. Must filter the points to only Admin-0 capitals before (or after) buffering
3. In gvSIG, the buffer tool is in the Geoprocessing menu, which may need to be activated
4. Must specify buffer radius in the units of the CRS (degrees for WGS84)
5. Must ensure original attributes are preserved in the output (not just the geometry)
6. Exporting from an attribute selection vs. from a subquery are different workflows in gvSIG

## Verification Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists | 20 | Output shapefile must exist |
| Geometry is polygon | 35 | Confirms buffer was actually applied |
| Feature count ~150-250 | 25 | Approximately one per Admin-0 capital |
| NAME field present | 20 | Original point attributes preserved |
| **Total** | **100** | Pass threshold: 60/100 |

## Real Data Source

Natural Earth 1:110m Cultural Vectors (Populated Places)
URL: https://www.naturalearthdata.com/downloads/110m-cultural-vectors/
License: Public Domain

## Workflow Note (for task designers)

In gvSIG Desktop, geoprocessing buffer can be accessed via:
- Menu: Geoprocesses → Geoprocessing toolbox → Buffer
- OR: Layer menu when the layer is selected

The agent needs to:
1. Add populated places layer to the view
2. Filter/select only Admin-0 capital features
3. Run the buffer tool with radius=2, apply to selected features only
4. Export to the target path
