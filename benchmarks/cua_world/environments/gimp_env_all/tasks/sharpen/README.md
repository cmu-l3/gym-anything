# GIMP Sharpen Filter Task (`sharpen@1`)

## Overview

This task tests an agent's ability to use GIMP's sharpening filters to enhance image detail and edge definition. The agent must navigate to the Unsharp Mask filter (GIMP's primary sharpening tool), apply appropriate sharpening parameters, and produce a noticeably sharper image while avoiding over-sharpening artifacts. This represents a fundamental image enhancement operation used extensively in photography, digital art, and image restoration workflows.

## Rationale

**Why this task is valuable:**
- **Essential Enhancement Operation:** Sharpening is one of the most common post-processing operations in photography and digital imaging
- **Filter System Introduction:** Introduces GIMP's extensive filter menu system in a practical, visual context
- **Parameter Understanding:** Tests ability to work with filter dialogs and adjust parameters meaningfully
- **Quality Assessment:** Requires visual judgment about appropriate enhancement levels
- **Opposite of Blur:** Provides pedagogical counterpoint to gaussian_blur task, teaching enhancement vs. softening
- **Foundation Skill:** Establishes concepts needed for more advanced filters and enhancements

**Skill Progression:** This task complements the gaussian_blur task by teaching the opposite operation, building understanding of image enhancement workflows at a similar difficulty level.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested filter menu structure (`Filters → Enhance → Sharpen (Unsharp Mask)`)
- **Dialog Management:** Work with filter preview dialogs and parameter controls
- **Slider Manipulation:** Adjust sliders to control sharpening intensity (Amount, Radius, Threshold)
- **Preview Assessment:** Use real-time preview to evaluate filter effects before applying
- **Confirmation Actions:** Apply filter changes using OK button
- **Visual Comparison:** Compare before/after to assess enhancement quality

### B. GIMP Knowledge
- **Filter System:** Understand GIMP's filter organization and the Enhance category
- **Unsharp Mask Concepts:** Know that "Unsharp Mask" is the primary sharpening tool in professional image editing
- **Parameter Relationships:** Understand how Amount, Radius, and Threshold affect sharpening
- **Preview Toggle:** Know how to use preview checkbox to compare before/after
- **Filter Application:** Understand that filters apply to the active layer/selection
- **Processing Time:** Recognize that filters may take time to process on large images

### C. Task-Specific Skills
- **Sharpness Assessment:** Visually evaluate whether an image appears sharp or soft
- **Edge Recognition:** Identify edges and details that benefit from sharpening
- **Over-sharpening Awareness:** Recognize when excessive sharpening creates halos or artifacts
- **Appropriate Enhancement:** Choose sharpening strength that enhances without degrading
- **Photography Principles:** Understand that sharpening enhances perceived detail and clarity

## Task Steps

### 1. Initial Image Assessment
- Examine the photograph that opens automatically in GIMP
- Identify areas with fine detail (textures, edges, patterns) that could benefit from sharpening
- Assess the current sharpness level as a baseline for comparison

### 2. Navigate to Sharpen Filter
- Click on "Filters" in the menu bar
- Hover over or click "Enhance" to open the enhancement submenu
- Locate "Sharpen (Unsharp Mask)" in the submenu options

### 3. Open Unsharp Mask Dialog
- Click on "Sharpen (Unsharp Mask)" to open the filter dialog
- Observe the preview window showing the current image
- Note the three main parameters: Amount, Radius, and Threshold

### 4. Enable Preview
- Ensure the "Preview" checkbox is checked
- This allows real-time visualization of sharpening effects
- Compare sharpened preview with original image

### 5. Adjust Sharpening Parameters
- **Amount:** Increase to approximately 1.0-2.0 (controls sharpening strength)
- **Radius:** Set to approximately 1.0-3.0 pixels (controls edge width)
- **Threshold:** Keep low, around 0-5 (controls which edges are sharpened)
- Use the preview to find appropriate values that enhance without creating artifacts

### 6. Visual Quality Check
- Zoom in on detailed areas to inspect sharpening quality
- Look for enhanced edge definition without excessive halos
- Ensure the image appears crisper and more defined
- Verify that sharpening doesn't introduce noise or artifacts

### 7. Apply Sharpening
- Click "OK" button to apply the unsharp mask filter
- Wait for processing to complete (may take a few seconds)
- Observe the final sharpened result in the canvas

### 8. Final Verification
- Compare the result with your memory of the original softness
- Confirm that edges and details appear noticeably sharper
- Verify that the enhancement looks natural and professional

### 9. Automatic Export
- The post-task hook will automatically export the result as "sharpened_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **advanced edge detection and sharpness metrics** to quantitatively measure enhancement:

### A. Edge Strength Analysis
- **Laplacian Variance:** Calculates variance of Laplacian filter response, which directly measures sharpness
- **Higher Variance = Sharper:** Sharpened images show significantly increased Laplacian variance
- **Threshold:** Requires minimum 20% increase in Laplacian variance for successful sharpening
- **Mathematical Foundation:** Laplacian operator detects edges and high-frequency content

### B. High-Frequency Content Measurement
- **FFT Analysis:** Uses Fast Fourier Transform to analyze frequency domain
- **High-Frequency Boost:** Sharpening increases high-frequency component energy
- **Frequency Ratio:** Compares high-frequency vs. low-frequency energy before/after
- **Scientific Metric:** Provides objective measurement of detail enhancement

### C. Edge Detection Comparison
- **Sobel Edge Detector:** Applies Sobel filter to detect edges in both images
- **Edge Strength Quantification:** Measures average edge magnitude in original vs. sharpened
- **Relative Increase:** Calculates percentage increase in edge strength
- **Multi-Direction Analysis:** Evaluates both horizontal and vertical edge components

### D. Quality Control Checks
- **Over-sharpening Detection:** Monitors for excessive edge enhancement (>200% increase triggers warning)
- **Artifact Prevention:** Checks that sharpening doesn't introduce extreme pixel value changes
- **Natural Appearance:** Ensures enhancement maintains photographic realism
- **Dimension Preservation:** Verifies image size and format remain unchanged

### Verification Checklist
- ✅ **Laplacian Variance Increased:** Minimum 20% increase in sharpness metric
- ✅ **Edge Strength Enhanced:** Noticeable increase in detected edge magnitude
- ✅ **High-Frequency Content Boosted:** FFT analysis shows enhanced detail components
- ✅ **Quality Maintained:** No severe over-sharpening artifacts or distortion
- ✅ **Image Modified:** Clear measurable differences from original image

### Scoring System
- **100%:** Excellent sharpening with 30%+ Laplacian variance increase and good quality
- **75-99%:** Good sharpening with 20-30% variance increase and acceptable quality
- **50-74%:** Minimal sharpening detected (10-20% increase) or quality issues
- **0-49%:** Insufficient sharpening (<10% increase) or failed operation

**Pass Threshold:** 75% (requires meaningful sharpening with good quality preservation)

## Technical Implementation

### Files Structure