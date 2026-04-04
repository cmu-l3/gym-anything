# GIMP Despeckle (Noise Reduction) Task (`despeckle@1`)

## Overview

This task tests an agent's ability to use GIMP's noise reduction filter to clean up a noisy or speckled image. The agent must navigate to the Despeckle filter, understand its purpose, apply it with appropriate settings, and produce a cleaner version of the input image. This represents a fundamental image enhancement operation used in photography, scanning, and digital restoration workflows.

## Rationale

**Why this task is valuable:**
- **Essential Enhancement:** Noise reduction is a critical skill in photography post-processing and image restoration
- **Filter System Introduction:** Introduces GIMP's "Enhance" filter category for image quality improvement
- **Quality Assessment:** Tests understanding of what constitutes image improvement vs. degradation
- **Real-world Application:** Common in processing scanned documents, low-light photos, and digital camera images
- **Practical Utility:** Frequently used before other operations like printing or further editing
- **Professional Workflow:** Standard step in professional photo editing and document digitization

**Skill Progression:** This task bridges basic operations with image quality assessment, teaching agents to evaluate and improve image characteristics rather than just apply geometric transformations.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested filter menus (`Filters → Enhance → Despeckle`)
- **Dialog Interaction:** Work with the Despeckle filter dialog and its preview
- **Parameter Understanding:** Comprehend filter parameters and their effects
- **Preview Assessment:** Evaluate the preview to judge filter effectiveness
- **Confirmation Actions:** Apply filter changes using OK button

### B. GIMP Knowledge
- **Filter System:** Understand GIMP's filter organization and the Enhance category
- **Despeckle Purpose:** Know that despeckle reduces noise while preserving edges
- **Filter Parameters:** Understand radius, black level, white level settings (if available)
- **Preview Mechanism:** Know how to use filter preview for before/after comparison
- **Non-destructive Preview:** Understand that preview shows effect before committing
- **Filter Application:** Know that clicking OK applies the filter to the entire image or selection

### C. Task-Specific Skills
- **Noise Recognition:** Identify noisy or speckled regions in images
- **Quality Judgment:** Assess whether despeckle improves image quality
- **Parameter Selection:** Choose appropriate settings that reduce noise without over-smoothing
- **Edge Preservation:** Understand the balance between noise reduction and detail preservation
- **Verification Skills:** Recognize when an image has been successfully cleaned

## Task Steps

### 1. Initial Image Analysis
- Examine the noisy image that opens automatically in GIMP
- Identify areas with visible noise, speckles, or grain
- Note important details and edges that should be preserved
- Assess overall noise level and type

### 2. Navigate to Despeckle Filter
- Click on "Filters" in the menu bar to open the Filters menu
- Hover over or click "Enhance" to open the enhancement submenu
- Locate "Despeckle" in the list of enhancement filters

### 3. Open Despeckle Dialog
- Click on "Despeckle" to open the filter dialog
- Wait for the dialog window to appear with preview
- Observe the default settings and preview

### 4. Evaluate Preview
- Examine the preview pane showing the effect of despeckle
- Compare the preview with the original to assess noise reduction
- Verify that important edges and details are preserved
- Check that the filter is effectively reducing visible speckles

### 5. Adjust Settings (if needed)
- If the default settings are insufficient, adjust parameters
- Common adjustments: radius (affects the area analyzed), threshold values
- Balance between noise reduction and detail preservation
- Use preview to evaluate changes in real-time

### 6. Apply Despeckle Filter
- Once satisfied with the preview, click "OK" to apply the filter
- Wait for GIMP to process the entire image
- Observe the progress indicator if the image is large

### 7. Verify Results
- Examine the final result to confirm noise reduction
- Check that speckles and noise have been reduced
- Verify that important image details remain intact
- Confirm overall image quality has improved

### 8. Automatic Export
- The post-task hook will automatically export the result as "despeckled_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **statistical noise analysis** to measure noise reduction effectiveness:

### A. Noise Level Measurement
- **Local Variance Analysis:** Calculates local variance in small image regions as a proxy for noise
- **Standard Deviation Comparison:** Measures pixel value variation before and after filtering
- **High-frequency Content:** Analyzes high-frequency components that indicate noise vs. detail
- **Multi-region Sampling:** Tests multiple image regions to ensure consistent noise reduction

### B. Noise Reduction Metrics
- **Variance Reduction:** Confirms that local variance decreased (indicating less noise)
- **Smoothness Increase:** Measures that the image is more uniform in previously noisy regions
- **Noise Threshold:** Ensures noise reduction is significant (typically 10-40% reduction)
- **Quality Preservation:** Verifies that overall image structure remains recognizable

### C. Edge Preservation Analysis
- **Edge Detection Comparison:** Ensures important edges are preserved after despeckle
- **Detail Retention:** Confirms that the filter didn't over-smooth and remove legitimate details
- **Structure Preservation:** Uses structural similarity metrics to verify image integrity
- **Balance Assessment:** Ensures noise reduction didn't cause excessive blur

### D. Change Detection and Validation
- **Modification Verification:** Confirms the image was actually processed (not unchanged)
- **Appropriate Change Magnitude:** Ensures changes are significant enough to represent filtering
- **Direction Validation:** Confirms changes represent noise reduction, not noise addition
- **Quality Improvement:** Validates that the filtering improved rather than degraded the image

### Verification Checklist
- ✅ **Noise Reduced:** Local variance decreased by at least 10% compared to original
- ✅ **Image Modified:** Clear statistical differences detected from original image
- ✅ **Quality Maintained:** Image structure and important features preserved (SSIM ≥ 0.75)
- ✅ **Appropriate Processing:** Changes consistent with despeckle operation (smoothing, not sharpening)

### Scoring System
- **100%:** Excellent noise reduction with strong detail preservation (all criteria strongly met)
- **75-99%:** Good noise reduction with adequate detail preservation (3-4 criteria met)
- **50-74%:** Moderate noise reduction but with quality concerns (2 criteria met)
- **0-49%:** Insufficient noise reduction or excessive quality loss (<2 criteria met)

**Pass Threshold:** 75% (requires successful noise reduction while maintaining image quality)

## Technical Implementation

### Files Structure