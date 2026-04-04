# GIMP Saturation Enhancement Task (`saturation_boost@1`)

## Overview

This task tests an agent's ability to use GIMP's Hue-Saturation tool to increase the color vibrancy of an image by boosting saturation levels. The agent must navigate to the color adjustment menu, increase the saturation slider to make colors more vivid and punchy, and apply the changes. This represents one of the most common photo enhancement operations used in digital photography and social media content preparation.

## Rationale

**Why this task is valuable:**
- **Essential Photo Enhancement:** Saturation adjustment is among the most frequently used color corrections in photography
- **Color Space Understanding:** Tests knowledge of HSV color model and saturation as independent from hue and brightness
- **Practical Application:** Common in social media prep, product photography, landscape enhancement, and creative editing
- **Tool Mastery:** Introduces GIMP's Hue-Saturation dialog in its most straightforward usage mode
- **Visual Judgment:** Requires understanding when colors appear more vibrant vs. over-saturated
- **Foundation Skill:** Prepares for more advanced color grading and selective color adjustments

**Skill Progression:** This task bridges basic color operations (like brightness) with more sophisticated color space manipulation, suitable for intermediate-level training.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Access `Colors → Hue-Saturation` through menu hierarchy
- **Dialog Management:** Work with the Hue-Saturation adjustment dialog interface
- **Slider Manipulation:** Adjust saturation slider to increase vividness (typically +20 to +40)
- **Preview Understanding:** Observe real-time preview of saturation changes
- **Change Application:** Apply adjustments using OK or Apply buttons
- **Value Assessment:** Judge appropriate saturation increase without over-processing

### B. GIMP Knowledge
- **Color Adjustment Menu:** Navigate GIMP's Colors menu and adjustment tools
- **Hue-Saturation Tool:** Understand the purpose and controls of the Hue-Saturation dialog
- **Saturation Concept:** Know that saturation controls color intensity/vividness independent of hue
- **Master Channel:** Understand that adjusting "Master" affects all colors uniformly
- **Slider Ranges:** Know typical saturation adjustment ranges (-100 to +100)
- **Preview System:** Understand how GIMP shows live previews of color adjustments

### C. Task-Specific Skills
- **Saturation Recognition:** Visually identify when an image has low or neutral saturation
- **Enhancement Judgment:** Determine appropriate saturation boost level for natural appearance
- **Color Vividness:** Understand the relationship between saturation and color "pop"
- **Over-saturation Awareness:** Recognize when colors become unnaturally intense
- **Real-world Application:** Know when saturation boost improves vs. degrades image quality

## Task Steps

### 1. Initial Image Assessment
- Examine the landscape or nature image that opens automatically in GIMP
- Observe the current saturation level (typically neutral or slightly muted)
- Identify areas that would benefit from increased color vividness

### 2. Access Hue-Saturation Tool
- Navigate to `Colors → Hue-Saturation` in the menu bar
- Wait for the Hue-Saturation adjustment dialog to open
- Observe the current saturation slider position (typically at 0)

### 3. Verify Master Channel Selected
- Ensure "Master" is selected in the channel dropdown
- This ensures saturation adjustment affects all colors uniformly
- Note that other options (Reds, Greens, Blues, etc.) allow selective adjustments

### 4. Increase Saturation
- Locate the Saturation slider in the middle of the dialog
- Drag the slider to the right (positive direction) to increase saturation
- Aim for approximately +25 to +35 increase for noticeable but natural enhancement
- Observe the preview showing colors becoming more vivid

### 5. Fine-tune Adjustment
- Monitor the image preview for natural appearance
- Ensure colors appear vibrant but not artificially oversaturated
- Adjust slider position if colors appear too intense or cartoon-like
- Balance enhancement with realism

### 6. Apply Changes
- Click "OK" button to apply the saturation enhancement
- Wait for GIMP to process the adjustment
- Observe that the image now displays more vibrant, punchy colors

### 7. Visual Verification
- Compare the result mentally with the original appearance
- Confirm that colors appear noticeably more vivid
- Ensure the image maintains natural appearance despite enhanced saturation

### 8. Automatic Export
- The post-task hook will automatically export the result as "vibrant_colors.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **HSV color space analysis** to mathematically measure saturation changes:

### A. Color Space Conversion
- **RGB to HSV Transformation:** Converts both original and result images to HSV color space
- **Saturation Channel Extraction:** Isolates the S (saturation) channel for analysis
- **Per-pixel Comparison:** Analyzes saturation changes across the entire image
- **Statistical Analysis:** Computes mean and median saturation values before and after

### B. Saturation Increase Measurement
- **Mean Saturation Comparison:** Calculates average saturation increase across all pixels
- **Relative Change Analysis:** Measures percentage increase in saturation levels
- **Distribution Shift:** Analyzes how the saturation histogram shifts toward higher values
- **Threshold Validation:** Ensures saturation increase is meaningful (typically ≥10% relative increase)

### C. Quality Preservation
- **Over-saturation Detection:** Checks that saturation wasn't increased excessively (clipping detection)
- **Color Integrity:** Ensures hue values remain unchanged (only saturation modified)
- **Brightness Preservation:** Verifies that brightness/value channel remains relatively stable
- **Natural Appearance:** Validates that the enhancement appears realistic

### D. Change Detection
- **Modification Verification:** Confirms the image was actually altered from the original
- **Directional Validation:** Ensures saturation increased (not decreased or unchanged)
- **Magnitude Assessment:** Checks that the change magnitude is appropriate (not too subtle or extreme)
- **Uniformity Check:** Verifies that saturation increase was applied globally (not selective regions)

### Verification Checklist
- ✅ **Saturation Increased:** Mean saturation value increased by at least 10% relative (or 0.05 absolute on 0-1 scale)
- ✅ **Meaningful Enhancement:** Clear visual difference in color vividness detected
- ✅ **Quality Maintained:** No excessive over-saturation or color clipping detected
- ✅ **Hue Preserved:** Color hues remain unchanged (adjustment targeted saturation only)

### Scoring System
- **100%:** Excellent saturation boost (15-40% increase) with natural appearance and preserved hues
- **75-99%:** Good saturation increase (10-15% or 40-60%) with minor quality issues
- **50-74%:** Minimal saturation change detected but below ideal threshold
- **0-49%:** Insufficient saturation increase or incorrect adjustment direction

**Pass Threshold:** 75% (requires meaningful saturation increase with quality preservation)

## Technical Implementation

### Files Structure