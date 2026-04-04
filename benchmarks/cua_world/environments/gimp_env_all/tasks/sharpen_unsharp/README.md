# GIMP Sharpen (Unsharp Mask) Task (`sharpen_unsharp@1`)

## Overview

This task tests an agent's ability to use GIMP's sharpening filters to enhance image detail and edge definition. The agent must navigate to the Unsharp Mask filter, apply appropriate sharpening parameters, and produce a visibly sharper image without introducing excessive artifacts. This represents one of the most fundamental image enhancement operations used in photography and digital image processing.

## Rationale

**Why this task is valuable:**
- **Essential Enhancement Tool:** Sharpening is one of the most common adjustments in photography and image editing
- **Filter System Introduction:** Introduces GIMP's extensive filter menu and parameter adjustment dialogs
- **Quality vs. Artifact Balance:** Tests understanding of appropriate parameter ranges to enhance without over-processing
- **Complementary to Blur:** Provides the opposite operation to gaussian_blur, completing the basic sharpness manipulation toolkit
- **Professional Workflow:** Standard step in photo editing pipelines for print and digital media
- **Parameter Understanding:** Introduces concept of filter parameters (radius, amount, threshold)

**Skill Progression:** This task builds on basic menu navigation while introducing filter parameter adjustment, bridging simple one-click operations with more nuanced editing decisions.

## Skills Required

### A. Interaction Skills
- **Filter Menu Navigation:** Navigate through nested menu structure (`Filters → Enhance → Unsharp Mask`)
- **Dialog Management:** Work with filter parameter dialogs
- **Slider Manipulation:** Adjust numeric sliders to control sharpening intensity
- **Preview Assessment:** Use preview functionality to evaluate effect before applying
- **Parameter Entry:** Enter or adjust numeric values for filter parameters
- **Apply Confirmation:** Confirm filter application with OK button

### B. GIMP Knowledge
- **Filter System:** Understand GIMP's comprehensive filter organization and categories
- **Unsharp Mask Concept:** Know that "Unsharp Mask" is a professional sharpening technique
- **Filter Parameters:** Understand that filters have adjustable parameters affecting the result
- **Preview Functionality:** Know that filters show real-time preview of effects
- **Processing Time:** Recognize that complex filters may take time to apply
- **Non-destructive Preview:** Understand that preview doesn't modify image until OK is clicked

### C. Task-Specific Skills
- **Sharpness Assessment:** Visually evaluate when an image has appropriate sharpness
- **Edge Enhancement Recognition:** Understand how sharpening affects edge definition
- **Artifact Detection:** Recognize over-sharpening artifacts (halos, noise amplification)
- **Parameter Selection:** Choose appropriate values for radius (0.5-2.0), amount (0.5-1.5), threshold (0-5)
- **Quality Judgment:** Balance enhancement with natural appearance
- **Detail Preservation:** Ensure fine details become more defined without harsh artifacts

## Task Steps

### 1. Initial Image Assessment
- Examine the portrait or landscape image that opens automatically in GIMP
- Identify areas that could benefit from increased sharpness (edges, details, textures)
- Note the current sharpness level as baseline for comparison

### 2. Navigate to Sharpen Filter
- Click on "Filters" in the menu bar to open the Filters menu
- Hover over or click "Enhance" to open the enhancement submenu
- Locate "Unsharp Mask" in the submenu options

### 3. Open Unsharp Mask Dialog
- Click on "Unsharp Mask" to open the filter dialog
- Observe the preview area and parameter controls
- Note the default parameter values (typically Radius: 1.0, Amount: 1.0, Threshold: 0)

### 4. Adjust Sharpening Parameters
- **Radius:** Set to approximately 1.0-2.0 pixels (controls sharpening spread)
- **Amount:** Set to approximately 0.8-1.5 (controls sharpening intensity)
- **Threshold:** Keep at 0-5 (controls which pixels are affected)
- Observe the preview to see how changes affect the image

### 5. Evaluate Preview
- Enable preview checkbox if not already active
- Examine edge definition and detail enhancement
- Look for any unwanted artifacts (halos, noise, oversaturation of edges)
- Adjust parameters if image appears over-sharpened or under-sharpened

### 6. Apply Sharpening
- Once satisfied with the preview, click "OK" to apply the filter
- Wait for processing to complete (usually very fast)
- Observe the final sharpened result in the canvas

### 7. Quality Verification
- Zoom in to examine edge quality and detail enhancement
- Verify that sharpening appears natural without obvious artifacts
- Confirm that important details (eyes, text, textures) are more defined

### 8. Automatic Export
- The post-task hook will automatically export the result as "sharpened_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **edge strength analysis and high-frequency content measurement** to detect sharpening:

### A. Edge Strength Analysis
- **Edge Detection:** Uses Sobel or Canny edge detection to identify edges in both images
- **Edge Intensity Comparison:** Measures the strength/intensity of detected edges
- **Sharpness Metric:** Calculates edge strength increase as indicator of sharpening
- **Statistical Analysis:** Compares mean and maximum edge intensities before/after

### B. High-Frequency Content Measurement
- **Frequency Domain Analysis:** Uses Laplacian variance or high-pass filtering to measure detail
- **Sharpness Quantification:** Higher variance indicates increased sharpness and detail
- **Percentage Increase:** Calculates relative increase in high-frequency content
- **Threshold Validation:** Ensures increase is significant enough (typically 10-50% improvement)

### C. Quality Preservation Assessment
- **Over-sharpening Detection:** Checks for excessive edge halos or artifacts
- **Noise Analysis:** Ensures noise levels haven't increased dramatically
- **Color Integrity:** Verifies colors remain natural and not oversaturated
- **Structure Preservation:** Confirms overall image structure is maintained

### D. Artifact Detection
- **Halo Detection:** Looks for bright/dark halos around edges (sign of over-sharpening)
- **Noise Amplification:** Checks that flat areas haven't become excessively noisy
- **Clipping Analysis:** Ensures highlights/shadows aren't clipped from aggressive sharpening
- **Natural Appearance:** Validates that sharpening enhances rather than degrades visual quality

### Verification Checklist
- ✅ **Sharpness Increased:** Edge strength or high-frequency content increased by 10-50%
- ✅ **Quality Maintained:** No excessive artifacts, halos, or noise amplification
- ✅ **Image Modified:** Clear measurable differences from original image
- ✅ **Appropriate Range:** Sharpening within professional acceptable range (not over/under-processed)

### Scoring System
- **100%:** Optimal sharpening with 15-40% edge strength increase and no artifacts
- **75-99%:** Good sharpening with measurable improvement and minimal artifacts
- **50-74%:** Detectable sharpening but either too subtle or with minor quality issues
- **0-49%:** Insufficient sharpening, no change, or severe artifacts/over-sharpening

**Pass Threshold:** 75% (requires clear sharpening improvement without quality degradation)

## Technical Implementation

### Files Structure