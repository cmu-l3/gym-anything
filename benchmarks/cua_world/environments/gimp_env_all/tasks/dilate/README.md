# GIMP Dilate Effect Task (`dilate@1`)

## Overview

This task tests an agent's ability to use GIMP's morphological image processing filters to expand bright regions in an image. The agent must navigate to the Dilate filter, apply it to expand light-colored areas, and understand how this morphological operation affects image structure. This represents a fundamental image processing technique used in edge enhancement, gap filling, and image preprocessing workflows.

## Rationale

**Why this task is valuable:**
- **Morphological Operations:** Introduces fundamental image processing concepts (dilation/erosion)
- **Edge Processing:** Tests understanding of how filters affect boundaries and edges
- **Single-step Operation:** Simple, one-click filter with immediate visual feedback
- **Real-world Applications:** Used in OCR preprocessing, mask creation, edge thickening, and small gap filling
- **Foundation Technique:** Establishes concepts needed for advanced image processing (erosion, opening/closing operations)
- **Minimal Parameters:** No complex settings, making it ideal for learning filter navigation

**Skill Progression:** This task introduces GIMP's Generic filter category with a simple, visually clear operation that builds understanding for more complex morphological and image processing workflows.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through nested menu structure (`Filters → Generic → Dilate`)
- **Filter Application:** Understand that filter applies directly without preview dialog
- **Visual Assessment:** Recognize the expansion effect on bright regions and edges
- **Result Confirmation:** Compare before/after to verify correct filter application

### B. GIMP Knowledge
- **Filter System:** Understand GIMP's extensive filter menu organization
- **Generic Filters:** Locate and identify the Generic filter category
- **Morphological Concepts:** Understand that dilation expands bright/white regions
- **Immediate Application:** Recognize that simple filters may apply without parameter dialogs
- **Filter Effects:** Understand how morphological operations affect edges and boundaries

### C. Task-Specific Skills
- **Morphological Understanding:** Know what "dilate" means in image processing context
- **Edge Analysis:** Recognize how bright edges thicken and dark gaps may close
- **Effect Magnitude:** Understand that one dilation pass has subtle but measurable effects
- **Quality Assessment:** Verify that light regions expanded appropriately without artifacts

## Task Steps

### 1. Initial Image Examination
- Examine the image that opens automatically in GIMP
- Identify bright regions, edges, and boundaries that will be affected
- Note the current thickness of bright areas and edges

### 2. Navigate to Filter Menu
- Click on "Filters" in the menu bar to open the Filters menu
- Locate and hover over "Generic" to open the generic filters submenu
- Identify the morphological operation options

### 3. Select Dilate Filter
- Click on "Dilate" from the Generic submenu
- The filter applies immediately (no parameter dialog for basic dilation)
- Observe the instant application of the effect

### 4. Verify Transformation
- Compare the result with the original appearance
- Confirm that bright regions have expanded slightly
- Verify that edges appear thicker and small dark gaps may have filled
- Note that the overall structure remains recognizable

### 5. Quality Check
- Ensure no unexpected artifacts or degradation occurred
- Confirm that the dilation effect is visible but not excessive
- Verify that the image dimensions remain unchanged

### 6. Automatic Export
- The post-task hook will automatically export the result as "dilated_image.png"

## Verification Strategy

### Verification Approach
The verifier uses **multi-metric morphological analysis** to detect bright region expansion:

### A. Brightness Distribution Analysis
- **High-Intensity Pixel Count:** Measures the number of bright pixels (intensity > 200) before and after
- **Mean Brightness Calculation:** Computes overall image brightness and verifies increase
- **Bright Region Expansion:** Confirms that the percentage of bright pixels increased
- **Threshold-based Detection:** Uses multiple intensity thresholds to detect expansion at various brightness levels

### B. Edge Thickness Analysis
- **Edge Detection:** Applies Sobel edge detection to both original and result images
- **Edge Strength Measurement:** Calculates total edge magnitude and intensity
- **Edge Expansion Verification:** Confirms that detected edges are stronger/thicker after dilation
- **Structural Comparison:** Uses edge analysis to verify morphological expansion occurred

### C. Morphological Signature Detection
- **Gradient Analysis:** Examines image gradients to detect characteristic dilation patterns
- **Local Maxima Expansion:** Verifies that local bright regions grew in size
- **Statistical Validation:** Uses standard deviation and histogram analysis to confirm effect
- **Spatial Consistency:** Ensures expansion occurred uniformly across the image

### D. Change Magnitude Assessment
- **Pixel Difference Analysis:** Measures pixel-wise changes between original and result
- **Significant Modification Check:** Ensures at least 2-5% of pixels changed meaningfully
- **Effect Consistency:** Verifies changes match expected dilation characteristics (brightening near edges)
- **Artifact Detection:** Checks that no unexpected anomalies were introduced

### Verification Checklist
- ✅ **Bright Region Expansion:** Increase in high-intensity pixel count (>1% relative increase)
- ✅ **Overall Brightness Increase:** Mean image brightness increased by at least 0.5%
- ✅ **Edge Thickening:** Edge magnitude sum increased, indicating thicker edges
- ✅ **Image Modified:** At least 2% of pixels changed by >10 intensity units
- ✅ **Morphological Consistency:** Changes match expected dilation patterns

### Scoring System
- **100%:** All criteria met with clear bright region expansion and edge thickening
- **75-99%:** Good dilation effect with most criteria met
- **50-74%:** Partial dilation detected but weak or incomplete
- **0-49%:** No significant dilation effect detected or incorrect operation

**Pass Threshold:** 75% (requires clear evidence of morphological dilation)

### Mathematical Verification Details