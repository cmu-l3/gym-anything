# Apply CQL Filter to Restrict Layer Features (`apply_cql_filter_layer@1`)

## Overview
This task requires the agent to apply a CQL (Common Query Language) filter on an existing published GeoServer layer to restrict which features are served through OGC services. The agent must configure the `ne_countries` feature type so that only South American countries are returned.

## Rationale
**Why this task is valuable:**
- Tests understanding of GeoServer's CQL filter mechanism for feature restriction.
- Requires knowledge of feature type configuration (not just layer publishing).
- Involves interacting with existing data and modifying its serving behavior.
- Simulates a common real-world requirement: serving a subset of a dataset without duplicating the data in the database.

**Real-world Context:** A cartographer needs to create a map service specific to South American operations. Rather than creating a new database table, they configure the WMS/WFS layer to filter the global dataset on-the-fly.

## Task Description

**Goal:** Apply a CQL filter to the `ne_countries` layer so that GeoServer only serves South American country features.

**Starting State:** 
- GeoServer is running.
- `ne:ne_countries` layer is published and shows all ~177 world countries.
- Firefox is open to the GeoServer login page.

**Expected Actions:**
1. Login to GeoServer (admin / Admin123!).
2. Locate the `ne_countries` layer configuration.
3. Configure the **CQL Filter** (often found in the Data settings of the Feature Type) to restrict features: `continent = 'South America'`.
4. Save the layer.

**Final State:** 
- WFS requests to `ne:ne_countries` return ~13 features (Brazil, Argentina, etc.).
- Non-South American countries are not returned.

## Verification Strategy

### Primary Verification: WFS Output Validation
The verifier issues a real WFS GetFeature request to the layer and checks:
1. Are features returned?
2. Is the count within the expected range (10-15)?
3. Do ALL returned features have `continent == 'South America'`?

### Secondary Verification: Configuration Check
The verifier checks the GeoServer REST API to confirm the `cqlFilter` property is set on the FeatureType.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **Features Filtered** | 50 | WFS returns only South American countries (no leaking of other continents). |
| **Feature Count** | 20 | WFS returns the correct number of features (10-15). |
| **Config Correct** | 20 | REST API confirms `cqlFilter` is set on the resource. |
| **State Change** | 10 | Feature count is significantly lower than the initial count (anti-gaming). |
| **Total** | **100** | |

Pass Threshold: **70** points.