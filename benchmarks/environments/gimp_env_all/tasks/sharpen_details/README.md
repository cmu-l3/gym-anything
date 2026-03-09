# GIMP Sharpen Details Task (`sharpen_details@1`)

## Overview

This task tests an agent's ability to use GIMP's sharpening filters to enhance image details and edge definition. The agent must navigate to the Unsharp Mask filter, apply appropriate sharpening parameters, and ensure the image gains clarity and definition without introducing excessive artifacts. This represents a fundamental enhancement operation used in photography, document scanning, and general image improvement workflows.

## Rationale

**Why this task is valuable:**
- **Essential Enhancement:** Sharpening is one of the most common image enhancement operations in photography and design
- **Filter Navigation:** Introduces GIMP's extensive filter system through a practical, frequently-used filter
- **Parameter Understanding:** Tests ability to work with filter dialogs that require numeric input and preview assessment
- **Quality Judgment:** Requires balancing enhancement with artifact prevention—a key skill in image processing
- **Professional Workflow:** Sharpening is a standard step in photography post-processing and print preparation
- **Visual Assessment Skills:** Develops understanding of image quality metrics and enhancement effectiveness

**Skill Progression:** This task introduces filter-based image enhancement with clear quality criteria, bridging basic adjustments with more sophisticated image processing operations.

## Skills Required

### A. Interaction Skills
- **Multi-level Menu Navigation:** Navigate through `Filters → Enhance → Unsharp Mask`
- **Dialog Box Interaction:** Work with the Unsharp Mask dialog and its multiple parameters
- **Slider Manipulation:** Adjust Amount, Radius, and Threshold sliders appropriately
- **Preview Assessment:** Evaluate the preview to judge appropriate sharpening levels
- **Parameter Entry:** Enter numeric values or use slider controls
- **Confirmation Actions:** Apply filter changes using OK button

### B. GIMP Knowledge
- **Filter System Organization:** Understand GIMP's hierarchical filter menu structure
- **Enhancement Filters:** Know where image enhancement operations are located
- **Unsharp Mask Concepts:** Understand what "Unsharp Mask" means and how it works
- **Preview Functionality:** Use real-time preview to assess filter effects before applying
- **Parameter Relationships:** Understand how Amount, Radius, and Threshold interact
- **Non-destructive Testing:** Know that dialog preview doesn't commit changes until OK is clicked

### C. Task-Specific Skills
- **Sharpening Theory:** Understand that sharpening enhances edges and fine details
- **Parameter Selection:** Choose appropriate values for natural-looking enhancement
- **Over-sharpening Awareness:** Recognize when sharpening is excessive and creates halos or artifacts
- **Detail Enhancement:** Identify areas that benefit from sharpening (edges, textures, fine details)
- **Quality Assessment:** Judge when image has achieved optimal clarity without degradation
- **Visual Refinement:** Balance technical parameters with aesthetic judgment

## Task Steps

### 1. Initial Image Assessment
- Examine the slightly soft image that opens automatically in GIMP
- Identify areas that would benefit from sharpening (edges, textures, fine details)
- Note the overall sharpness level and areas lacking definition

### 2. Navigate to Sharpen Filter
- Click on "Filters" in the menu bar
- Hover over or click "Enhance" to open the enhancement submenu
- Locate "Unsharp Mask" in the enhancement options

### 3. Open Unsharp Mask Dialog
- Click on "Unsharp Mask" to open the filter dialog
- Observe the preview window and parameter controls
- Ensure "Preview" checkbox is enabled to see real-time changes

### 4. Configure Sharpening Parameters
- **Radius:** Set to approximately 1.0-3.0 pixels (controls sharpening edge width)
- **Amount:** Set to approximately 0.5-1.5 (controls sharpening intensity)
- **Threshold:** Keep low at 0-5 (controls which edges are sharpened)
- Adjust values while observing the preview for natural enhancement

### 5. Preview Assessment
- Zoom into the preview to examine fine details at 100% magnification
- Check for improved edge definition and detail clarity
- Verify no excessive halos or artifacts around high-contrast edges
- Ensure enhancement looks natural and not over-processed

### 6. Fine-tune Parameters (if needed)
- Adjust sliders if initial settings are too strong or too weak
- Balance sharpening strength with natural appearance
- Aim for noticeable improvement without obvious processing artifacts

### 7. Apply Sharpening
- Click "OK" to apply the Unsharp Mask filter
- Wait for GIMP to process the entire image
- Observe the sharpened result in the main canvas

### 8. Final Verification
- Zoom in to examine details and edges at 100% view
- Compare mentally with the original softness
- Verify that the image has gained clarity and definition

### 9. Automatic Export
- The post-task hook will automatically export the result as "sharpened_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **edge intensity analysis and high-frequency content measurement** to detect and quantify sharpening:

### A. Edge Enhancement Detection
- **Sobel Edge Detection:** Applies Sobel operators to detect edges in original and result images
- **Edge Intensity Measurement:** Calculates average edge strength (gradient magnitude)
- **Enhancement Ratio:** Compares edge intensity before/after to quantify sharpening effect
- **Threshold Analysis:** Requires significant edge enhancement (typically 15-40% increase)

### B. High-Frequency Content Analysis
- **FFT-based Analysis:** Uses Fast Fourier Transform to analyze frequency content
- **High-Frequency Power:** Measures energy in high-frequency components (fine details)
- **Frequency Shift Detection:** Confirms increase in high-frequency content indicating sharpening
- **Spatial Detail Metrics:** Analyzes local standard deviation as proxy for detail enhancement

### C. Quality Preservation
- **Structural Similarity (SSIM):** Ensures overall image structure is preserved (SSIM ≥ 0.85)
- **Artifact Detection:** Checks for excessive noise or halos that indicate over-sharpening
- **Brightness Preservation:** Verifies that average brightness hasn't changed dramatically
- **Natural Appearance:** Ensures enhancement looks realistic and not over-processed

### D. Comprehensive Assessment
- **Multi-metric Validation:** Combines edge analysis, frequency analysis, and quality checks
- **Reasonable Enhancement Range:** Ensures sharpening is noticeable but not excessive
- **Modification Verification:** Confirms the image was actually altered from the original
- **Professional Standards:** Applies industry-standard criteria for acceptable sharpening

### Verification Checklist
- ✅ **Edge Enhancement:** Edge intensity increased by 15-40% compared to original
- ✅ **High-Frequency Boost:** Measurable increase in high-frequency content/detail
- ✅ **Structure Preserved:** SSIM ≥ 0.85 indicates overall image integrity maintained
- ✅ **Quality Maintained:** No excessive artifacts, halos, or noise introduced
- ✅ **Appropriate Magnitude:** Enhancement is noticeable but not over-sharpened

### Scoring System
- **100%:** All criteria met with excellent detail enhancement and quality preservation
- **75-99%:** Good sharpening with minor issues in balance or quality
- **50-74%:** Adequate sharpening but with notable quality issues or insufficient enhancement
- **0-49%:** Insufficient sharpening, over-sharpening, or failed operation

**Pass Threshold:** 75% (requires effective sharpening with good quality preservation)

## Technical Implementation

### Files Structure