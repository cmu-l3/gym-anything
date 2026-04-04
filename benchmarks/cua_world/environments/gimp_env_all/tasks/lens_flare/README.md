# GIMP Lens Flare Effect Task (`lens_flare@1`)

## Overview

This task tests an agent's ability to apply GIMP's lens flare filter to add realistic lighting effects to an image. The agent must navigate to the appropriate filter, position the flare effect appropriately, and apply it to create a dramatic lighting accent. This represents a common creative photography and digital art technique used to enhance images with realistic or stylized light sources.

## Rationale

**Why this task is valuable:**
- **Artistic Filter Introduction:** Introduces GIMP's extensive Light and Shadow filter category
- **Creative Enhancement Skills:** Tests ability to apply effects that enhance rather than just transform images
- **Position-based Interaction:** Requires both menu navigation and spatial positioning within the image
- **Real-world Relevance:** Commonly used in photography, game assets, promotional imagery, and digital art
- **Visual Impact Understanding:** Tests comprehension of how lighting effects enhance composition
- **Foundation for Effects:** Establishes concepts needed for other lighting and atmospheric effects

**Skill Progression:** This task bridges basic transformations with creative filter application, introducing agents to GIMP's artistic enhancement capabilities.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through nested filter menus (`Filters → Light and Shadow → Lens Flare`)
- **Preview Dialog Interaction:** Work with filter preview dialogs that show real-time effect
- **Position Selection:** Click within preview to position the flare center point
- **Parameter Observation:** Understand default filter parameters and their effects
- **Dialog Confirmation:** Apply filter changes using OK/Apply buttons
- **Visual Assessment:** Evaluate the effect's appropriateness and visual impact

### B. GIMP Knowledge
- **Filter System Organization:** Understand GIMP's categorized filter menu structure
- **Light and Shadow Category:** Navigate the lighting effects filter category
- **Preview System:** Work with filter preview windows that show before/after comparison
- **Non-destructive Preview:** Understand that preview shows effect before commitment
- **Filter Application:** Know that filters apply directly to the active layer
- **Effect Intensity:** Recognize that lens flare has adjustable intensity parameters

### C. Task-Specific Skills
- **Lighting Theory:** Understand how light sources interact with scenes
- **Composition Enhancement:** Identify appropriate locations for lighting effects (typically sky, light sources, highlights)
- **Realism Assessment:** Judge whether the flare position looks natural for the scene
- **Effect Subtlety:** Balance dramatic effect with maintaining image quality
- **Spatial Reasoning:** Position effect in compositionally appropriate areas

## Task Steps

### 1. Initial Image Analysis
- Examine the landscape or outdoor scene image that opens automatically in GIMP
- Identify potential light source locations (sky, sun position, bright areas)
- Consider where a lens flare would enhance the composition naturally

### 2. Navigate to Lens Flare Filter
- Click on "Filters" in the menu bar
- Hover over "Light and Shadow" to open the lighting effects submenu
- Locate and click on "Lens Flare" option

### 3. Lens Flare Dialog Interaction
- Observe the Lens Flare dialog with preview window
- Note the default flare position in the preview
- Examine available parameters (center position, intensity, lens type)

### 4. Position the Lens Flare
- Click in the preview window to reposition the flare center
- Place the flare in the upper portion of the image (sky area) for natural appearance
- Alternatively, position over an existing bright spot or light source
- Adjust position to create visually pleasing composition

### 5. Parameter Adjustment (Optional)
- If needed, adjust intensity or other parameters using available sliders
- Maintain default settings for simplicity if they produce good results
- Preview updates in real-time as parameters change

### 6. Apply the Effect
- Click "OK" button to apply the lens flare to the image
- Wait for filter processing to complete
- Observe the bright light burst and rays added to the image

### 7. Quality Verification
- Visually confirm the lens flare is visible and well-positioned
- Ensure the effect enhances rather than overwhelms the image
- Verify no error messages or processing failures occurred

### 8. Automatic Export
- The post-task hook will automatically export the result as "lens_flare_effect.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **brightness analysis and change detection** to identify lens flare addition:

### A. Brightness Delta Analysis
- **High-brightness Region Detection:** Identifies new bright spots in the result image
- **Intensity Threshold:** Searches for pixels with brightness significantly higher than original
- **Cluster Analysis:** Detects concentrated bright regions characteristic of lens flare
- **Position Validation:** Confirms bright regions appear in expected areas (upper portion of image)

### B. Localized Brightness Increase
- **Pixel-wise Comparison:** Compares brightness values between original and result
- **Bright Spot Identification:** Identifies pixels with ≥30-50 intensity units increase
- **Region Size:** Verifies bright regions are substantial (typically 200+ connected pixels)
- **Maximum Brightness:** Checks for very bright pixels (near 255) indicating flare center

### C. Visual Effect Characteristics
- **Radial Pattern:** Analyzes whether brightness increase shows radial/star-like pattern
- **Gradient Analysis:** Detects brightness gradients radiating from flare center
- **Color Analysis:** Checks for characteristic flare colors (white, yellow, rainbow artifacts)
- **Effect Distribution:** Verifies effect is localized, not global brightness increase

### D. Change Magnitude
- **Sufficient Modification:** Ensures image was meaningfully altered (not just minor tweaks)
- **Effect Prominence:** Validates that flare is visible and significant
- **Quality Preservation:** Confirms overall image quality maintained outside flare area
- **No Artifacts:** Checks for absence of processing errors or corruption

### Verification Checklist
- ✅ **Bright Region Added:** Significant new bright spots detected (≥200 pixels with >30 intensity increase)
- ✅ **High Intensity Peak:** At least some pixels reach very high brightness (≥240 intensity)
- ✅ **Localized Effect:** Bright region is concentrated, not spread across entire image
- ✅ **Appropriate Position:** Bright region appears in upper half or logical light source area
- ✅ **Image Modified:** Clear differences from original detected (≥2% pixels significantly changed)

### Scoring System
- **100%:** All criteria met with clear, well-positioned lens flare effect
- **75-99%:** Good lens flare present with minor positioning or intensity issues
- **50-74%:** Lens flare detected but weak, poorly positioned, or barely visible
- **0-49%:** No clear lens flare effect detected or image unchanged

**Pass Threshold:** 75% (requires clear, visible lens flare effect appropriately positioned)

## Technical Implementation

### Files Structure