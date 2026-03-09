# GIMP Edge Detection Task (`edge_detect@1`)

## Overview

This task tests an agent's ability to use GIMP's edge detection filter to identify and highlight boundaries in an image. The agent must navigate to the edge detection filter, apply it to transform the image into a high-contrast representation where edges are prominently visible against a dark background. This represents a fundamental image analysis operation commonly used in artistic effects, technical illustration, and computer vision preprocessing.

## Rationale

**Why this task is valuable:**
- **Filter System Introduction:** Introduces GIMP's extensive filter menu in a straightforward, single-operation manner
- **Visual Analysis Concepts:** Tests understanding of what constitutes "edges" and boundaries in visual content
- **Image Processing Foundation:** Introduces fundamental computer vision concepts in an accessible way
- **Distinctive Output:** Produces clearly verifiable results with characteristic high-contrast edge patterns
- **Practical Applications:** Used in graphic design (sketch effects), technical illustration (boundary emphasis), and preprocessing for further operations
- **Real-world Relevance:** Common in artistic photography, comic book effects, architectural rendering, and image analysis workflows

**Skill Progression:** This task serves as an ideal introduction to GIMP's filter system, providing binary success criteria and building confidence before progressing to multi-parameter filter operations.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested filter menu structure (`Filters → Edge-Detect → Edge...`)
- **Dialog Management:** Interact with the Edge Detection dialog box and its controls
- **Parameter Assessment:** Understand preview window showing filter effect
- **Algorithm Selection:** Choose from available edge detection algorithms (Sobel, Prewitt, etc.)
- **Change Confirmation:** Apply the filter using OK/Apply button
- **Visual Comparison:** Compare before/after states to confirm successful application

### B. GIMP Knowledge
- **Filter Menu Organization:** Understand GIMP's hierarchical filter categorization system
- **Edge Detection Concepts:** Comprehend what edge detection does (highlights boundaries, suppresses uniform areas)
- **Algorithm Options:** Know that different algorithms (Sobel, Prewitt, Gradient, Roberts) produce similar results
- **Filter Parameters:** Understand Amount/Threshold controls affect edge sensitivity
- **Preview System:** Use preview to assess changes before committing
- **Immediate Application:** Recognize that filters with dialogs require OK confirmation

### C. Task-Specific Skills
- **Edge Recognition:** Understand that edges are areas of rapid intensity/color change
- **Visual Feature Identification:** Recognize object boundaries, texture transitions, and contrast changes
- **Algorithm Appropriateness:** Know that default settings (Sobel algorithm) work well for most images
- **Quality Assessment:** Evaluate whether edges are adequately detected and highlighted
- **Effect Validation:** Confirm the characteristic "sketch-like" appearance of edge-detected images

## Task Steps

### 1. Initial Image Examination
- Examine the image that opens automatically in GIMP (typically a photograph with clear subjects)
- Identify areas with strong edges: object boundaries, architectural lines, contrast changes
- Note distinctive features that should become prominent after edge detection

### 2. Navigate to Filter Menu
- Click on "Filters" in the menu bar to open the filter menu
- Observe the organized categories of filter operations

### 3. Access Edge Detection Submenu
- Hover over or click "Edge-Detect" to reveal edge detection options
- Locate the "Edge..." option (the primary edge detection filter)

### 4. Open Edge Detection Dialog
- Click on "Edge..." to open the Edge Detection dialog
- Wait for the dialog to appear with preview and parameter controls
- Observe the preview showing the edge-detected version

### 5. Review Parameters (Optional)
- Note the default algorithm selection (usually "Sobel")
- Observe the default Amount/Threshold setting (typically 2.0-4.0)
- The defaults work well for most images, so changes are optional
- Preview updates automatically as parameters change

### 6. Apply Edge Detection
- Click "OK" button to apply the edge detection filter
- Wait for GIMP to process the image (usually 1-3 seconds)
- Observe the transformation: edges become bright lines on dark background

### 7. Verify Transformation
- Examine the result: image should show prominent white/light edges
- Background and uniform areas should be dark or black
- Object boundaries should be clearly delineated
- The image should have a characteristic "sketch" or "outline" appearance

### 8. Automatic Export
- The post-task hook will automatically export the result as "edges_detected.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **multi-metric statistical analysis** to detect characteristic edge detection transformations:

### A. Edge Intensity Analysis
- **Gradient Magnitude Computation:** Calculates image gradients using Sobel operators on both original and result
- **Edge Strength Comparison:** Measures mean edge intensity in result vs. original
- **Relative Enhancement Factor:** Computes the ratio of edge intensity increase
- **Threshold Validation:** Requires significant edge enhancement (≥50% increase) to confirm filter application

### B. Background Suppression Detection
- **Dark Pixel Analysis:** Measures percentage of pixels below darkness threshold (value < 50)
- **Suppression Increase:** Compares dark pixel percentage before and after
- **Background Darkening:** Validates that non-edge areas have been suppressed to black/dark
- **Distribution Shift:** Confirms characteristic shift toward bimodal distribution (dark background + bright edges)

### C. Contrast Enhancement Measurement
- **Standard Deviation Analysis:** Measures pixel value spread as proxy for contrast
- **Contrast Ratio:** Compares overall contrast between original and result
- **Bimodal Pattern:** Checks for characteristic edge detection histogram shape
- **Dynamic Range:** Validates increased separation between edge and non-edge pixels

### D. Transformation Completeness
- **Pixel Difference Analysis:** Measures magnitude of change from original
- **Modification Threshold:** Ensures at least 10% of pixels significantly changed
- **Visual Transformation:** Confirms the image underwent substantial, characteristic modification
- **False Positive Prevention:** Distinguishes edge detection from other effects (blur, sharpen, threshold)

### Verification Checklist
- ✅ **Edge Intensity Increased:** Edge strength increased by ≥50% compared to original
- ✅ **Background Suppressed:** Dark pixel percentage increased by ≥20 percentage points
- ✅ **Contrast Enhanced:** Standard deviation increased, indicating stronger edge/background differentiation
- ✅ **Substantially Modified:** At least 10% of pixels changed significantly (>30 intensity units)

### Scoring System
- **100%:** All 4 criteria met (perfect edge detection with strong edges and dark background)
- **75-99%:** 3/4 criteria met (good edge detection with minor parameter issues)
- **50-74%:** 2/4 criteria met (partial edge detection, possibly weak settings)
- **0-49%:** <2 criteria met (edge detection not applied or failed)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure