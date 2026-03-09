# Task: GeoWebCache Tile Cache Seeding

## Domain Context

GIS Platform Architects preparing geospatial portals for high-traffic public access must configure the tile caching layer (GeoWebCache, integrated in GeoServer as "Tile Caching") to pre-generate tiles at lower zoom levels. This eliminates rendering latency for common overview maps and reduces server load. The workflow involves configuring which gridsets (coordinate systems and zoom levels) a layer is cached in, setting image formats, and triggering a tile seeding operation that generates pre-built PNG tiles for a defined bounding box and zoom range.

## Occupation

**Geographic Information Systems Technologists and Technicians** — configuring tile map services (TMS/WMTS) and managing GeoWebCache for production geospatial portals.

---

## Goal

Configure tile caching for the `ne:ne_countries` layer and initiate tile seeding:

1. Navigate to the **Tile Caching** section in GeoServer and find the tile layer for `ne:ne_countries`
2. Configure the tile layer settings:
   - Ensure `EPSG:4326` gridset is present
   - Add `EPSG:900913` (Web Mercator) gridset with zoom levels 0–8
   - Set the tile image format to `image/png`
   - Set the metatiling factor to at least 4×4
3. **Seed tiles** for the `ne:ne_countries` layer:
   - Gridset: `EPSG:4326`
   - Zoom levels: 0 to 3 (minimum)
   - Format: `image/png`
   - Bounding box: full world extent (left: -180, bottom: -90, right: 180, top: 90)
4. Confirm seeding has been triggered (check GeoWebCache seed status)

GeoServer admin: `http://localhost:8080/geoserver/web/` (admin / Admin123!)
GeoWebCache is accessible from the main menu under "Tile Caching" or directly at `/geoserver/gwc/`.

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| GWC tile layer exists for ne:ne_countries | 20 |
| EPSG:4326 gridset configured | 20 |
| EPSG:900913 gridset configured | 15 |
| Tile image format includes image/png | 15 |
| Tile seeding was triggered (seed status found) | 30 |
| **Total** | **100** |

**Pass threshold**: ≥60 points
**Mandatory**: GWC tile layer must exist

---

## Verification Strategy

- GWC layer: `GET /geoserver/gwc/rest/layers/ne:ne_countries.json` — presence and configuration
- Gridsets: parse `gridSubsets` in the GWC layer JSON
- Tile formats: parse `mimeFormats` in the GWC layer JSON
- Seeding: `GET /geoserver/gwc/rest/seed/ne:ne_countries.json` — check for active or completed seed tasks

---

## Notes

- The GWC REST API uses a different base path: `/geoserver/gwc/rest/` NOT `/geoserver/rest/`
- EPSG:900913 is the legacy EPSG code for Web Mercator (same as EPSG:3857)
- Seeding can take a few minutes even for low zoom levels; the verifier checks that a seed was triggered, not that it fully completed
- GWC configuration in GeoServer admin: left menu "Tile Caching" → "Tile Layers" → click on layer name
- Seed/Truncate operations: "Tile Caching" → "Tile Layers" → seed icon next to layer
