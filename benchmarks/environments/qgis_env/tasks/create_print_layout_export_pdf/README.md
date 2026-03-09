# Task: Create Print Layout and Export PDF

## Overview
This task tests QGIS's cartographic map production workflow—creating a print layout with standard map elements (title, north arrow, scale bar, legend) and exporting to PDF. This is the culmination of a typical GIS project: producing a publication-ready map from spatial data.

## Domain Context
A GIS analyst has completed their spatial analysis and needs to produce a professional map for a client presentation or report. The standard cartographic requirements include a map frame showing the data, a descriptive title, a north arrow for orientation, a scale bar for distance reference, and a legend explaining the symbology. The final output must be a PDF suitable for printing or digital distribution.

## Target Data
- **Polygon layer**: `/home/ga/GIS_Data/sample_polygon.geojson` (2 zones)
- **Point layer**: `/home/ga/GIS_Data/sample_points.geojson` (3 monitoring points)
- **Expected output**: `/home/ga/GIS_Data/exports/sample_map.pdf`
- **Map title**: "San Francisco Bay Area - GIS Sample Data"
- **Layout name**: "Sample Data Map"

## Task Description
1. Open QGIS (already running)
2. Load polygon and point layers
3. Ensure both layers are visible on the map canvas
4. Create new print layout (Project > New Print Layout, name: "Sample Data Map")
5. Add map item (Add Item > Add Map, draw rectangle on layout)
6. Add title label: "San Francisco Bay Area - GIS Sample Data"
7. Add north arrow (Add Item > Add North Arrow or Add Picture)
8. Add scale bar (Add Item > Add Scale Bar)
9. Add legend (Add Item > Add Legend)
10. Export as PDF to `/home/ga/GIS_Data/exports/sample_map.pdf`

## Success Criteria
1. PDF file exists at expected path
2. PDF has valid format (%PDF header)
3. PDF has substantial content (>50KB, not blank)
4. PDF has at least 1 page
5. PDF size indicates full map layout (>100KB suggests title/legend/scale bar rendered)
6. File is newly created (not pre-existing)

## Verification Strategy
- **export_result.sh** checks PDF validity (header bytes), file size, page count
- **verifier.py** checks 6 criteria with weighted scoring (total 100 points)
- Baseline recording: initial PDF count
- Pass threshold: 55 points

## Edge Cases
- Agent may export layout from toolbar button instead of menu — same result
- Agent may forget individual elements — file size check differentiates partial vs full layout
- Layout name may differ — doesn't affect PDF output verification
- Agent may add extra elements — acceptable, only checks for minimum requirements
