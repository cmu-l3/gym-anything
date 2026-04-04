# GIMP Pixelate Filter Task (`pixelate@1`)

## Overview

This task tests an agent's ability to apply GIMP's Pixelate filter to create a mosaic/pixel-block effect on an image. The agent must navigate to the Pixelate filter, configure the pixel block size, and apply the effect to reduce image detail into visible pixel squares. This represents a common operation used for privacy protection (obscuring faces/text), artistic stylization, and retro aesthetic effects.

## Rationale

**Why this task is valuable:**
- **Privacy Tool Mastery:** Pixelation is essential for anonymizing sensitive visual information
- **Filter System Introduction:** Introduces GIMP's extensive Filters menu in a straightforward way
- **Single-Parameter Control:** Tests focused adjustment of one clear parameter (pixel size)
- **Immediate Visual Feedback:** The effect is obvious and easy to recognize
- **Real-world Application:** Common in journalism, social media, legal documentation, and artistic design
- **Practical Utility:** Balances technical skill with useful, everyday functionality

**Skill Progression:** This task sits between basic operations (like mirroring) and complex filters, making it ideal for early-intermediate training.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through `Filters → Blur → Pixelate` multi-level hierarchy
- **Dialog Management:** Interact with the Pixelate filter dialog interface
- **Numeric Input:** Set pixel block size value (typically 10-30 pixels)
- **Preview Monitoring:** Observe live preview to assess effect intensity
- **Dialog Confirmation:** Apply changes using OK button

### B. GIMP Knowledge
- **Filters Menu System:** Understand the organization of GIMP's extensive filter categories
- **Blur Filter Family:** Recognize pixelate as part of the blur/obscure filter group
- **Parameter Concepts:** Understand that larger values create bigger pixel blocks (more dramatic effect)
- **Live Preview:** Know that the dialog shows real-time preview of adjustments
- **Filter Application:** Understand that filters modify the active layer permanently

### C. Task-Specific Skills
- **Effect Intensity Assessment:** Judge appropriate pixel block size for desired effect
- **Detail Reduction Understanding:** Recognize how pixelation reduces image detail
- **Use Case Awareness:** Know when pixelation is appropriate (privacy vs. artistic effect)
- **Visual Recognition:** Identify when the effect has been successfully applied
- **Balance Judgment:** Find the right pixel size—not too subtle, not excessively blocky

## Task Steps

### 1. Initial Image Examination
- Examine the image that opens automatically in GIMP (typically a portrait or street scene)
- Identify areas that will show clear pixelation effect
- Plan the desired pixel block size (typically 12-20 for noticeable but moderate effect)

### 2. Navigate to Pixelate Filter
- Click on "Filters" in the menu bar to open the Filters menu
- Hover over "Blur" to expand the blur filters submenu
- Locate "Pixelate" (or "Pixelize" depending on GIMP version)

### 3. Open Pixelate Dialog
- Click on "Pixelate" to open the filter dialog
- Wait for the Pixelate dialog window to appear
- Observe the preview pane and parameter controls

### 4. Configure Pixel Block Size
- Locate the pixel width/height parameter (often called "Pixel Width" or "Block Size")
- Set the value to approximately 15 pixels for a noticeable mosaic effect
- If width and height are separate, set both to the same value for square blocks
- Observe the preview updating to show the pixelation effect

### 5. Preview Assessment
- Review the preview to ensure pixelation is visible but not excessive
- Verify that image details have been reduced to visible pixel blocks
- Adjust the size if needed (increase for more dramatic effect, decrease for subtlety)

### 6. Apply Pixelate Filter
- Click "OK" button to apply the pixelation effect
- Wait for GIMP to process the filter application
- Observe that the image now displays clear pixel block patterns

### 7. Visual Verification
- Zoom in if needed to confirm pixel blocks are visible
- Verify that the entire image has been uniformly pixelated
- Confirm the effect matches expectations

### 8. Automatic Export
- The post-task hook will automatically export the result as "pixelated_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **multi-metric analysis** combining color reduction, edge detection, and structural pattern analysis:

### A. Color Reduction Analysis
- **Unique Color Counting:** Pixelation significantly reduces the number of unique colors
- **Color Palette Comparison:** Measures decrease in color diversity from original to result
- **Reduction Threshold:** Expects at least 30% reduction in unique colors for successful pixelation
- **Statistical Validation:** Uses NumPy to efficiently count unique RGB combinations

### B. Edge Pattern Analysis
- **Edge Detection:** Applies edge detection to identify boundaries
- **Grid Pattern Recognition:** Pixelation creates regular grid-like edge patterns
- **Edge Density Measurement:** Calculates proportion of edge pixels in the image
- **Structural Change:** Compares edge patterns before and after for characteristic changes

### C. Block Detection via Variance Analysis
- **Local Variance Computation:** Calculates color variance in small regions (e.g., 5x5 pixels)
- **Uniformity Assessment:** Pixelated images have large regions with zero or very low variance
- **Low-Variance Region Counting:** Measures percentage of image with uniform color blocks
- **Threshold Validation:** Expects significantly increased uniformity compared to original

### D. Visual Difference Quantification
- **Pixel-wise Comparison:** Calculates mean absolute difference between original and result
- **Modification Verification:** Ensures substantial changes occurred (mean difference > 10 intensity units)
- **Smoothing Detection:** Pixelation creates characteristic smoothing within blocks
- **Detail Loss Confirmation:** Validates that fine details have been reduced

### Verification Checklist
- ✅ **Color Reduction:** Unique colors decreased by at least 30%
- ✅ **Block Uniformity:** At least 40% of image area shows low variance (uniform blocks)
- ✅ **Substantial Modification:** Mean pixel difference from original exceeds 10 intensity units
- ✅ **Edge Pattern Change:** Edge density or structure changed significantly (±20%)

### Scoring System
- **100%:** All 4 criteria met (excellent pixelation with clear block effect)
- **75-99%:** 3/4 criteria met (good pixelation with minor issues)
- **50-74%:** 2/4 criteria met (partial pixelation but weak effect)
- **0-49%:** <2 criteria met (pixelation not successfully applied)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure