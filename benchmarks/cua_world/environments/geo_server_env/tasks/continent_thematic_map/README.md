# Task: Continent Thematic Map

## Domain Context

Geographic Information Systems (GIS) Analysts at regional development organizations and mapping agencies regularly create thematic choropleth maps to visualize country-level attributes — such as population, GDP, or administrative classification — in published web mapping services. A core professional skill is building Styled Layer Descriptor (SLD) XML with classified rendering rules that apply distinct symbology based on attribute values, then wiring those styles to published layers.

This task represents a realistic workflow for a GIS Analyst who needs to stand up a new "regional atlas" workspace from scratch, publish the world countries layer into it from the existing PostGIS backend, and produce a continent-classification choropleth style using OGC filter expressions.

## Occupation

**Geographic Information Systems Technologists and Technicians** — publishing classified thematic maps as WMS services for internal and public-facing mapping portals.

---

## Goal

Create a fully functional thematic map service for world countries classified by continent:

1. Create a new GeoServer workspace named `regional_atlas` with namespace URI `http://atlas.regional.example.org`
2. Create a PostGIS datastore named `world_geodata` inside `regional_atlas` connecting to the existing PostGIS database (`gs-postgis:5432/gis`, credentials `geoserver`/`geoserver123`)
3. Publish the `ne_countries` PostGIS table as a layer named `countries` in the `regional_atlas` workspace
4. Create an SLD style named `continent_colors` (in the `regional_atlas` workspace or globally) that classifies countries by their `continent` attribute with at least **7 rules** — one rule per continent (Africa, Antarctica, Asia, Europe, North America, Oceania, South America). Each rule must:
   - Use an `<ogc:PropertyIsEqualTo>` filter on the `continent` field
   - Use a `<PolygonSymbolizer>` with a distinct fill color per continent
   - Have at least 6 distinct fill colors across the 7 rules
5. Apply `continent_colors` as the **default style** for the `regional_atlas:countries` layer

GeoServer admin URL: `http://localhost:8080/geoserver/web/`
Login: `admin` / `Admin123!`

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Workspace `regional_atlas` exists | 10 |
| PostGIS datastore in `regional_atlas` | 15 |
| Layer `countries` published in `regional_atlas` | 20 |
| SLD `continent_colors` exists | 10 |
| SLD has ≥7 rules | 15 |
| SLD uses `continent` property in ogc:Filter expressions | 10 |
| SLD has ≥6 distinct hex fill colors | 10 |
| `continent_colors` is the default style for `regional_atlas:countries` | 10 |
| **Total** | **100** |

**Pass threshold**: ≥65 points
**Mandatory**: Layer `countries` must exist in `regional_atlas` workspace

---

## Verification Strategy

- Workspace presence: REST API `GET /rest/workspaces/regional_atlas.json`
- Datastore: `GET /rest/workspaces/regional_atlas/datastores.json` — must contain a PostGIS type store
- Layer: `GET /rest/workspaces/regional_atlas/datastores/{store}/featuretypes/countries.json`
- Style: `GET /rest/workspaces/regional_atlas/styles/continent_colors.sld` OR `GET /rest/styles/continent_colors.sld`
- SLD rule count: parse XML `<Rule>` elements
- Filter property: search SLD XML for `<ogc:PropertyName>continent</ogc:PropertyName>`
- Color count: extract all `<CssParameter name="fill">#......` hex values, count distinct
- Default style: `GET /rest/layers/regional_atlas:countries.json` → check `defaultStyle.name`

---

## Edge Cases

- The agent may create the style in the global scope rather than the workspace scope — both are valid, export script searches both
- The agent may name the layer differently — export script accepts `countries`, `ne_countries`, or any name containing the substring "countr"
- Continent values in ne_countries: Africa, Antarctica, Asia, Europe, North America, Oceania, South America (7 values)
- The PostGIS connection host inside the GeoServer container is `gs-postgis` (the Docker service name), NOT `localhost`
- Default style assignment requires the layer to be published first
