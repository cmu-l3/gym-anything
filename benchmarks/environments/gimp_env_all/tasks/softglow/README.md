# GIMP Soft Glow Effect Task (`softglow@1`)

## Overview

This task tests an agent's ability to apply GIMP's Soft Glow artistic filter to create a dreamy, luminous effect on an image. The agent must navigate to the appropriate filter menu, understand the Soft Glow effect parameters, and apply the effect to transform a portrait or landscape into a softer, more ethereal version. This represents a popular photographic technique used in portrait and artistic photography.

## Rationale

**Why this task is valuable:**
- **Artistic Filter Introduction:** Introduces GIMP's artistic filters category beyond basic adjustments
- **Portrait Enhancement:** Teaches a commonly-used effect for flattering portraits and romantic scenes
- **Filter Parameter Understanding:** Tests ability to work with filter dialogs and their controls
- **Real-world Relevance:** Widely used in wedding photography, portrait retouching, and artistic image creation
- **Visual Effect Assessment:** Develops understanding of how filters transform image characteristics
- **Professional Technique:** Represents industry-standard photo softening and glow effects

**Skill Progression:** This task bridges basic color adjustments with advanced artistic filters, introducing agents to GIMP's extensive creative effects library.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through `Filters → Light and Shadow → Softglow` (or `Filters → Artistic → Softglow` in some versions)
- **Dialog Interaction:** Work with the Soft Glow filter dialog and its preview
- **Parameter Adjustment:** Adjust glow radius and brightness sliders if needed
- **Preview Interpretation:** Understand the real-time preview of filter effects
- **Confirmation Actions:** Apply the filter using OK button
- **Patience Management:** Wait for filter processing to complete

### B. GIMP Knowledge
- **Filter Menu Organization:** Understand GIMP's hierarchical filter categorization
- **Artistic Filters:** Know that Soft Glow is part of artistic/light effects category
- **Filter Processing:** Understand that complex filters may take time to process
- **Preview System:** Know how to use filter preview to assess effects before applying
- **Glow Effect Concepts:** Understand how soft glow brightens highlights and diffuses light
- **Non-destructive Preview:** Recognize that preview shows potential result before commitment

### C. Task-Specific Skills
- **Glow Effect Understanding:** Recognize what constitutes a successful soft glow (dreamy, luminous quality)
- **Intensity Assessment:** Judge whether glow effect is appropriately applied (not too subtle, not overdone)
- **Image Suitability:** Understand that soft glow works best on images with light areas and subjects
- **Artistic Judgment:** Balance technical execution with aesthetic quality
- **Before/After Comparison:** Mentally compare the glowing result with the original

## Task Steps

### 1. Initial Image Assessment
- Examine the portrait or landscape image that opens automatically in GIMP
- Identify highlight areas that will receive the glow effect
- Note the current image appearance for later comparison

### 2. Navigate to Soft Glow Filter
- Click on "Filters" in the menu bar to open the Filters menu
- Navigate to "Light and Shadow" submenu (or "Artistic" in some GIMP versions)
- Locate and hover over "Softglow" option

### 3. Open Soft Glow Dialog
- Click on "Softglow" to open the filter dialog
- Wait for the dialog window to appear with preview
- Observe the default parameter settings

### 4. Review Filter Parameters
- Note the "Glow radius" slider (controls spread of glow)
- Note the "Brightness" slider (controls glow intensity)
- Observe the preview showing the effect with current settings

### 5. Adjust Parameters (Optional)
- Default settings typically work well for most images
- Optionally adjust glow radius (typical range: 10-20)
- Optionally adjust brightness (typical range: 0.70-0.95)
- Use preview to assess the effect

### 6. Apply Soft Glow Effect
- Click "OK" button to apply the filter
- Wait for processing to complete (may take several seconds)
- Observe the transformation as the effect is applied

### 7. Verify Result
- Examine the final image for the characteristic soft glow appearance
- Check that highlights appear luminous and diffused
- Confirm the dreamy, ethereal quality has been achieved

### 8. Automatic Export
- The post-task hook will automatically export the result as "softglow_portrait.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **multi-metric luminance and softness analysis** to detect the soft glow effect:

### A. Brightness Enhancement Detection
- **Highlight Analysis:** Measures increase in brightness values, especially in lighter areas
- **Global Brightness:** Calculates overall image brightness increase (5-20% typical)
- **Luminance Distribution:** Analyzes shift toward brighter values in histogram
- **High-value Pixel Count:** Counts increase in pixels with high luminance values

### B. Softness and Blur Assessment
- **Edge Sharpness Analysis:** Measures reduction in edge definition using gradient magnitude
- **Detail Preservation:** Ensures fine details are softened but not eliminated
- **Variance Reduction:** Calculates decreased local variance indicating diffusion
- **Smoothness Metrics:** Uses standard deviation analysis to detect softening

### C. Glow Characteristic Detection
- **Highlight Bloom:** Detects expansion of bright areas into surrounding regions
- **Halo Effects:** Identifies gentle halos around bright objects (characteristic of glow)
- **Contrast Softening:** Measures reduction in local contrast while maintaining overall structure
- **Diffusion Pattern:** Analyzes spatial frequency changes indicating light diffusion

### D. Quality and Integrity Checks
- **No Over-processing:** Ensures effect isn't so strong that image becomes unrecognizable
- **Balanced Effect:** Verifies glow is present but not excessive
- **Image Modification:** Confirms clear differences from original image
- **No Artifacts:** Checks that no processing errors or corruption occurred

### Verification Checklist
- ✅ **Brightness Increased:** Overall image brightness increased by 5-20%
- ✅ **Edges Softened:** Edge sharpness reduced by at least 15%, indicating diffusion
- ✅ **Glow Present:** Characteristic expansion and softening of highlights detected
- ✅ **Quality Maintained:** Image remains clear and recognizable despite softening

### Scoring System
- **100%:** Perfect soft glow with appropriate brightness increase, softening, and characteristic glow
- **75-99%:** Good glow effect with clear softening and brightness enhancement
- **50-74%:** Partial glow effect present but weak or inconsistent
- **0-49%:** No discernible soft glow effect or processing failure

**Pass Threshold:** 75% (requires clear evidence of soft glow characteristics)

## Technical Implementation

### Files Structure