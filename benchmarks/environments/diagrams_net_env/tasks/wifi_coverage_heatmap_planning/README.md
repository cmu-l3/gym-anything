# WiFi Coverage Heatmap Planning (`wifi_coverage_heatmap_planning@1`)

## Overview
This task evaluates the agent's ability to use Diagrams.net (draw.io) for spatial facility planning. The agent must import a floor plan image, organize content using multiple layers (a critical best practice for complex diagrams), and visualize wireless signal coverage using semi-transparent shapes. This tests image manipulation, layer management, and custom styling capabilities.

## Rationale
**Why this task is valuable:**
- **Layer Management**: Tests the ability to use the Layers panel to organize background vs. foreground data (locking the floor plan so it doesn't move).
- **Styling & Opacity**: Requires adjusting shape properties (fill color, opacity/alpha) to create "heatmap" effects that don't obscure the underlying map.
- **Image Handling**: Tests importing and resizing external raster images within the vector tool.
- **Spatial Reasoning**: Requires placing objects based on visual landmarks in the floor plan rather than grid coordinates.

**Real-world Context:** A Network Engineer is designing a WiFi upgrade for a small office. To get budget approval, they need to visualize the estimated signal coverage over the actual office layout, showing stakeholders where "dead zones" might exist. They use draw.io to overlay AP locations and coverage bubbles on the building blueprints.

## Task Description

**Goal:** Create a WiFi coverage map for the office by importing a floor plan, placing Wireless Access Points (WAPs) on a dedicated layer, and drawing semi-transparent coverage zones on a top layer.

**Starting State:**
- Diagrams.net is open with a blank diagram.
- `~/Desktop/office_floorplan.png`: A PNG image of the office layout.
- `~/Desktop/wifi_project_specs.txt`: Instructions detailing the 3 required AP locations, coverage radii, and color coding (2.4GHz vs 5GHz).

**Expected Actions:**
1. Open the Layers dialog (View > Layers or Ctrl+Shift+L).
2. Rename the background layer to "Floor Plan" and import `~/Desktop/office_floorplan.png` into it.
3. **Lock** the "Floor Plan" layer so the image cannot be accidentally moved.
4. Create a new layer named "Hardware".
5. On the "Hardware" layer, place 3 "Wireless Access Point" icons (from the Network or standard shape libraries) at the locations specified in the text file (Lobby, Conference Room, Bullpen).
6. Create a new layer named "Coverage".
7. On the "Coverage" layer, draw circles representing the signal range for each AP as specified (e.g., Green/50% opacity for 5GHz, Blue/30% opacity for 2.4GHz).
8. Export the result as a PNG image to `~/Diagrams/exports/wifi_coverage_map.png`.

**Final State:**
- A `.drawio` file with 3 distinct layers.
- Background image locked on bottom layer.
- Hardware icons on middle layer.
- Semi-transparent circles on top layer.
- Exported PNG showing the composite view.

## Verification Strategy

### Primary Verification: XML Structure Analysis
The verifier parses the saved `.drawio` file (XML format) to check:
1. **Layer Count**: Verifies existence of 3 `<mxCell parent="0">` siblings (layers).
2. **Layer Names**: Checks `value` attribute for "Floor Plan", "Hardware", "Coverage".
3. **Image Presence**: Checks for `<mxCell>` with `style="...image..."` inside the Floor Plan layer.
4. **Locking**: Checks if the Floor Plan layer has `locked="1"`.
5. **Transparency**: Checks the style of coverage circles for `opacity` (or `fillColor` with alpha) and verifies it is < 100%.
6. **Shape Count**: Confirms 3 AP icons and appropriate number of coverage circles.

### Secondary Verification: Export Check
- Verifies `~/Diagrams/exports/wifi_coverage_map.png` exists and is a valid image file.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File saved & modified | 10 | Basic file operations |
| **Layer Management** | **30** | 3 layers created and correctly named |
| Floor Plan Imported | 15 | Image object found in XML |
| Floor Plan Locked | 10 | Layer locked attribute set |
| AP Icons Placed | 15 | 3 Wireless Access Point shapes found |
| **Visual Styling** | **20** | Coverage circles have opacity < 100% (semi-transparent) |
| PNG Export | 10 | Valid output image created |
| **Total** | **100** | |

**Pass Threshold**: 70 points (Must have layers and transparency correct).