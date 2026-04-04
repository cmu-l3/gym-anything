# GIMP Neon Edge Effect Task (`neon_edges@1`)

## Overview

This task tests an agent's ability to apply GIMP's Neon edge detection filter to create a distinctive artistic effect. The agent must navigate to the edge detection filters, apply the Neon effect with appropriate parameters, and produce an image with glowing colored edges on a dark background. This represents a common artistic workflow used in poster design, digital art, and creative photography.

## Rationale

**Why this task is valuable:**
- **Artistic Filter Introduction:** Introduces GIMP's edge-detection filters with immediate visual impact
- **Creative Effects Mastery:** Tests understanding of artistic transformation vs. basic adjustments
- **Filter Menu Navigation:** Builds familiarity with GIMP's extensive Filters menu hierarchy
- **Parameter Understanding:** Teaches how filter parameters affect output (radius controls edge detection sensitivity)
- **Real-world Application:** Used in graphic design, concert posters, neon-style artwork, and creative photography
- **Distinctive Results:** Produces immediately recognizable output that's easy to verify

**Skill Progression:** This task bridges basic color operations with advanced artistic effects, introducing the concept of edge-detection based filters.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through nested menus (`Filters → Edge-Detect → Neon...`)
- **Dialog Management:** Work with filter parameter dialogs
- **Parameter Adjustment:** Understand and set radius/amount parameters (or accept defaults)
- **Preview Interpretation:** Recognize what the effect will look like before applying
- **Confirmation Actions:** Apply filter using OK button
- **Wait for Processing:** Understand that filters may take time to compute

### B. GIMP Knowledge
- **Filters Menu System:** Navigate GIMP's comprehensive filter organization
- **Edge Detection Concepts:** Understand that edge detection identifies contrast boundaries
- **Filter Parameters:** Know that radius controls detection sensitivity and edge thickness
- **Processing Time:** Recognize that complex filters require computation time
- **Effect Preview:** Understand how to use filter preview windows
- **Artistic vs. Technical Filters:** Distinguish between corrective and creative filters

### C. Task-Specific Skills
- **Edge Analysis:** Visually assess where edges will appear in the source image
- **Effect Evaluation:** Recognize when neon effect has been successfully applied
- **Parameter Judgment:** Understand appropriate radius values (typically 5-15 pixels)
- **Artistic Vision:** Appreciate the aesthetic goal of glowing edges on dark background
- **Quality Assessment:** Evaluate whether edges are sufficiently bright and visible

## Task Steps

### 1. Image Analysis
- Examine the photo that opens automatically in GIMP
- Identify areas with strong edges (object boundaries, contrast changes)
- Anticipate how the neon effect will highlight these edges

### 2. Navigate to Neon Filter
- Click on "Filters" in the menu bar
- Hover over or click on "Edge-Detect" to open the submenu
- Locate "Neon..." in the edge detection options

### 3. Open Neon Dialog
- Click on "Neon..." to open the effect dialog
- Observe the parameter controls (Radius, Amount)
- Note the preview showing the effect

### 4. Configure Parameters
- Set Radius to approximately 5-10 pixels for clear edge detection
- Keep Amount at default (typically works well)
- Observe preview to ensure edges are visible and well-defined

### 5. Apply Effect
- Click "OK" to apply the neon edge effect
- Wait for GIMP to process the filter (may take a few seconds)
- Observe the transformation: bright glowing edges on dark/black background

### 6. Verify Result
- Confirm that the image now shows glowing outline style
- Check that background has become very dark or black
- Verify that edges are bright and colorful

### 7. Automatic Export
- The post-task hook will automatically export the result as "neon_effect.png"

## Verification Strategy

### Verification Approach
The verifier uses **multi-criteria edge and darkness analysis** to detect the characteristic neon effect:

### A. Background Darkness Analysis
- **Mean Brightness Check:** Verifies that overall image brightness has significantly decreased
- **Dark Pixel Percentage:** Calculates percentage of very dark pixels (intensity < 50)
- **Background Transformation:** Confirms background areas became very dark/black
- **Threshold Validation:** Ensures at least 60% of pixels are dark (characteristic of neon effect)

### B. Edge Brightness Analysis
- **Maximum Intensity Check:** Verifies presence of very bright pixels (edges)
- **Bright Pixel Detection:** Identifies pixels with intensity > 180 (glowing edges)
- **Edge Prominence:** Measures contrast between bright edges and dark background
- **Distribution Analysis:** Confirms bright pixels form edge-like structures

### C. Contrast Enhancement Verification
- **Overall Contrast Increase:** Measures that image contrast has dramatically increased
- **Standard Deviation Analysis:** Compares pixel intensity variation before/after
- **High Dynamic Range:** Verifies strong separation between dark and bright areas
- **Histogram Transformation:** Confirms bimodal distribution (dark background + bright edges)

### D. Edge Structure Validation
- **Edge Continuity:** Checks that bright areas form connected edge-like structures
- **Spatial Distribution:** Verifies edges are well-distributed (not concentrated in one area)
- **Edge Thickness:** Confirms edges have appropriate thickness (not too thin or too thick)
- **Quality Assessment:** Ensures edges are clean and well-defined

### Verification Checklist
- ✅ **Dark Background:** ≥60% of pixels are very dark (intensity < 50)
- ✅ **Bright Edges Present:** ≥5% of pixels are bright (intensity > 180)
- ✅ **Dramatically Darkened:** Mean brightness reduced by ≥50% from original
- ✅ **Contrast Enhanced:** Standard deviation increased by ≥30% or very high (>60)

### Scoring System
- **100%:** All 4 criteria met (perfect neon edge effect)
- **75-99%:** 3/4 criteria met (good effect with minor issues)
- **50-74%:** 2/4 criteria met (partial transformation but incomplete)
- **0-49%:** <2 criteria met (neon effect not successfully applied)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

### Mathematical Analysis Details