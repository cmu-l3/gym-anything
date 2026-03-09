# Task: filter_south_america_major

## Overview

**Difficulty**: very_hard
**Occupation**: Environmental Scientists and Specialists (O*NET 19-2041.00)
**Industry**: Life, Physical, and Social Science
**Environment**: gvSIG Desktop 2.4.0

## Task Description

An environmental scientist needs to extract a subset of South American countries for a biodiversity corridor study. The criteria are:
1. Country must be in South America (`CONTINENT = 'South America'`)
2. Country must have population > 5 million (`POP_EST > 5000000`)

**Input**: `/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp`
**Output**: `/home/ga/gvsig_exports/south_america_major.shp` (selected features only)

## Why This Is Hard

1. Requires using gvSIG's attribute-based selection with compound AND conditions
2. In gvSIG, this requires either:
   - The "Selection by attributes" query tool with a compound expression
   - Or using the attribute table's filter/selection functionality
3. After selection, must use "Export selected features" (not "Export all") to produce a subset shapefile
4. If the agent exports the wrong features or exports all features, the verifier will fail

## Expected Qualifying Countries (Natural Earth 110m data)

Based on the Natural Earth 110m dataset, the following countries qualify:

| Country | Population (est.) |
|---------|------------------|
| Brazil | ~215,000,000 |
| Colombia | ~52,000,000 |
| Argentina | ~46,000,000 |
| Peru | ~33,000,000 |
| Venezuela | ~32,000,000 |
| Chile | ~19,000,000 |
| Ecuador | ~18,000,000 |
| Bolivia | ~12,000,000 |
| Paraguay | ~7,000,000 |

Total: ~9 countries (actual count depends on the NE 110m version in the environment)

## Verification Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists | 15 | Output shapefile must exist |
| Wrong-target GATE | — | Any non-SA country → score=0 |
| All features in SA | 20 | All CONTINENT = 'South America' |
| All POP_EST > 5M | 25 | Population filter correctly applied |
| Brazil present | 20 | Largest SA country must be included |
| Feature count [7, 13] | 20 | Correct number of qualifying countries |
| **Total** | **100** | Pass threshold: 60/100 |

## Real Data Source

Natural Earth 1:110m Cultural Vectors (Admin-0 Countries)
URL: https://www.naturalearthdata.com/downloads/110m-cultural-vectors/
License: Public Domain
