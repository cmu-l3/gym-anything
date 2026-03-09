# GIMP Add Noise Task (`add_noise@1`)

## Overview

This task tests an agent's ability to use GIMP's noise generation filters to add texture and grain to an image. The agent must navigate to the RGB Noise filter, configure appropriate noise parameters, and apply the effect to simulate film grain or add visual texture. This represents a common technique in digital photography and artistic image processing.

## Rationale

**Why this task is valuable:**
- **Texture Generation:** Introduces procedural texture and noise generation concepts
- **Filter System Mastery:** Tests navigation of GIMP's extensive filter system
- **Parameter Control:** Requires understanding and adjusting filter parameters
- **Artistic Technique:** Simulates film grain, adds vintage effects, or creates texture
- **Real-world Application:** Common in photography (film grain), design (texture), and digital art
- **Foundation for Advanced Effects:** Builds understanding needed for more complex procedural effects

**Skill Progression:** This task introduces parametric filters, bridging simple menu operations with adjustable effect application.

## Skills Required

### A. Interaction Skills
- **Nested Menu Navigation:** Navigate through `Filters → Noise → RGB Noise`
- **Dialog Interaction:** Work with filter parameter dialogs
- **Slider Manipulation:** Adjust noise intensity using slider controls
- **Preview Assessment:** Use preview window to judge appropriate noise levels
- **Dialog Confirmation:** Apply filter changes using OK/Apply buttons

### B. GIMP Knowledge
- **Filter System Organization:** Understand GIMP's hierarchical filter menu structure
- **Noise Filter Categories:** Distinguish between RGB Noise, HSV Noise, and other noise types
- **Parameter Effects:** Understand how noise intensity affects image appearance
- **Non-destructive Preview:** Use preview to assess changes before applying
- **Filter Application:** Know that filters apply directly to active layer

### C. Task-Specific Skills
- **Noise Level Judgment:** Determine appropriate noise intensity for the desired effect
- **Visual Balance:** Add noticeable noise without overwhelming the original image
- **Texture Understanding:** Recognize how noise adds grain and texture
- **Quality Assessment:** Ensure noise adds desired effect without excessive degradation
- **Film Grain Simulation:** Understand how noise mimics analog photography characteristics

## Task Steps

### 1. Initial Image Assessment
- Examine the clean image that opens automatically in GIMP
- Identify areas where noise will be most visible (smooth gradients, solid colors)
- Plan appropriate noise intensity (noticeable but not overwhelming)

### 2. Navigate to Noise Filter
- Click on "Filters" in the menu bar
- Hover over "Noise" to open the noise filters submenu
- Locate "RGB Noise" in the submenu

### 3. Open RGB Noise Dialog
- Click on "RGB Noise" to open the filter dialog
- Observe the parameter controls and preview window
- Note default settings (typically 0.20 for RGB channels)

### 4. Configure Noise Parameters
- Adjust the noise sliders to add visible texture
- Set noise intensity between 0.20 and 0.40 for noticeable effect
- Can adjust individual Red, Green, Blue channels or use linked values
- Keep "Independent RGB" checked for natural color noise

### 5. Preview Assessment
- Enable preview checkbox to see effect in real-time
- Adjust parameters until noise is clearly visible but not excessive
- Aim for subtle film-grain appearance rather than overwhelming static

### 6. Apply Noise Filter
- Click "OK" to apply the noise effect to the image
- Wait for GIMP to process the filter (may take a few seconds)
- Observe the added texture and grain throughout the image

### 7. Verify Application
- Zoom in to confirm noise was successfully applied
- Check that noise is distributed across the entire image
- Ensure the effect maintains reasonable image quality

### 8. Automatic Export
- The post-task hook will automatically export the result as "noisy_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **statistical variance analysis** to detect and quantify added noise:

### A. Noise Variance Measurement
- **Standard Deviation Analysis:** Calculates pixel intensity variation before and after
- **Channel-wise Variance:** Measures noise across Red, Green, and Blue channels independently
- **Spatial Distribution:** Ensures noise is evenly distributed, not localized
- **Increase Detection:** Confirms variance increased significantly after noise addition

### B. Texture Metrics
- **Local Variance Analysis:** Measures fine-detail variation in local image regions
- **High-frequency Content:** Uses gradient analysis to detect added texture
- **Smoothness Reduction:** Quantifies decrease in smooth, uniform regions
- **Texture Increase:** Validates that image has more fine-grained detail

### C. Quality Preservation
- **Overall Structure Maintenance:** Ensures major image features remain recognizable
- **Color Integrity:** Validates that color distribution remains reasonable
- **Contrast Preservation:** Confirms overall contrast wasn't destroyed by noise
- **Excessive Noise Detection:** Flags if noise is so extreme it ruins the image

### D. Mathematical Validation
- **Statistical Threshold:** Requires minimum 10-20% increase in standard deviation
- **Variance Ratio:** Compares noise variance to original image variance
- **Distribution Analysis:** Ensures noise follows expected random distribution
- **Correlation Reduction:** Validates that noise reduced pixel-to-pixel correlation (added randomness)

### Verification Checklist
- ✅ **Noise Variance Increased:** Standard deviation increased by ≥10% across all channels
- ✅ **Texture Added:** Local variance measurements show increased fine detail
- ✅ **Image Modified:** Clear statistical differences detected from original
- ✅ **Quality Reasonable:** Image remains recognizable, noise not excessive (variance increase <200%)

### Scoring System
- **100%:** Perfect noise application with 10-50% variance increase, excellent texture
- **75-99%:** Good noise addition with appropriate parameters, minor issues
- **50-74%:** Noise present but too weak or too strong
- **0-49%:** Insufficient noise added or image quality destroyed

**Pass Threshold:** 75% (requires noticeable, appropriate noise addition)

## Technical Implementation

### Files Structure