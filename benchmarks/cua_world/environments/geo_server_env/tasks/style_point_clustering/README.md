# Create Point Clustering Style (`style_point_clustering@1`)

## Overview
This task requires the agent to create a complex SLD (Styled Layer Descriptor) that applies a **Rendering Transformation** to dynamically cluster point features. The agent must configure the `ne_populated_places` layer to use the `gs:PointStacker` transformation function, grouping overlapping cities into single cluster markers based on proximity, while displaying isolated cities as distinct symbols.

## Rationale
**Why this task is valuable:**
- Tests mastery of **SLD Rendering Transformations**, a powerful feature for server-side data processing.
- Tests ability to write conditional styling rules based on transformation outputs (e.g., `count` attribute).
- Addresses a common GIS visualization challenge: reducing map clutter (decluttering) without preprocessing data.
- Verifies understanding of the distinction between raw data styling and transformed data styling.

**Real-world Context:** A web mapping developer is building a dashboard for a global logistics firm. The "Populated Places" layer looks like a chaotic blob of overlapping points at global zoom levels. The developer needs to implement server-side clustering so that users see a single "Cluster" icon with a number (e.g., "5") in dense areas, and individual city markers in sparse areas, ensuring a clean and readable map at all scales.

## Task Description

**Goal:** Create a new style named `clustered_places` that uses the `gs:PointStacker` rendering transformation to cluster `ne_populated_places` features, and set it as the default style for that layer.

**Starting State:**
- GeoServer is running at `http://localhost:8080/geoserver`.
- The layer `ne:ne_populated_places` (Natural Earth Populated Places) is published and currently uses a simple point style.
- Firefox is open to the GeoServer web admin interface.
- Admin credentials: `admin` / `Admin123!`.

**Expected Actions:**
1.  **Create a new Style** named `clustered_places` in the `ne` workspace (or global).
2.  **Configure the Transformation**:
    - Use the `gs:PointStacker` rendering transformation function.
    - Set the `cellSize` parameter to `60` (pixels).
    - Ensure the transformation operates on the `data` parameter.
3.  **Define Styling Rules**:
    - **Rule 1 (Clusters)**: Applied when the cluster contains **more than 1** point (attribute `count > 1`).
        - Symbol: A **Circle** mark.
        - Fill Color: **Blue** (`#0000FF`).
        - Size: **22** pixels.
        - Label: The value of the `count` attribute (centered on the circle, color White).
    - **Rule 2 (Single Points)**: Applied when the cluster contains exactly **1** point (attribute `count = 1` or just `else`).
        - Symbol: A **Star** mark.
        - Fill Color: **Red** (`#FF0000`).
        - Size: **12** pixels.
4.  **Apply the Style**:
    - Update the `ne:ne_populated_places` layer configuration to use `clustered_places` as its **Default Style**.
    - Save the layer configuration.

**Final State:**
- The `clustered_places` style exists and contains the `gs:PointStacker` transformation.
- The `ne:ne_populated_places` layer is configured to use this style by default.
- A WMS request to the layer renders simplified clusters in dense areas (Blue circles with numbers) and stars in sparse areas.

## Verification Strategy

### Primary Verification: REST API Style Analysis
The verifier will retrieve the style body via the REST API and parse the SLD XML to validate:
- **Transformation**: Presence of `<ogc:Function name="gs:PointStacker">`.
- **Parameters**: `cellSize` is set to `60`.
- **Rules**:
    - A rule exists filtering for `count` > 1 (or equivalent) with a Blue Circle symbolizer.
    - A rule exists for single points with a Red Star symbolizer.
    - A TextSymbolizer exists printing the `count` property.

### Secondary Verification: Layer Configuration Check
Query the layer definition via REST API (`/rest/layers/ne:ne_populated_places.json`) to confirm:
- `defaultStyle/name` is equal to `clustered_places` (or `ne:clustered_places`).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Style Created | 15 | Style `clustered_places` exists |
| Style Assigned | 15 | `clustered_places` is default for layer `ne_populated_places` |
| Transformation Valid | 30 | SLD contains `gs:PointStacker` with `cellSize` 60 |
| Cluster Styling | 20 | Rule for `count > 1` has Blue Circle and Text Label |
| Single Point Styling | 20 | Rule for `count = 1` has Red Star |
| **Total** | **100** | |