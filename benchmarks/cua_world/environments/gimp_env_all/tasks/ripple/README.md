# GIMP Ripple Effect Task (`ripple@1`)

## Overview

This task tests an agent's ability to apply GIMP's Ripple distortion filter to create a water-like wave effect on an image. The agent must navigate to the Ripple filter, configure its parameters appropriately, and apply the effect to transform the image with a characteristic wave distortion pattern. This represents a fundamental artistic filter operation commonly used for creative distortion and water-simulation effects.

## Rationale

**Why this task is valuable:**
- **Distortion Filter Introduction:** Introduces GIMP's distortion filter category in a straightforward way
- **Creative Effects:** Tests ability to apply artistic transformations that dramatically alter image appearance
- **Parameter Understanding:** Requires working with filter dialogs and adjusting effect intensity
- **Visual Feedback:** Provides clear, immediate visual confirmation of successful application
- **Real-world Relevance:** Used in digital art, water effects, creative photography, and abstract design
- **Foundation for Complex Effects:** Builds understanding of GIMP's extensive filter system

**Skill Progression:** This task is similar in difficulty to applying blur, sharpen, or other basic filters, making it ideal for agents learning GIMP's filter workflow.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through nested menu structure (`Filters → Distorts → Ripple`)
- **Dialog Management:** Work with filter preview dialogs and parameter controls
- **Parameter Adjustment:** Modify amplitude and wavelength sliders to control effect intensity
- **Preview Interpretation:** Understand preview window to assess effect before applying
- **Confirmation Actions:** Apply filter using OK/Apply buttons
- **Value Input:** Optionally enter specific numeric values for precise control

### B. GIMP Knowledge
- **Filter System:** Understand GIMP's comprehensive filter architecture and organization
- **Distortion Category:** Know where geometric distortion effects are located in the menu
- **Filter Dialogs:** Navigate the standard GIMP filter dialog interface with preview
- **Parameter Effects:** Understand how amplitude and wavelength affect the ripple appearance
- **Preview System:** Use the filter preview to evaluate effects before committing
- **Processing Time:** Recognize that filters may take time to process and apply

### C. Task-Specific Skills
- **Wave Pattern Understanding:** Recognize what ripple/wave effects look like visually
- **Parameter Selection:** Choose appropriate values for noticeable but not excessive distortion
- **Effect Assessment:** Evaluate whether the ripple effect has been successfully applied
- **Quality Balance:** Balance effect intensity with maintaining image recognizability
- **Visual Analysis:** Confirm that wave-like distortions are present throughout the image

## Task Steps

### 1. Initial Image Examination
- Examine the photo image that opens automatically in GIMP
- Note the image content and areas where ripple effects will be most visible
- Mentally prepare for the expected wave distortion pattern

### 2. Navigate to Ripple Filter
- Click on "Filters" in the menu bar to open the Filters menu
- Hover over or click "Distorts" to open the distortion filter submenu
- Locate "Ripple" in the list of distortion filters

### 3. Open Ripple Dialog
- Click on "Ripple" to open the Ripple filter dialog
- Observe the filter dialog with parameter controls and preview window
- Note the default parameter values (typically Amplitude: 10-20, Wavelength: 10-20)

### 4. Adjust Ripple Parameters (Optional)
- View the preview to see how the default settings affect the image
- Optionally adjust Amplitude slider (controls wave height/intensity)
- Optionally adjust Wavelength slider (controls wave frequency/spacing)
- Aim for noticeable but not extreme distortion (Amplitude 15-30 recommended)

### 5. Apply Ripple Effect
- Click "OK" or "Apply" button to apply the ripple distortion
- Wait for GIMP to process the effect (may take a few seconds)
- Observe the wave-like distortion applied across the entire image

### 6. Verify Effect Application
- Visually confirm that the image now shows wave-like distortions
- Check that the ripple pattern is visible throughout the image
- Ensure the image hasn't been corrupted or excessively distorted

### 7. Automatic Export
- The post-task hook will automatically export the result as "ripple_effect.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **distortion detection and wavelet-like pattern analysis** to validate ripple application:

### A. Distortion Magnitude Analysis
- **Pixel Displacement Detection:** Calculates pixel-wise differences between original and result
- **Structural Change Measurement:** Uses SSIM (Structural Similarity Index) to quantify distortion
- **Distortion Threshold:** Verifies SSIM is sufficiently low (< 0.85) indicating substantial transformation
- **Change Distribution:** Ensures distortion is distributed across the image, not localized

### B. Wave Pattern Detection
- **Frequency Analysis:** Detects periodic patterns characteristic of wave distortions
- **Edge Curvature:** Analyzes whether previously straight edges now show wave-like curves
- **Gradient Flow:** Examines image gradients for sinusoidal-like patterns
- **Spatial Consistency:** Verifies distortion pattern has wave-like regularity

### C. Quality Preservation
- **Content Recognition:** Ensures image content remains recognizable despite distortion
- **Excessive Distortion Check:** Verifies distortion isn't so extreme that content is lost
- **Artifact Detection:** Checks for processing artifacts or corruption
- **Color Preservation:** Confirms colors remain intact, only geometry is distorted

### D. Mathematical Validation
- **Standard Deviation Analysis:** Measures increased pixel position variance
- **Gradient Magnitude:** Detects changes in edge orientations and positions
- **Histogram Comparison:** Verifies color histogram remains similar (geometric change, not color)
- **Local Variance:** Checks for increased local pixel displacement variance

### Verification Checklist
- ✅ **Significant Distortion:** SSIM < 0.85 between original and result (substantial geometric change)
- ✅ **Distributed Effect:** Distortion present across multiple image regions (>20% of image)
- ✅ **Pattern Detection:** Evidence of wave-like periodic distortion patterns
- ✅ **Content Preserved:** Image remains recognizable with SSIM > 0.40 (not completely destroyed)

### Scoring System
- **100%:** All criteria met with clear ripple effect and appropriate intensity
- **75-99%:** Good ripple effect with minor issues in distribution or intensity
- **50-74%:** Noticeable distortion but weak or inconsistent ripple pattern
- **0-49%:** Insufficient distortion or incorrect filter applied

**Pass Threshold:** 75% (requires clear ripple effect with proper distribution)

## Technical Implementation

### Files Structure