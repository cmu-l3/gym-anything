# GIMP Oil Painting Effect Task (`oilify@1`)

## Overview

This task tests an agent's ability to apply GIMP's oil painting artistic filter to transform a photograph into an artwork that resembles an oil painting. The agent must navigate to the Oilify filter, configure basic parameters (mask size), and apply the effect to create a painterly appearance with softened edges and unified color regions. This represents a fundamental artistic filter commonly used in creative photo manipulation and artistic content creation.

## Rationale

**Why this task is valuable:**
- **Artistic Filter Introduction:** Introduces GIMP's artistic filter system with a visually distinctive effect
- **Simple Filter Workflow:** Tests basic filter navigation and application without complex parameters
- **Visual Transformation:** Provides dramatic before/after results that clearly indicate success
- **Creative Applications:** Common in poster design, artistic photo effects, and stylized graphics
- **Algorithm Understanding:** Demonstrates how algorithms can simulate traditional art media
- **Foundation for Effects:** Establishes workflow patterns for other artistic filters

**Skill Progression:** This task bridges basic image operations with artistic filter application, introducing the filter system while maintaining simplicity through minimal parameter adjustment.

## Skills Required

### A. Interaction Skills
- **Filter Menu Navigation:** Navigate nested filter menus (Filters → Artistic → Oilify)
- **Dialog Interaction:** Work with filter dialog box and parameter controls
- **Slider/Numeric Input:** Adjust mask size parameter using slider or numeric input
- **Preview Assessment:** Use preview window to assess effect before applying
- **Filter Application:** Confirm and apply the filter transformation

### B. GIMP Knowledge
- **Filter System Architecture:** Understand GIMP's hierarchical filter organization
- **Artistic Filter Category:** Know where artistic effects are located in menu structure
- **Oilify Effect:** Understand that oilify creates painterly appearance by averaging nearby colors
- **Mask Size Parameter:** Larger values = broader brush strokes, more dramatic effect
- **Processing Time:** Recognize that artistic filters may require processing time
- **Non-destructive Preview:** Preview shows effect without committing changes

### C. Task-Specific Skills
- **Artistic Effect Recognition:** Understand what oil painting appearance looks like
- **Parameter Selection:** Choose appropriate mask size (typically 5-15) for balanced effect
- **Quality Judgment:** Assess whether transformation achieves painterly quality
- **Effect Intensity:** Recognize relationship between mask size and effect intensity

## Task Steps

### 1. Initial Image Examination
- Examine the photograph that opens automatically in GIMP
- Note areas with detail that will be transformed into paint-like regions
- Consider how the oil painting effect will alter textures and edges

### 2. Navigate to Oilify Filter
- Click on "Filters" in the menu bar
- Navigate to "Artistic" submenu
- Locate and click on "Oilify..." option

### 3. Configure Oilify Parameters
- In the Oilify dialog, observe the "Mask Size" parameter
- Set mask size to a moderate value (e.g., 7-10 pixels)
- Larger values create broader, more dramatic brush strokes
- Use preview checkbox to see effect before applying

### 4. Preview Assessment (Optional)
- Enable preview to see the oil painting effect
- Adjust mask size if needed to achieve desired painterly quality
- Balance between too subtle (too small) and too abstract (too large)

### 5. Apply Oil Painting Effect
- Click "OK" to apply the oilify filter
- Wait for GIMP to process the effect (may take several seconds depending on image size)
- Observe the transformation to painterly appearance

### 6. Result Verification
- Examine the result for characteristic oil painting qualities:
  - Softened edges and details
  - Unified color regions (like brush strokes)
  - Reduced fine texture while maintaining overall composition
- Verify the image has painterly rather than photographic appearance

### 7. Automatic Export
- The post-task hook will automatically export the result as "oil_painting.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **edge softening analysis and local color uniformity measurement** to validate the oil painting effect:

### A. Edge Softening Detection
- **Edge Comparison:** Apply edge detection to both original and result images
- **Edge Reduction Measurement:** Oil painting effect significantly reduces sharp edges
- **Edge Pixel Count:** Calculate reduction in high-contrast edge pixels
- **Softness Metric:** Measure overall reduction in high-frequency detail

### B. Local Color Uniformity Analysis
- **Regional Color Variance:** Oil painting creates regions of uniform color (brush strokes)
- **Variance Reduction:** Measure decrease in local color variance within small neighborhoods
- **Smoothness Metric:** Calculate increase in color smoothness across local regions
- **Texture Simplification:** Detect reduction in fine texture detail

### C. Detail Preservation vs. Simplification
- **Overall Structure Maintained:** Verify major compositional elements remain recognizable
- **Fine Detail Reduced:** Confirm small details have been softened/unified
- **Balance Assessment:** Ensure effect is substantial but not completely abstract
- **SSIM Analysis:** Use structural similarity to verify reasonable similarity (0.6-0.85 range)

### D. Transformation Confirmation
- **Significant Change Detection:** Ensure substantial pixel-level differences from original
- **Processing Signature:** Detect characteristic oilify smoothing patterns
- **Quality Maintenance:** Verify no corruption or severe quality loss occurred

### Verification Checklist
- ✅ **Edge Reduction:** Sharp edges reduced by at least 40% compared to original
- ✅ **Color Uniformity:** Local color variance decreased by at least 30%
- ✅ **Structural Preservation:** SSIM between 0.6-0.85 (transformed but recognizable)
- ✅ **Substantial Modification:** At least 30% of pixels significantly changed from original

### Scoring System
- **100%:** All 4 criteria met (perfect oil painting effect with proper smoothing and uniformity)
- **75-99%:** 3/4 criteria met (good oil painting effect with minor issues)
- **50-74%:** 2/4 criteria met (partial effect but incomplete transformation)
- **0-49%:** <2 criteria met (oilify filter not successfully applied)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure