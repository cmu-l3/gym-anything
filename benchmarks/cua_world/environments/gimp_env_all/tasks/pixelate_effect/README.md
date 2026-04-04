# GIMP Pixelate Effect Task (`pixelate_effect@1`)

## Overview

This task tests an agent's ability to apply GIMP's pixelate filter to create a blocky, mosaic-style effect on an image. The agent must navigate to the appropriate filter menu, configure the pixelate parameters to create visible block patterns, and apply the transformation. This represents a fundamental artistic filter operation commonly used for privacy protection (face obscuring) and creative stylization.

## Rationale

**Why this task is valuable:**
- **Filter System Introduction:** Introduces GIMP's extensive filter library in a simple, visual way
- **Privacy Applications:** Teaches a practical technique for obscuring sensitive information in images
- **Artistic Stylization:** Provides foundation for retro gaming aesthetics and digital art effects
- **Parameter Understanding:** Builds familiarity with filter dialogs and parameter adjustment
- **Immediate Visual Feedback:** Creates obvious, easy-to-recognize transformation patterns
- **Common Use Case:** Widely used in social media, journalism, and content creation for privacy

**Skill Progression:** This task serves as an excellent introduction to GIMP's filter system, requiring only basic menu navigation and parameter adjustment while producing dramatic, easily verifiable results.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through nested filter menus (`Filters → Blur → Pixelize`)
- **Dialog Management:** Work with filter parameter dialogs
- **Numeric Input:** Adjust pixel block size using sliders or direct input
- **Preview Understanding:** Interpret real-time preview to assess effect intensity
- **Parameter Adjustment:** Modify settings to achieve desired visual effect
- **Dialog Confirmation:** Apply filter changes using OK/Apply buttons

### B. GIMP Knowledge
- **Filter Menu System:** Understand the organization of GIMP's extensive filter library
- **Blur Category Familiarity:** Recognize that pixelate is categorized under Blur filters
- **Dialog Interaction:** Work with filter parameter dialogs and preview windows
- **Non-destructive Preview:** Use preview checkbox to see effects before committing
- **Parameter Effects:** Understand how block size affects the final visual result
- **Filter Application:** Know that filters modify the active layer directly

### C. Task-Specific Skills
- **Visual Effect Assessment:** Recognize when pixelation is clearly visible and effective
- **Block Size Judgment:** Choose appropriate pixel block size for visible effect
- **Quality vs. Effect Balance:** Balance recognizability with pixelation strength
- **Preview Interpretation:** Use preview to adjust parameters before final application
- **Artistic Judgment:** Determine when the effect achieves the desired aesthetic

## Task Steps

### 1. Initial Image Examination
- Examine the portrait or landscape image that opens automatically in GIMP
- Identify the subject and overall composition
- Plan appropriate pixelation strength for visible effect

### 2. Navigate to Pixelize Filter
- Click on "Filters" in the menu bar
- Navigate to "Blur" submenu
- Locate and click on "Pixelize" option

### 3. Wait for Filter Dialog
- Observe the Pixelize dialog opening
- Note the preview checkbox and parameter controls
- See initial preview with default settings

### 4. Enable Preview (if not automatic)
- Check the "Preview" checkbox if not already enabled
- Observe real-time effect preview in the image window
- Understand that preview shows effect before committing

### 5. Adjust Pixel Block Size
- Locate the "Pixel Width" and "Pixel Height" parameters
- Increase values to create visible blocky effect (typically 10-20 pixels)
- Use slider or direct numeric input to adjust values
- Observe preview updating with each change

### 6. Verify Effect Strength
- Assess whether pixelation is clearly visible in preview
- Ensure block pattern is distinct and recognizable
- Confirm the effect meets the task requirements (visible but not extreme)

### 7. Apply Pixelation
- Click "OK" button to apply the filter
- Wait for GIMP to process the entire image
- Observe the final pixelated result on the canvas

### 8. Automatic Export
- The post-task hook will automatically export the result as "pixelated_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **block pattern detection and edge analysis** to identify pixelation:

### A. Edge Density Analysis
- **Edge Detection:** Uses Sobel or Canny edge detection to identify image edges
- **Grid Pattern Detection:** Analyzes edge patterns for regular horizontal/vertical lines
- **Baseline Comparison:** Compares edge density with original image
- **Pattern Recognition:** Identifies characteristic pixelate filter signature (regular grid)

### B. Block Pattern Frequency Analysis
- **Horizontal Line Detection:** Scans for regular horizontal edge patterns
- **Vertical Line Detection:** Scans for regular vertical edge patterns
- **Grid Spacing Analysis:** Measures spacing between detected grid lines
- **Regularity Assessment:** Validates that patterns are evenly spaced (characteristic of pixelation)

### C. Visual Degradation Measurement
- **Detail Loss Analysis:** Measures reduction in high-frequency image details
- **Smoothness Assessment:** Quantifies increase in flat color regions
- **Block Size Estimation:** Estimates pixel block size from pattern analysis
- **Threshold Validation:** Ensures pixelation is strong enough to be clearly visible

### D. Statistical Image Comparison
- **Color Palette Reduction:** Measures reduction in unique color count
- **Variance Analysis:** Compares local variance before/after (pixelation reduces local variance)
- **Histogram Changes:** Analyzes how color distribution changes with pixelation
- **Perceptual Difference:** Quantifies overall visual change from original

### Verification Checklist
- ✅ **Block Pattern Detected:** Regular grid pattern identified through edge analysis
- ✅ **Sufficient Pixelation:** Block size ≥8 pixels (clearly visible blocky effect)
- ✅ **Edge Regularity:** Horizontal and vertical edges show grid-like regularity
- ✅ **Detail Reduction:** Significant decrease in image detail (≥30% detail loss)
- ✅ **Image Modified:** Clear statistical differences from original image

### Scoring System
- **100%:** Strong pixelation with clear block patterns and all criteria met
- **75-99%:** Good pixelation with detectable blocks and 4/5 criteria met
- **50-74%:** Moderate pixelation with 3/5 criteria met
- **0-49%:** Weak or absent pixelation with <3 criteria met

**Pass Threshold:** 75% (requires clear, visible pixelation effect)

## Technical Implementation

### Files Structure