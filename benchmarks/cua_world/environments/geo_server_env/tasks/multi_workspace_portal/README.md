# Task: Multi-Workspace GIS Data Portal Setup

## Domain Context

GIS Leads at regional planning authorities set up complete, production-ready geospatial data portals that serve different thematic datasets through separate logical workspaces. A real multi-tenant GeoServer deployment separates infrastructure/transportation data from natural environment data, each in its own workspace with its own namespace, PostGIS datastore, layers, custom SLD styles, and workspace-specific WMS service metadata. A global layer group ties cross-workspace layers together into a single composite map for the public portal.

This task requires coordinating at least 8 distinct GeoServer operations across multiple UI sections: workspaces, stores, layers, styles, layer groups, and service configuration.

## Occupation

**Geographic Information Systems Technologists and Technicians** — architecting and deploying multi-workspace GeoServer portals for regional planning and municipal GIS data services.

---

## Goal

Build a complete dual-workspace GIS data portal:

### Workspace Setup
1. Create workspace `infrastructure` with namespace URI `http://infrastructure.authority.gov/gis`
2. Create workspace `environment` with namespace URI `http://environment.authority.gov/gis`

### Data Stores
3. Create a PostGIS datastore named `infra_data` in the `infrastructure` workspace, connecting to `gs-postgis:5432/gis` (user: `geoserver`, password: `geoserver123`)
4. Create a PostGIS datastore named `env_data` in the `environment` workspace, connecting to the same PostGIS database

### Layers
5. Publish `ne_populated_places` from `infra_data` as a layer named `settlements` in `infrastructure`
6. Publish `ne_rivers` from `env_data` as a layer named `waterways` in `environment`

### SLD Styles
7. Create an SLD style `settlement_marker` with a point symbolizer using a circle mark, orange fill (`#FFA500`), size 8
8. Create an SLD style `waterway_line` with a line symbolizer, blue stroke (`#0080FF`), width 2
9. Apply `settlement_marker` as default style for `infrastructure:settlements`
10. Apply `waterway_line` as default style for `environment:waterways`

### Layer Group
11. Create a global layer group named `regional_portal` combining both layers: `infrastructure:settlements` and `environment:waterways`

GeoServer admin: `http://localhost:8080/geoserver/web/` (admin / Admin123!)

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Workspace `infrastructure` exists | 5 |
| Workspace `environment` exists | 5 |
| Layer `settlements` in `infrastructure` | 20 |
| Layer `waterways` in `environment` | 20 |
| SLD `settlement_marker` with point/circle symbolizer | 10 |
| SLD `waterway_line` with line symbolizer | 10 |
| Styles applied as defaults to respective layers | 10 |
| Layer group `regional_portal` with both layers | 20 |
| **Total** | **100** |

**Pass threshold**: ≥65 points
**Mandatory**: Both layers (settlements + waterways) must exist in their respective workspaces

---

## Verification Strategy

- Workspaces: REST API `GET /rest/workspaces/{name}.json`
- Datastores: `GET /rest/workspaces/{ws}/datastores.json` — find PostGIS stores
- Layers: `GET /rest/workspaces/{ws}/featuretypes/{name}.json`
- Styles: `GET /rest/styles/{name}.json` or workspace-scoped, SLD content parsed for symbolizer type and color
- Default style assignment: `GET /rest/layers/{ws}:{layer}.json` → `defaultStyle.name`
- Layer group: `GET /rest/layergroups/regional_portal.json` → count layers and match names

---

## Notes

- This task requires creating 2 workspaces, 2 datastores, 2 layers, 2 styles, 1 layer group — a total of 7 configuration operations with dependencies
- Layer groups can reference layers from different workspaces
- Styles can be created globally or workspace-scoped; either is valid
- The PostGIS connection host is `gs-postgis` (Docker service name)
