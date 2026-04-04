# Task: field_calc_gdp_percapita

## Overview

**Difficulty**: very_hard
**Occupation**: GIS Technologists and Technicians (O*NET 15-1299.02)
**Industry**: Computer and Mathematical
**Environment**: gvSIG Desktop 2.4.0

## Task Description

A GIS analyst for an economic policy team needs to enrich the countries shapefile with GDP per capita values. Using gvSIG's field calculator, add a new computed field `GDP_PCAP` to the layer and export the enriched dataset.

**Formula**: `GDP_PCAP = (GDP_MD_EST × 1,000,000) ÷ POP_EST`
- `GDP_MD_EST` is GDP in millions of USD
- `POP_EST` is total population
- Result is GDP per capita in USD per person

**Input**: `/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp`
**Output**: `/home/ga/gvsig_exports/countries_gdp_percapita.shp`

## Why This Is Hard

1. Requires enabling layer editing mode before the field calculator is accessible
2. Must know how to add a new field of the correct data type (Double/Float)
3. Must write a correct field calculator expression referencing existing fields
4. In gvSIG, the field calculator syntax uses `[FIELD_NAME]` or direct field references
5. After calculation, must stop editing (save edits) before exporting
6. Must export to a NEW shapefile, not overwrite the original

## Expected Output Values

| Country | Approximate GDP_PCAP (USD) |
|---------|---------------------------|
| United States | ~55,000 – 70,000 |
| Germany | ~42,000 – 55,000 |
| China | ~8,000 – 15,000 |
| India | ~1,500 – 3,500 |
| Nigeria | ~2,000 – 4,000 |

## Verification Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists | 15 | Output shapefile must exist |
| GDP_PCAP field present | 30 | New field must appear in the output |
| USA value in [35k, 90k] | 25 | Correctness of formula for a high-income country |
| China value in [4k, 22k] | 20 | Correctness of formula for a middle-income country |
| Feature count ~177 | 10 | All countries preserved in export |
| **Total** | **100** | Pass threshold: 60/100 |

## Real Data Source

Natural Earth 1:110m Cultural Vectors (Admin-0 Countries)
URL: https://www.naturalearthdata.com/downloads/110m-cultural-vectors/
License: Public Domain
