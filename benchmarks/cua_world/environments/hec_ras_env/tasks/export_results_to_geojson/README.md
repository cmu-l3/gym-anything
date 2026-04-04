# Export Results to GeoJSON (`export_results_to_geojson@1`)

## Overview
This task evaluates the agent's ability to extract spatial geometry and simulation results from a HEC-RAS HDF5 file and merge them into a standard geospatial format (GeoJSON). The agent must programmatically link cross-section cut lines (spatial data) with peak hydraulic results (attribute data) to support web-mapping applications.

## Rationale
**Why this task is valuable:**
- **Interoperability:** Tests the ability to bridge engineering software (HEC-RAS) with modern web/GIS standards (GeoJSON).
- **Data Wrangling:** Requires merging data from two distinct HDF5 groups (Geometry and Unsteady Results).
- **Spatial Data Handling:** Evaluates proficiency in handling coordinate arrays and structuring spatial features.
- **Automation:** Simulates a real-world pipeline where model results are automatically published to a dashboard.

**Real-world Context:** A Web-GIS Developer at a flood control agency is building a "Real-time Flood Dashboard." They need to visualize the model results on a web map. Since HEC-RAS doesn't natively export "Cross Sections with Attributes" to GeoJSON, they need a Python script to convert the internal HDF5 data into a web-friendly format containing the cut lines and peak water levels.

## Task Description

**Goal:** Create a Python script that reads the Muncie HEC-RAS HDF5 file and generates a GeoJSON file containing all cross-section cut lines, with `RiverStation`, `PeakWSE`, and `PeakFlow` included as properties for each feature.

**Starting State:**
- A terminal is open in the Muncie project directory (`/home/ga/Documents/hec_ras_projects/Muncie`).
- The simulation results HDF file (`Muncie.p04.tmp.hdf` or `Muncie.p04.hdf`) is available.
- Python 3 with `h5py`, `numpy`, and `json` is installed.

**Expected Actions:**
1. **Analyze the HDF5 Structure:** Locate:
   - The Cross Section Cut Lines (Polyline coordinates) in the Geometry group.
   - The Cross Section Attributes (River Stations) in the Geometry group.
   - The Peak Water Surface Elevation and Peak Flow results in the Results/Unsteady/Output/Output Blocks... path.
2. **Develop the Conversion Script:** Write a Python script (e.g., `export_geojson.py`) that:
   - Iterates through all cross-sections.
   - Extracts the X,Y coordinates for the cut line.
   - Extracts the corresponding River Station, Peak WSE, and Peak Flow.
   - Constructs a GeoJSON `Feature` for each cross-section.
   - Compiles these into a `FeatureCollection`.
3. **Execute and Validate:** Run the script to generate `muncie_results.geojson`.
   - *Note:* Keep the coordinates in the original projection (State Plane/Cartesian) as found in the file; do not attempt to reproject to Lat/Lon.

**Final State:**
- A valid GeoJSON file exists at `/home/ga/Documents/hec_ras_results/muncie_results.geojson`.
- The file contains a `FeatureCollection` with one `LineString` feature per cross-section.
- Each feature has correct geometry and the required properties.

## Verification Strategy

### Primary Verification: GeoJSON Structure and Content
The verifier parses the output file (`muncie_results.geojson`) and checks:
1. **JSON Validity:** File is valid JSON.
2. **GeoJSON Spec:** Root object is a `FeatureCollection` with a `features` list.
3. **Feature Count:** Number of features matches the number of cross-sections in the HDF ground truth.
4. **Geometry Match:** The coordinates of the first and last cross-sections match the HDF ground truth (within tolerance).
5. **Attribute Accuracy:** The `peak_wse` and `peak_flow` properties for a sample of cross-sections match the computed maximums from the HDF file.

### Secondary Verification: Script Existence
- Checks that a Python script exists and uses `h5py` and `json` libraries.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Valid JSON Output | 10 | File exists and parses as JSON |
| GeoJSON Structure | 15 | Correct FeatureCollection/Feature/LineString hierarchy |
| Feature Count | 15 | Correct number of cross-sections included |
| Geometry Accuracy | 20 | Coordinates match HDF source data |
| Property Schema | 10 | `station`, `peak_wse`, `peak_flow` keys present |
| Data Accuracy | 30 | WSE and Flow values match HDF results |
| **Total** | **100** | |

**Pass Threshold:** 70 points