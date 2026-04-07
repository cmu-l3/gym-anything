# fix_geospatial_etl_pipeline

**Occupation**: Geospatial Information Scientist (15-1299.02)
**Industry**: Urban Planning
**Difficulty**: very_hard

## Description

A city planning department's geospatial data processing pipeline has 5 critical bugs
causing incorrect spatial analysis results. Map overlays are misaligned, area
calculations are wrong, and exported GeoJSON data fails validation against RFC 7946.

The agent must locate and fix all bugs across 5 Python source files in the pipeline:

1. **coordinate_transform.py** -- Swapped latitude/longitude coordinate order
2. **spatial_operations.py** -- Buffer distance applied in degrees instead of meters
3. **area_calculator.py** -- Area computed on geographic (degree) coordinates instead of projected
4. **topology_validator.py** -- Exact floating-point equality instead of epsilon comparison
5. **geojson_exporter.py** -- Missing FeatureCollection wrapper in GeoJSON output

## Scoring

Each fix is worth 20 points (total 100). Pass threshold is 60 (3 of 5 bugs fixed).
