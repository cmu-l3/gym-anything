# Public Health Zone Mapping — High-Risk Census Tract Analysis

**Environment**: qgis_env
**Difficulty**: very_hard
**Occupation**: Public Health GIS Analyst / Epidemiologist
**Industry**: Public Health / Government / Environmental Health

## Scenario

A city public health department has commissioned an analysis to identify census tracts that qualify for the "High-Risk Health Zone" designation. These zones receive priority funding for community health centers, air quality monitoring, and mobile medical units.

The department has provided:
- A GeoJSON file with 20 census tract polygons, each containing environmental and healthcare access metrics
- A designation criteria document specifying the exact thresholds required for classification

The analyst must read the criteria document, load the census tract data in QGIS, apply the appropriate attribute filters, and export only the qualifying tracts to a new GeoJSON file for use in the department's mapping portal.

## Task Difficulty Justification (very_hard)

The task description does NOT specify:
- Which census tracts qualify
- The exact filter thresholds (agent must read the criteria document)
- The QGIS workflow steps required
- Which attribute fields to filter on

The agent must independently:
1. Read the designation criteria document to discover the thresholds
2. Load the census tract GeoJSON in QGIS
3. Apply attribute-based selection using the discovered criteria
4. Export only the selected features to the output GeoJSON

## Data Description

- **Input**: `/home/ga/GIS_Data/census_tracts.geojson` — 20 polygon features
  - Attributes: `tract_id`, `tract_name`, `aqi` (Air Quality Index), `pop_density` (persons/km²), `dist_hospital_km`
- **Criteria**: `/home/ga/GIS_Data/designation_criteria.txt` — threshold document (agent must read)
- **Output**: `/home/ga/GIS_Data/exports/high_risk_zones.geojson` — filtered features only

## High-Risk Designation Criteria (ground truth)
AQI > 75 AND population density > 3500 AND distance to nearest hospital > 7.5 km
Qualifying tracts: CT-003, CT-007, CT-011, CT-014, CT-016, CT-018, CT-020 (7 of 20)

## Scoring

| Criterion | Points |
|-----------|--------|
| Output file exists and is valid GeoJSON FeatureCollection | 10 |
| All 7 qualifying tracts present in output (proportional: ~5.7 pts/tract) | 40 |
| All 13 non-qualifying tracts absent from output (proportional: ~2.3 pts/tract) | 30 |
| Exact match: exactly 7 correct features, no extras | 20 |
| **Total** | **100** |
| **Pass threshold** | **65** |

### Strategy Enumeration

| Strategy | Score | Passes? |
|----------|-------|---------|
| Do nothing (no output file) | 0 | No |
| Export all 20 features | 10 + 40 + 0 + 0 = 50 | No |
| Export 7 correct only | 10 + 40 + 30 + 20 = 100 | Yes |
| Export 5 correct, 0 wrong | 10 + 29 + 30 + 0 = 69 | Yes |
| Export 4 correct, 0 wrong | 10 + 23 + 30 + 0 = 63 | Borderline No |

## Feature Matrix

| Feature | Used |
|---------|------|
| GeoJSON data loading | ✓ |
| Attribute-based feature selection | ✓ |
| Multi-condition filter (AND logic) | ✓ |
| Feature export to GeoJSON | ✓ |
| Document-driven criteria discovery | ✓ |
| Public health domain knowledge | ✓ |
