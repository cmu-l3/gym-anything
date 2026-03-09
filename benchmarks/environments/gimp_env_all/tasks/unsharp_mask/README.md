# GIMP Unsharp Mask Task (`unsharp_mask@1`)

## Overview

This task tests an agent's ability to use GIMP's Unsharp Mask filter to enhance image sharpness and edge detail. The agent must navigate to the filter, apply it with appropriate parameters, and ensure the resulting image shows improved sharpness without introducing excessive artifacts. This represents a fundamental image enhancement technique used extensively in photography, print preparation, and digital image processing.

## Rationale

**Why this task is valuable:**
- **Core Enhancement Technique:** Unsharp Mask is the gold standard for professional image sharpening
- **Filter System Introduction:** Introduces GIMP's extensive filter menu in a practical, commonly-used context
- **Parameter Understanding:** Requires working with filter dialogs and adjusting parameters appropriately
- **Quality Assessment:** Tests understanding of appropriate enhancement levels (enough but not too much)
- **Real-world Relevance:** Used in virtually every professional photography and image editing workflow
- **Different from Basic Sharpen:** More sophisticated than simple sharpen, teaching advanced concepts

**Skill Progression:** This task bridges basic filter application with parameter-driven enhancement, preparing agents for more sophisticated image processing operations.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through nested filter menu (`Filters → Enhance → Unsharp Mask`)
- **Dialog Interaction:** Work with filter dialog boxes containing multiple parameters
- **Parameter Adjustment:** Understand and adjust sliders for Radius, Amount, and Threshold
- **Preview Assessment:** Evaluate preview results to determine appropriate settings
- **Apply Confirmation:** Confirm and apply filter changes using OK button

### B. GIMP Knowledge
- **Filter Menu System:** Navigate GIMP's extensive filter hierarchy
- **Enhancement Category:** Understand that sharpening tools are in the Enhance submenu
- **Unsharp Mask Concept:** Know the difference between Unsharp Mask and basic sharpen
- **Parameter Interactions:** Understand how Radius, Amount, and Threshold affect results
- **Preview System:** Use real-time preview to assess filter effects before applying
- **Non-destructive Preview:** Recognize that preview shows temporary results until confirmed

### C. Task-Specific Skills
- **Sharpness Assessment:** Visually evaluate image sharpness and edge definition
- **Parameter Selection:** Choose appropriate values for different image types
- **Artifact Recognition:** Identify when sharpening is excessive (halos, noise amplification)
- **Quality Judgment:** Balance sharpness enhancement with natural appearance
- **Enhancement Degree:** Understand what constitutes "moderate" vs "aggressive" sharpening

## Task Steps

### 1. Initial Image Assessment
- Examine the photo that opens automatically in GIMP
- Identify areas that would benefit from sharpness enhancement (edges, fine details)
- Note the current sharpness level to compare after enhancement

### 2. Navigate to Unsharp Mask Filter
- Click on "Filters" in the menu bar
- Hover over "Enhance" to open the enhancement submenu
- Locate and click on "Unsharp Mask"

### 3. Unsharp Mask Dialog Opens
- Observe the filter dialog with its three main parameters: Radius, Amount, Threshold
- Note the preview checkbox (ensure it's enabled to see real-time effects)
- Examine default or current parameter values

### 4. Adjust Radius Parameter
- Set Radius to control the width of sharpening effect (typically 1.0-3.0 pixels)
- Recommended starting value: 1.5 pixels for general photography
- Observe preview to see how Radius affects edge enhancement width

### 5. Adjust Amount Parameter
- Set Amount to control sharpening intensity (typically 0.5-1.5)
- Recommended starting value: 1.0 for moderate enhancement
- Monitor preview for appropriate enhancement level without artifacts

### 6. Adjust Threshold (Optional)
- Threshold can be left at 0 for most images
- Higher threshold values prevent sharpening low-contrast areas (reduces noise amplification)
- For this task, threshold can remain at default (0)

### 7. Preview Assessment
- Enable preview checkbox if not already active
- Zoom to 100% view to accurately assess sharpening effect
- Check that edges are crisper without obvious halos or artifacts

### 8. Apply Enhancement
- Once satisfied with preview, click "OK" button
- Wait for filter to process and apply to the full image
- Observe the enhanced result in the canvas

### 9. Automatic Export
- The post-task hook will automatically export the result as "sharpened_unsharp.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **mathematical sharpness analysis** to quantify edge enhancement:

### A. Sharpness Metric Calculation
- **Laplacian Variance:** Calculates image sharpness using Laplacian operator (measures edge magnitude)
- **Before/After Comparison:** Computes sharpness metric for both original and result images
- **Enhancement Ratio:** Calculates the proportional increase in sharpness
- **Standard Metric:** Uses well-established computer vision technique for objective sharpness measurement

### B. Edge Enhancement Detection
- **High-frequency Analysis:** Examines enhancement of fine details and edges
- **Gradient Magnitude:** Measures edge strength increase across the image
- **Spatial Frequency:** Analyzes enhancement in frequency domain
- **Edge Preservation:** Ensures edges are enhanced without excessive artifacts

### C. Quality Validation
- **Reasonable Enhancement:** Verifies sharpening is noticeable but not excessive
- **Threshold Bounds:** Ensures enhancement is within 10%-80% increase range
- **Artifact Avoidance:** Checks that sharpening didn't introduce severe artifacts
- **Natural Appearance:** Validates that enhancement maintains photographic quality

### D. Change Detection
- **Modification Verification:** Confirms the image was actually modified from original
- **Significant Change:** Ensures change is substantial enough to represent successful sharpening
- **Target Area Enhancement:** Verifies sharpening affected appropriate image regions

### Verification Checklist
- ✅ **Sharpness Increased:** Laplacian variance shows measurable increase (10%+ recommended)
- ✅ **Reasonable Enhancement:** Sharpness increase is within acceptable bounds (10%-80%)
- ✅ **Image Modified:** Clear detectable differences from original image
- ✅ **Quality Maintained:** No severe artifacts or unnatural appearance

### Scoring System
- **100%:** Optimal sharpness enhancement (15%-60% increase) with excellent quality
- **75-99%:** Good sharpness enhancement (10%-80% increase) with acceptable quality
- **50-74%:** Minimal enhancement (5%-10% increase) or slight over-sharpening (80%-100%)
- **0-49%:** Insufficient enhancement (<5%) or excessive sharpening (>100%)

**Pass Threshold:** 75% (requires noticeable, appropriate sharpness enhancement)

### Mathematical Sharpness Analysis