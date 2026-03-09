# Task: Spatial Feature Enhancement

## Occupation
Remote Sensing Technician — processing imagery for urban planning.

## Industry
Urban Planning / Infrastructure Mapping

## Scenario
A remote sensing technician must enhance Sentinel-2 true color imagery to improve discrimination of built structures and infrastructure. The agent must discover SNAP's spatial filtering capabilities (e.g., Raster > Filtered Band), choose an appropriate filter (edge detection, high-pass, etc.), and produce enhanced output while preserving original bands.

## Data
- **Source**: Sentinel-2A TCI (True Color Image) from AWS COGs
- **File**: sentinel2_tci.tif (3-band RGB)

## What Makes This Very Hard
- Agent must discover SNAP's filtering tools (not told which menu or dialog)
- Agent must choose appropriate filter type for edge/structure enhancement
- Agent must preserve original bands alongside filtered output
- No filter parameters, kernel sizes, or settings provided
- No UI path hints — agent discovers all navigation independently

## Verification (6 criteria, 100 pts, pass at 70)
1. Product saved in DIMAP format (15 pts)
2. Filtered band(s) exist beyond originals (25 pts)
3. Filter type identifiable by band name (15 pts)
4. Original bands preserved alongside filter output (20 pts)
5. GeoTIFF exported (15 pts)
6. GeoTIFF has non-trivial size (10 pts)
