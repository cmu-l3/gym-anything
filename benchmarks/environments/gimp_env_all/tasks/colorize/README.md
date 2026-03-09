# GIMP Colorize Task (`colorize@1`)

## Overview

This task tests an agent's ability to use GIMP's Colorize tool to convert a color image into a monochromatic tinted version. The agent must navigate to the Colorize dialog, adjust the hue parameter to create a specific color tone (e.g., sepia or cyan), and apply the effect. This represents a fundamental artistic color treatment commonly used for mood creation, vintage effects, and stylistic image processing in photography and design.

## Rationale

**Why this task is valuable:**
- **Artistic Color Treatment:** Introduces creative color manipulation distinct from basic adjustments or filters
- **Monochromatic Workflow:** Tests understanding of single-hue color schemes and their applications
- **HSL Color Space:** Builds intuition about hue-based color transformation
- **Common Professional Effect:** Widely used in photography (sepia tones), social media (color grading), and design (mood creation)
- **Simple Single-Dialog Operation:** Clean workflow with clear parameters, ideal for learning
- **Distinctive Visual Result:** Creates dramatic, easily recognizable transformations

**Skill Progression:** Bridges basic color adjustments (brightness/contrast, saturation) with advanced selective color manipulation (color replacement, channel mixing), teaching fundamental color space concepts through practical application.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Colors → Colorize`)
- **Dialog Management:** Work with the Colorize dialog interface
- **Slider Manipulation:** Adjust hue slider to achieve target color tone
- **Preview Interpretation:** Understand real-time preview showing color transformation
- **Parameter Fine-tuning:** Optionally adjust saturation and lightness for refinement
- **Confirmation Actions:** Apply changes using OK button

### B. GIMP Knowledge
- **Colorize vs. Other Tools:** Understand how Colorize differs from Hue-Saturation (which preserves color variety) or Desaturate (which removes color entirely)
- **Monochromatic Concept:** Know that Colorize converts all colors to variations of a single hue
- **HSL Color Model:** Understand Hue (color tone), Saturation (intensity), Lightness (brightness) parameters
- **Luminosity Preservation:** Recognize that Colorize maintains original brightness relationships and detail
- **Color Menu System:** Navigate GIMP's extensive color manipulation menu hierarchy
- **Non-destructive Preview:** Use dialog preview to assess changes before committing

### C. Task-Specific Skills
- **Target Hue Selection:** Choose appropriate hue value for desired artistic effect (e.g., ~30° for warm sepia, ~180° for cool cyan)
- **Saturation Balance:** Understand how saturation affects subtlety vs. intensity of the effect
- **Mood Creation:** Recognize emotional/aesthetic impact of different color tones
- **Effect Assessment:** Evaluate whether the colorized result achieves the intended artistic vision
- **Tonal Preservation:** Ensure original image detail and contrast remain visible through colorization

## Task Steps

### 1. Initial Image Analysis
- Examine the color photograph that opens automatically in GIMP (e.g., landscape scene)
- Note the current diverse color palette and tonal range
- Prepare to convert this to a single-hue monochromatic treatment

### 2. Access Colorize Dialog
- Navigate to `Colors → Colorize` in the menu bar
- Wait for the Colorize dialog to open
- Observe the initial preview showing default colorization

### 3. Adjust Hue for Sepia Tone
- Locate the Hue slider in the Colorize dialog
- Adjust the hue to approximately 30-35° (warm brown/orange for sepia effect)
- Observe the real-time preview transforming the image to sepia tones

### 4. Verify Saturation (Optional Check)
- Note the Saturation slider (typically defaulted to ~0.5)
- If needed, ensure saturation is sufficient for visible coloring (usually 30-60%)
- The default value should work well for most images

### 5. Verify Lightness (Optional Check)
- Note the Lightness slider (typically at 0, meaning neutral)
- Keep near 0 to preserve original brightness relationships
- Avoid adjusting unless image becomes too dark or bright

### 6. Apply Colorization
- Click "OK" button to apply the colorize effect
- Observe that the entire image now displays a sepia-tone monochromatic treatment
- Verify that original detail and contrast remain visible in the brown-toned result

### 7. Automatic Export
- The post-task hook will automatically export the result as "colorized_sepia.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **HSV color space analysis with hue uniformity detection** to confirm proper colorization:

### A. Hue Uniformity Analysis
- **HSV Conversion:** Transforms result image to HSV color space for precise hue measurement
- **Hue Distribution Mapping:** Analyzes distribution of hue values across all pixels
- **Uniformity Calculation:** Measures standard deviation of hue values (colorized images have narrow hue range)
- **Monochromatic Signature:** Expects hue std dev < 20° (compared to >60° for natural color images)

### B. Target Hue Verification
- **Predominant Hue Detection:** Identifies the median/mode hue across the image
- **Target Range Matching:** Verifies hue is within ±20° of target (30° for sepia)
- **Circular Distance Handling:** Properly calculates hue distance on circular 0-360° scale
- **Validation Masking:** Ignores very dark/bright/desaturated pixels where hue is unreliable

### C. Saturation Presence Check
- **Color Intensity Analysis:** Confirms image has significant saturation (not grayscale)
- **Saturation Mean:** Verifies mean saturation > 0.2 (on 0-1 scale)
- **Monochrome Validation:** Ensures saturation is present but uniform across image
- **Desaturate Distinction:** Differentiates colorization from accidental desaturation

### D. Luminosity Preservation
- **Brightness Correlation:** Compares value (brightness) channel between original and result
- **Tonal Structure:** Requires correlation > 0.85, indicating preserved brightness relationships
- **Detail Maintenance:** Verifies that image detail and contrast remain visible
- **No Flattening:** Ensures colorization didn't reduce image to uniform flat color

### Verification Checklist
- ✅ **Hue Uniformity:** Standard deviation of hue values < 20° (narrow monochromatic range)
- ✅ **Target Hue Achieved:** Median hue within 30 ± 20° (sepia range: 10-50°)
- ✅ **Saturation Present:** Mean saturation > 0.2 (clearly colored, not grayscale)
- ✅ **Luminosity Preserved:** Value channel correlation with original > 0.85

### Scoring System
- **100%:** All 4 criteria met (perfect colorization with correct sepia hue)
- **75-99%:** 3/4 criteria met (good colorization with minor hue deviation or reduced uniformity)
- **50-74%:** 2/4 criteria met (partial colorization or significantly incorrect hue)
- **0-49%:** <2 criteria met (colorization failed, not applied, or wrong operation used)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure