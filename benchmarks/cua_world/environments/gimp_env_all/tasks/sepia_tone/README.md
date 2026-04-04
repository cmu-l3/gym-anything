# GIMP Sepia Tone Task (`sepia_tone@1`)

## Overview

This task challenges an agent to use GIMP's color adjustment tools to transform a color photograph into a vintage sepia-toned image. The agent must convert the image to grayscale and then apply a warm brown colorization to create the characteristic vintage photography appearance. This represents a fundamental photo editing workflow used extensively in portrait photography, vintage aesthetics, and nostalgic content creation.

## Rationale

**Why this task is valuable:**
- **Classic Photo Effect:** Sepia toning is one of the most recognizable and widely-used vintage photo effects
- **Multi-step Workflow:** Combines desaturation with colorization, teaching logical operation sequencing
- **Color Theory Application:** Tests understanding of how to apply monochromatic color overlays
- **Real-world Relevance:** Extremely common in portrait photography, wedding albums, heritage projects, and social media filters
- **Artistic Judgment:** Requires understanding what makes an effective sepia tone vs. muddy brown
- **Foundation for Color Grading:** Establishes concepts needed for more advanced color grading workflows

**Skill Progression:** This task bridges basic color operations (like desaturation) with artistic color grading, making it ideal for intermediate-level training on color manipulation workflows.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Access nested color adjustment menus multiple times
- **Dialog Management:** Work with both Desaturate and Colorize dialogs sequentially
- **Slider Manipulation:** Adjust hue, saturation, and lightness sliders for sepia characteristics
- **Mode Selection:** Choose appropriate desaturation mode if prompted
- **Preview Assessment:** Evaluate preview results before applying changes
- **Sequential Application:** Apply multiple color adjustments in correct order

### B. GIMP Knowledge
- **Color Menu System:** Navigate GIMP's comprehensive color adjustment hierarchy
- **Desaturate Operation:** Understand how to convert color images to grayscale
- **Colorize Tool:** Know how to apply monochromatic color overlays to grayscale images
- **HSL Color Model:** Understand Hue-Saturation-Lightness parameters for colorization
- **Preview System:** Use previews to assess adjustments before committing
- **Non-destructive Workflow:** Understand the sequence matters (desaturate first, then colorize)

### C. Task-Specific Skills
- **Sepia Tone Characteristics:** Recognize the warm brown tones that define sepia photography
- **Hue Selection:** Know that sepia uses hues in the yellow-orange-brown range (typically 30-40° hue)
- **Saturation Balancing:** Apply enough saturation for warmth without oversaturating (typically 20-40%)
- **Lightness Adjustment:** Maintain appropriate brightness while adding sepia tones
- **Vintage Aesthetics:** Understand what makes a convincing sepia-toned vintage photograph
- **Color Harmony:** Ensure the sepia tone looks natural and cohesive across the entire image

## Task Steps

### 1. Initial Image Assessment
- Examine the color photograph that opens automatically in GIMP
- Identify the color characteristics that will be transformed
- Prepare to convert to vintage sepia aesthetic

### 2. Navigate to Desaturate
- Navigate to `Colors → Desaturate → Desaturate...` in the menu bar
- Wait for the Desaturate dialog to open
- Review the available desaturation modes (Lightness, Luminosity, Average)

### 3. Apply Desaturation
- Select an appropriate desaturation mode (Luminosity is typically best for photos)
- Click "OK" to apply the grayscale conversion
- Verify that the image is now fully grayscale with no color information

### 4. Navigate to Colorize
- Navigate to `Colors → Colorize...` in the menu bar
- Wait for the Colorize dialog to open
- Observe that the dialog provides Hue, Saturation, and Lightness sliders

### 5. Set Sepia Hue
- Adjust the Hue slider to the yellow-orange-brown range (typically 30-40 on the 0-360 scale)
- This creates the characteristic warm brown tone of sepia photography
- Use preview to assess the hue selection

### 6. Configure Sepia Saturation
- Adjust the Saturation slider to 20-40% (typically around 25-35)
- This provides enough color for the sepia effect without oversaturation
- Balance warmth with subtlety for authentic vintage appearance

### 7. Fine-tune Lightness (if needed)
- Adjust Lightness slider slightly if needed to maintain proper brightness
- Typically keep close to 0 (no change) unless the image appears too dark or light
- Ensure the sepia tone maintains good contrast and tonal range

### 8. Apply Colorization
- Click "OK" to apply the sepia tone colorization
- Verify that the image now displays the characteristic warm brown vintage appearance

### 9. Automatic Export
- The post-task hook will automatically export the result as "sepia_photo.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **sophisticated color channel analysis** combined with **sepia tone characteristic detection**:

### A. Grayscale Baseline Check
- **Color Variance Analysis:** Confirms the image has low color saturation (indicating successful desaturation base)
- **Channel Relationship:** Verifies that RGB channels maintain consistent relationships across the image
- **Saturation Reduction:** Ensures overall color saturation is significantly reduced from original

### B. Sepia Tone Characteristics
- **Warm Color Cast Detection:** Analyzes RGB channel ratios to detect characteristic brown tones
- **Channel Hierarchy:** Verifies that Red > Green > Blue in most pixels (sepia signature)
- **Hue Range Analysis:** Checks that dominant hues fall in the yellow-orange-brown range (20-50° typically)
- **Monochromatic Consistency:** Ensures the color overlay is relatively uniform (not multi-colored)

### C. Color Mathematical Analysis
- **RGB Ratio Calculation:** Measures R/G and G/B ratios across the image
  - Sepia typically shows: R/G ratio of 1.1-1.3, G/B ratio of 1.05-1.2
- **Mean Color Values:** Verifies that average RGB values follow sepia pattern (R > G > B)
- **Color Temperature:** Confirms warm (yellow-brown) color temperature throughout
- **Saturation Level:** Ensures saturation is present but subdued (indicating colorization after desaturation)

### D. Quality and Authenticity Assessment
- **Tonal Range Preservation:** Verifies that contrast and detail are maintained
- **Uniform Colorization:** Checks that sepia tone is consistently applied across the image
- **Vintage Appearance:** Ensures the result resembles authentic sepia-toned photography
- **No Color Contamination:** Confirms no unexpected color casts (blues, greens, magentas)

### Verification Checklist
- ✅ **Grayscale Base:** Image shows low color variance consistent with desaturation
- ✅ **Sepia Color Cast:** RGB channels follow sepia hierarchy (R > G > B)
- ✅ **Appropriate Hue Range:** Dominant colors fall in warm brown range (20-50° hue)
- ✅ **Correct Saturation:** Moderate saturation level (not fully gray, not fully saturated)
- ✅ **Warm Temperature:** Overall color temperature is warm (brown/yellow bias)

### Scoring System
- **100%:** Perfect sepia tone with all characteristic features present
- **75-99%:** Good sepia effect with minor deviations in hue, saturation, or uniformity
- **50-74%:** Recognizable sepia attempt but with significant issues (wrong hue, over/under-saturation)
- **0-49%:** Failed sepia conversion or image remains unchanged/incorrectly processed

**Pass Threshold:** 75% (requires convincing sepia tone with appropriate characteristics)

## Technical Implementation

### Files Structure