# Task: reproject_rivers_utm33n

## Overview

**Difficulty**: very_hard
**Occupation**: Water/Wastewater Engineers (O*NET 17-2051.02)
**Industry**: Architecture and Engineering
**Environment**: gvSIG Desktop 2.4.0

## Task Description

A water resources engineer needs to reproject the global rivers dataset from WGS84 geographic coordinates (EPSG:4326) to UTM Zone 33N (EPSG:32633) for a Central European watershed analysis. The reprojected layer must be exported as a new shapefile.

**Input**: `/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp` (WGS84 / EPSG:4326)
**Output**: `/home/ga/gvsig_exports/rivers_utm33n.shp` (UTM Zone 33N / EPSG:32633)

## Why This Is Hard

1. Requires understanding the difference between setting a layer's CRS (display only) vs. actually reprojecting/transforming coordinates
2. In gvSIG, reprojection requires using the "Export to shapefile" or "Save as..." workflow with CRS transformation — not just changing the layer's CRS property
3. The agent must navigate gvSIG's geoprocessing tools or Layer Export dialog, find the CRS transformation option, and specify the correct EPSG code
4. No UI navigation hints are given — the agent must discover the workflow independently

## Verification Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists | 20 | `/home/ga/gvsig_exports/rivers_utm33n.shp` must exist |
| CRS = EPSG:32633 | 40 | Output .prj must define UTM Zone 33N |
| Feature count matches | 25 | Same number of river features as source |
| Coordinates are metric | 15 | X values must be in meter range, not degrees |
| **Total** | **100** | Pass threshold: 60/100 |

## Real Data Source

Natural Earth 1:110m Rivers and Lake Centerlines
URL: https://www.naturalearthdata.com/downloads/110m-physical-vectors/
License: Public Domain

## Workflow Hint (for task designers only, not shown to agent)

In gvSIG Desktop, the correct workflow is:
1. Load the rivers layer (Layer → Add Layer → Add Vector Layer)
2. Right-click the layer → Export → "Export to shapefile" (or use Layer menu → Export)
3. In the export dialog, change the "CRS" / "Coordinate Reference System" to EPSG:32633
4. Set output path to `/home/ga/gvsig_exports/rivers_utm33n.shp`
5. Click OK/Export
