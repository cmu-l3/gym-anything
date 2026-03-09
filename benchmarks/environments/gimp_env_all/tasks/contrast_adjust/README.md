# GIMP Contrast Adjustment Task (`contrast_adjust@1`)

## Overview

This task tests an agent's ability to use GIMP's contrast adjustment controls to enhance an image's tonal range. The agent must navigate to the Brightness-Contrast dialog, increase the contrast value to make the image more vivid with stronger differences between light and dark areas, and apply the adjustment. This represents one of the most fundamental image enhancement operations in digital photography and design.

## Rationale

**Why this task is valuable:**
- **Essential Enhancement Tool:** Contrast adjustment is one of the primary operations in photo editing workflows
- **Histogram Understanding:** Builds intuition about tonal distribution and dynamic range
- **Visual Assessment:** Requires evaluating before/after image quality
- **Menu Navigation:** Reinforces familiarity with GIMP's color adjustment menu system
- **Foundation Operation:** Establishes concepts needed for more advanced adjustments (curves, levels)
- **Universal Application:** Used across photography, design, document scanning, and content creation

**Skill Progression:** This task pairs naturally with brightness adjustment as complementary tonal controls, representing fundamental image correction skills.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Colors → Brightness-Contrast`)
- **Dialog Interaction:** Work with slider-based adjustment dialogs
- **Slider Manipulation:** Drag or click slider controls to adjust numeric values
- **Value Entry:** Optionally enter specific numeric values directly
- **Real-time Preview:** Observe live preview of changes while adjusting
- **Change Application:** Apply adjustments using OK/Apply buttons

### B. GIMP Knowledge
- **Color Adjustment System:** Understand GIMP's color and tone adjustment tools
- **Brightness vs. Contrast:** Distinguish between brightness (overall lightness) and contrast (tonal separation)
- **Contrast Behavior:** Know that increasing contrast makes lights lighter and darks darker
- **Preview System:** Understand GIMP's real-time preview functionality
- **Dialog Workflow:** Know how to navigate, adjust, and apply changes in adjustment dialogs
- **Value Ranges:** Understand typical contrast adjustment ranges (-100 to +100)

### C. Task-Specific Skills
- **Tonal Assessment:** Evaluate whether an image needs more or less contrast
- **Visual Judgment:** Determine appropriate contrast level without over-processing
- **Before/After Comparison:** Mentally compare original and adjusted images
- **Quality Control:** Recognize when contrast adjustment improves vs. degrades image quality
- **Clipping Awareness:** Understand that excessive contrast can lose detail in highlights/shadows

## Task Steps

### 1. Initial Image Assessment
- Examine the landscape/portrait image that opens automatically in GIMP
- Evaluate the current tonal range and identify whether it appears flat or dull
- Note areas that might benefit from increased tonal separation

### 2. Navigate to Contrast Adjustment
- Click on "Colors" in the menu bar to open the Colors menu
- Locate and click on "Brightness-Contrast" to open the adjustment dialog
- Observe the slider controls and current values (both typically at 0)

### 3. Access Contrast Control
- In the Brightness-Contrast dialog, locate the "Contrast" slider
- Note that it's separate from the "Brightness" slider above it
- Observe the current contrast value (0 = no adjustment)

### 4. Increase Contrast
- Drag the Contrast slider to the right to increase contrast (typically +20 to +40)
- Alternatively, type a numeric value directly into the contrast field
- Observe the real-time preview showing enhanced tonal separation

### 5. Evaluate the Adjustment
- Compare the preview with the original image
- Ensure the adjustment enhances the image without creating harsh or unnatural results
- Verify that important details are preserved in both light and dark areas

### 6. Apply the Contrast Adjustment
- Click "OK" button to apply the contrast adjustment
- Observe that the dialog closes and the adjustment is permanently applied
- Verify the image now has more vivid, distinct tones

### 7. Final Quality Check
- Examine the adjusted image for overall improvement
- Confirm that the image appears more vibrant without loss of detail
- Ensure no extreme clipping or posterization occurred

### 8. Automatic Export
- The post-task hook will automatically export the result as "enhanced_contrast.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **statistical contrast analysis** to quantitatively measure tonal range enhancement:

### A. Contrast Metric Calculation
- **Standard Deviation Analysis:** Measures pixel intensity spread as primary contrast indicator
- **Histogram Distribution:** Analyzes tonal distribution across the full intensity range
- **Dynamic Range Assessment:** Calculates the effective range of intensities present
- **Mathematical Precision:** Uses NumPy for accurate statistical computation

### B. Contrast Increase Validation
- **Relative Improvement:** Compares contrast metrics between original and result images
- **Threshold Validation:** Requires minimum 10% increase in standard deviation
- **Reasonable Bounds:** Ensures contrast increase is significant but not excessive (10-80%)
- **Natural Appearance:** Validates that adjustment remains within realistic parameters

### C. Quality Preservation
- **Clipping Detection:** Checks for excessive loss of highlight/shadow detail
- **Histogram Shape:** Ensures tonal distribution remains smooth without gaps
- **Overall Brightness:** Verifies that overall brightness wasn't dramatically altered
- **Detail Retention:** Confirms image structure and features remain intact

### D. Change Validation
- **Modification Verification:** Confirms the image was actually altered from original
- **Direction Validation:** Ensures contrast was increased, not decreased
- **Completeness Check:** Verifies entire image was processed uniformly

### Verification Checklist
- ✅ **Contrast Increased:** Standard deviation increased by at least 10% from original
- ✅ **Reasonable Range:** Contrast increase is between 10% and 80% (not excessive)
- ✅ **Quality Maintained:** No extreme clipping (less than 5% of pixels at 0 or 255)
- ✅ **Image Modified:** Clear statistical differences detected from original

### Scoring System
- **100%:** Excellent contrast enhancement (15-50% increase) with perfect quality preservation
- **75-99%:** Good contrast increase with minor quality concerns
- **50-74%:** Adequate contrast adjustment but with notable issues
- **0-49%:** Insufficient contrast increase or quality problems

**Pass Threshold:** 75% (requires meaningful contrast increase with quality preservation)

### Statistical Analysis Details