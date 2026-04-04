# Task: WFS Feature Service Setup with SQL View

## Domain Context

Spatial Data Engineers at natural resources and government agencies configure OGC Web Feature Services (WFS) to allow downstream GIS clients to query and download vector features programmatically. A common workflow is creating a **SQL View** (virtual table) inside an existing PostGIS datastore to expose a pre-filtered subset of data as a named feature type — for example, publishing only major world cities (population > 1 million) rather than all 7000+ populated places.

This task exercises three distinct GeoServer capabilities that professionals frequently combine: WFS global service configuration, SQL view creation within an existing datastore, and point symbology.

## Occupation

**Geographic Information Systems Technologists and Technicians** — configuring OGC feature services and parameterized data views for web GIS portals.

---

## Goal

Set up a WFS service and publish a filtered SQL view for major world cities:

1. **Configure WFS service** (global settings):
   - Enable WFS if not already enabled
   - Set WFS service title to `"Natural Earth WFS"`
   - Set WFS service abstract to a non-empty description mentioning WFS or Natural Earth
   - Set maximum number of features to `5000`

2. **Create an SQL View** named `major_cities` inside the `ne` workspace's existing PostGIS datastore:
   - SQL: `SELECT * FROM ne_populated_places WHERE pop_max > 1000000`
   - Geometry column: `wkb_geometry`, type: `Point`, SRID: `4326`
   - Publish the SQL view as a layer in the `ne` workspace

3. **Create an SLD style** named `city_marker` with:
   - A `Mark` graphic using the `circle` well-known name
   - Red fill color (`#FF0000`)
   - Size: `8` pixels
   - Apply `city_marker` as the **default style** for `ne:major_cities`

GeoServer admin: `http://localhost:8080/geoserver/web/` (admin / Admin123!)

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| WFS service enabled | 15 |
| WFS title contains "Natural Earth" or "WFS" | 10 |
| WFS max features >= 1000 | 10 |
| SQL view layer `major_cities` exists in `ne` workspace | 25 |
| Layer is Point geometry type | 10 |
| SLD `city_marker` exists with circle mark | 15 |
| `city_marker` applied as default style to `ne:major_cities` | 15 |
| **Total** | **100** |

**Pass threshold**: ≥60 points
**Mandatory**: `major_cities` layer must exist in the `ne` workspace

---

## Verification Strategy

- WFS: `GET /rest/services/wfs/settings.json` → check `enabled`, `title`, `maxFeatures`
- SQL view layer: `GET /rest/workspaces/ne/featuretypes/major_cities.json` — presence + geometry type
- SLD: `GET /rest/styles/city_marker.sld` or workspace-scoped — parse for `Mark/WellKnownName=circle` and `#FF0000`
- Default style: `GET /rest/layers/ne:major_cities.json` → `defaultStyle.name`

---

## Notes

- The SQL view creation in GeoServer GUI: go to **Layers > Add new layer**, select the `ne` PostGIS datastore, then click **"Configure new SQL view"** rather than selecting an existing table
- The geometry column in ne_populated_places is `wkb_geometry`
- SQL views require specifying the geometry type and SRID in the GeoServer form
- The ne workspace and its PostGIS datastore already exist from the environment setup
