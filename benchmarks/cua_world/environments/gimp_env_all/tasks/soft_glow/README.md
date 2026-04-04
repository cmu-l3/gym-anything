# GIMP Soft Glow Effect Task (`soft_glow@1`)

## Overview

This task tests an agent's ability to apply GIMP's Soft Glow filter to create a dreamy, luminous effect on an image. The agent must navigate to the filter menu, configure the glow parameters, and apply the effect to transform a standard photograph into a softened, ethereal version. This represents a popular artistic technique used in portrait photography, wedding photography, and creative image enhancement.

## Rationale

**Why this task is valuable:**
- **Artistic Filter Application:** Introduces GIMP's Light and Shadow filter category with practical effects
- **Portrait Enhancement Skill:** Teaches a widely-used technique for flattering portrait processing
- **Multi-parameter Control:** Requires balancing glow radius and brightness for optimal results
- **Real-world Workflow:** Common in wedding photography, fashion, and romantic/dreamy aesthetics
- **Effect Subtlety:** Tests ability to apply effects that enhance rather than overwhelm the image
- **Filter Category Knowledge:** Builds familiarity with GIMP's extensive filter organization system

**Skill Progression:** This task bridges basic adjustments with artistic filters, teaching agents to apply sophisticated effects that require both technical execution and aesthetic judgment.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through `Filters → Light and Shadow → Softglow`
- **Dialog Interaction:** Work with the Softglow filter dialog and its parameters
- **Slider Manipulation:** Adjust Glow radius to control the effect intensity
- **Brightness Control:** Fine-tune the glow brightness for natural appearance
- **Preview Monitoring:** Use real-time preview to assess effect quality
- **Confirmation Actions:** Apply the filter using OK button

### B. GIMP Knowledge
- **Filter Menu Structure:** Understand GIMP's hierarchical filter organization
- **Light and Shadow Category:** Know where lighting-related effects are located
- **Softglow Mechanism:** Understand that soft glow adds luminous blur to bright areas
- **Preview System:** Use the preview window to evaluate effects before applying
- **Filter Parameters:** Know that radius controls spread and brightness controls intensity
- **Processing Time:** Understand that complex filters may take time to apply

### C. Task-Specific Skills
- **Glow Intensity Judgment:** Determine appropriate glow radius (typically 10-20 pixels)
- **Brightness Balance:** Set glow brightness for enhancement without overexposure
- **Natural Effect Assessment:** Recognize when glow looks flattering vs. artificial
- **Highlight Understanding:** Know that soft glow primarily affects bright areas and highlights
- **Aesthetic Evaluation:** Judge whether the dreamy effect enhances the image appropriately

## Task Steps

### 1. Initial Image Examination
- Examine the portrait or landscape image that opens automatically in GIMP
- Identify bright areas and highlights that will receive the glow effect
- Note overall image brightness and contrast

### 2. Navigate to Softglow Filter
- Click `Filters` in the menu bar
- Hover over or click `Light and Shadow` to expand the submenu
- Locate and click `Softglow` to open the filter dialog

### 3. Observe Default Preview
- Wait for the Softglow dialog to open with default parameters
- Observe the preview showing the glow effect
- Note default Glow radius and Brightness values

### 4. Adjust Glow Radius
- Move the Glow radius slider to approximately 10-15 pixels
- Watch the preview update showing the spread of the glow effect
- Balance between too subtle (radius too small) and too blurry (radius too large)

### 5. Adjust Brightness (if available)
- If the dialog includes a Brightness or Sharpness parameter, adjust to moderate levels
- Aim for a subtle, flattering glow rather than harsh overexposure
- Keep values that maintain image detail while adding luminosity

### 6. Evaluate Preview
- Assess whether the soft glow enhances the image appropriately
- Check that highlights have a gentle, luminous quality
- Verify that important details remain visible

### 7. Apply Filter
- Click "OK" to apply the Softglow effect
- Wait for processing to complete (may take several seconds)
- Observe the final result in the main canvas

### 8. Automatic Export
- The post-task hook will automatically export the result as "soft_glow_result.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **brightness distribution analysis and blur detection** to validate soft glow application:

### A. Brightness Enhancement Detection
- **Highlight Amplification:** Measures increase in bright pixel values (top 10% brightness)
- **Average Brightness Increase:** Verifies overall image brightness has increased moderately
- **Overexposure Prevention:** Ensures brightness increase is controlled (not clipping to white)
- **Target Range:** Expects 5-20% brightness increase in highlight regions

### B. Blur/Softness Analysis
- **Edge Softening Detection:** Measures reduction in high-frequency content (edges)
- **Gradient Analysis:** Calculates edge strength before and after using Sobel operators
- **Blur Evidence:** Verifies that edges are softer but not completely eliminated
- **Detail Preservation:** Ensures major features remain recognizable

### C. Glow Characteristics
- **Luminous Halo Detection:** Identifies characteristic glow halos around bright areas
- **Pixel Spread Analysis:** Measures how light values have spread to neighboring pixels
- **Natural Appearance:** Validates that glow doesn't create harsh artifacts or unnatural patterns
- **Uniform Application:** Confirms effect applied to entire image, not localized regions

### D. Image Quality Preservation
- **Detail Retention:** Verifies that important image features remain visible
- **Color Integrity:** Ensures colors haven't been drastically altered (mostly brightness effect)
- **No Corruption:** Checks for processing artifacts or errors
- **Appropriate Intensity:** Validates effect is noticeable but not overwhelming

### Verification Checklist
- ✅ **Brightness Increased:** Highlight regions show 5-20% brightness increase
- ✅ **Image Softened:** Edge strength reduced by 15-40% (blur evidence)
- ✅ **Glow Halos Present:** Bright areas show characteristic luminous spread
- ✅ **Details Preserved:** Major features remain visible and recognizable

### Scoring System
- **100%:** All 4 criteria met (excellent soft glow application)
- **75-99%:** 3/4 criteria met (good glow with minor parameter issues)
- **50-74%:** 2/4 criteria met (partial effect or incorrect intensity)
- **0-49%:** <2 criteria met (soft glow not properly applied)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure