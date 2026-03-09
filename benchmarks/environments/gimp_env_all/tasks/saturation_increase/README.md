# GIMP Saturation Increase Task (`saturation_increase@1`)

## Overview

This task tests an agent's ability to use GIMP's color adjustment tools to enhance the vibrancy and intensity of colors in an image. The agent must navigate to the Hue-Saturation dialog, increase the saturation value to make colors more vivid and "pop," and ensure the enhancement is applied correctly. This represents one of the most common color corrections in photography and digital content creation.

## Rationale

**Why this task is valuable:**
- **Color Enhancement Mastery:** Introduces GIMP's fundamental color adjustment capabilities beyond basic brightness
- **Photography Workflow:** Tests understanding of common photo editing operations used to improve visual appeal
- **HSV Color Model:** Builds understanding of hue-saturation-value color space concepts distinct from RGB
- **Slider Interaction:** Develops skills in continuous parameter adjustment with real-time visual feedback
- **Real-world Application:** Extremely common in social media, photography, marketing, and design workflows ("Instagram-style" enhancement)
- **Visual Judgment:** Requires balancing enhancement with natural appearance

**Skill Progression:** This task builds on basic color understanding while introducing parametric adjustment controls, preparing agents for more complex color grading workflows.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Access `Colors → Hue-Saturation` through multi-level menu system
- **Dialog Interaction:** Work with the Hue-Saturation adjustment dialog interface
- **Slider Manipulation:** Adjust saturation slider by dragging or entering numeric values
- **Preview Monitoring:** Watch real-time preview to assess appropriate enhancement level
- **Value Input:** Either drag slider or type numeric value for precise control
- **Change Application:** Apply changes using OK button or Enter key

### B. GIMP Knowledge
- **Color Adjustment System:** Understand GIMP's Colors menu organization and capabilities
- **Hue-Saturation Dialog:** Navigate the HSV adjustment interface and its controls
- **Saturation Concept:** Understand that saturation controls color intensity/vibrancy, independent of lightness
- **Master Channel:** Know that adjusting "Master" channel affects all colors uniformly
- **Preview Functionality:** Utilize real-time preview to see changes before committing
- **Parameter Ranges:** Understand saturation adjustment ranges (typically -100 to +100)

### C. Task-Specific Skills
- **Color Enhancement Judgment:** Assess appropriate level of saturation increase for the image
- **Natural Balance:** Avoid over-saturation that makes images look unnatural, garish, or posterized
- **Visual Assessment:** Recognize when colors appear more vibrant and visually appealing
- **Photography Principles:** Understand common photo editing goals for making images "pop"
- **Before/After Comparison:** Mentally compare enhanced result with original appearance

## Task Steps

### 1. Initial Image Assessment
- Examine the landscape or nature image that opens automatically in GIMP
- Observe the current color saturation and identify that colors could be more vibrant
- Note the variety of colors present (sky, foliage, objects)

### 2. Access Color Adjustment Menu
- Navigate to `Colors` in the menu bar to open the Colors menu
- Locate and click on `Hue-Saturation` in the submenu

### 3. Verify Dialog and Channel
- Wait for the Hue-Saturation dialog to open
- Confirm that "Master" channel is selected (affects all colors uniformly)

### 4. Increase Saturation
- Locate the Saturation slider in the middle section of the dialog
- Drag the slider to the right to increase saturation (recommended: +25 to +35)
- Monitor the preview window to see real-time effect on image colors
- Aim for vibrant, "punchy" colors that still look natural

### 5. Apply Enhancement
- Click "OK" button to apply the saturation increase
- Observe that colors in the image now appear noticeably more vibrant and intense

### 6. Visual Verification
- Visually confirm that colors are more vivid than the original
- Check that blues are bluer, greens are greener, reds are redder, etc.

### 7. Automatic Export
- The post-task hook will automatically export the result as "vibrant_colors.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **HSV color space mathematical analysis** to objectively measure saturation changes:

### A. HSV Color Space Analysis
- **Color Space Conversion:** Converts both original and result images from RGB to HSV color space
- **Saturation Channel Extraction:** Isolates the S (saturation) channel for independent analysis
- **Statistical Measurement:** Calculates mean saturation values across all pixels
- **Change Quantification:** Measures the absolute and relative increase in average saturation

### B. Saturation Increase Validation
- **Meaningful Enhancement:** Verifies saturation increased by at least 15% relative to original mean
- **Reasonable Bounds:** Ensures saturation didn't increase excessively (not more than 80% increase)
- **Direction Correctness:** Confirms saturation increased (not decreased or unchanged)
- **Statistical Significance:** Uses thresholds that represent visually perceptible changes

### C. Quality Preservation
- **No Clipping:** Checks that saturation values don't hit maximum (255) for more than 5% of pixels
- **Distribution Preservation:** Ensures enhancement maintained reasonable color distribution
- **Over-saturation Detection:** Identifies unnatural "neon" or "garish" appearance
- **Detail Maintenance:** Verifies that color enhancement didn't destroy image structure

### D. Change Confirmation
- **Image Modified:** Confirms clear statistical differences from original image
- **Sufficient Magnitude:** Ensures change is visually perceptible (minimum 15% increase)
- **Appropriate Range:** Validates enhancement falls within professional editing standards

### Verification Checklist
- ✅ **Saturation Increased:** Mean saturation increased by at least 15% from original
- ✅ **Reasonable Enhancement:** Saturation increase is between 15% and 80% (not excessive)
- ✅ **No Over-saturation:** Less than 5% of pixels at maximum saturation (avoiding clipping)
- ✅ **Sufficient Change:** Mean saturation absolute increase is at least 10 points (0-255 scale)

### Scoring System
- **100%:** All 4 criteria met (excellent, professional saturation enhancement)
- **75-99%:** 3/4 criteria met (good enhancement with minor issues)
- **50-74%:** 2/4 criteria met (partial success but needs improvement)
- **0-49%:** <2 criteria met (task not successfully completed)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure