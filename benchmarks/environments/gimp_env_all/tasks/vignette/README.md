# GIMP Vignette Effect Task (`vignette@1`)

## Overview

This task tests an agent's ability to apply a vignette effect to an image using GIMP's built-in lighting filters. The agent must navigate to the appropriate filter, apply the vignette effect that darkens the edges while keeping the center bright, and ensure the result creates the characteristic focus-drawing effect commonly used in photography and portrait editing. This represents a fundamental artistic enhancement technique used across photography, social media, and professional editing workflows.

## Rationale

**Why this task is valuable:**
- **Filter System Introduction:** Introduces GIMP's extensive filter library through a commonly-used effect
- **Photography Enhancement:** Teaches a classic technique for directing viewer attention to image subjects
- **Artistic Judgment:** Balances technical execution with aesthetic goals (natural-looking darkening)
- **Professional Workflow:** Represents real-world post-processing techniques used by photographers
- **Immediate Visual Feedback:** Provides clear, intuitive success criteria with visible edge darkening
- **Filter Parameter Understanding:** Introduces concepts of adjustable filter parameters without overwhelming complexity

**Skill Progression:** This task bridges basic image adjustments with artistic filter applications, building toward more sophisticated creative effects while maintaining simplicity of execution.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through nested filter menu structure (`Filters → Light and Shadow → Vignette`)
- **Dialog Interaction:** Work with filter preview dialogs and parameter controls
- **Parameter Adjustment:** Use sliders or numeric inputs to control effect intensity (optional for basic task)
- **Preview Assessment:** Evaluate real-time preview to judge effect appropriateness
- **Dialog Confirmation:** Apply the filter using OK/Apply buttons
- **Visual Quality Assessment:** Judge whether the effect enhances the image appropriately

### B. GIMP Knowledge
- **Filter Menu System:** Understand GIMP's categorized filter organization structure
- **Light and Shadow Filters:** Recognize the category containing lighting effect filters
- **Filter Dialog Interface:** Navigate preview dialogs with adjustment controls
- **Real-time Preview:** Understand that filter dialogs show live previews of effects
- **Default Parameters:** Know that filters often have reasonable defaults that can be applied directly
- **Filter Application:** Understand that filters modify the current layer directly

### C. Task-Specific Skills
- **Vignette Concept:** Understand what a vignette effect is and its artistic purpose
- **Edge Darkening Recognition:** Identify the characteristic darker edges and brighter center
- **Natural Effect Assessment:** Judge whether darkening looks gradual and natural vs. harsh and artificial
- **Subject Focus:** Understand how vignettes draw attention to central subjects
- **Subtlety Balance:** Recognize appropriate vignette intensity (noticeable but not overdone)

## Task Steps

### 1. Initial Image Assessment
- Examine the portrait or landscape image that opens automatically in GIMP
- Identify the main subject or focal point in the center/middle region
- Note that edges are currently uniform brightness with the rest of the image

### 2. Navigate to Filter Menu
- Click on "Filters" in the menu bar to open the filters menu
- Locate and hover over "Light and Shadow" to open that submenu
- Observe the various lighting effect options available

### 3. Select Vignette Filter
- Click on "Vignette" from the Light and Shadow submenu
- Wait for the Vignette filter dialog to open with preview

### 4. Review Default Settings
- Observe the preview showing darkened edges in the dialog
- Note the default parameter settings (typically work well for most images)
- Optionally adjust "Softness" or "Radius" sliders if edges are too harsh or subtle

### 5. Apply Vignette Effect
- Click "OK" button to apply the vignette effect to the image
- Observe that the dialog closes and effect is applied to canvas

### 6. Visual Verification
- Examine the result to confirm edges are darker than the center
- Verify that the darkening is gradual and natural-looking
- Confirm that the central subject now has enhanced visual prominence

### 7. Automatic Export
- The post-task hook will automatically export the result as "vignette_portrait.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **spatial brightness analysis with edge-to-center comparison** to detect vignette effects:

### A. Regional Brightness Analysis
- **Edge Region Definition:** Defines edge regions as the outer 20% border of the image (all four sides)
- **Center Region Definition:** Defines center region as the middle 40% of the image dimensions
- **Corner Region Sampling:** Specifically analyzes corner regions where vignette darkening is most pronounced
- **Multi-region Strategy:** Analyzes multiple zones to ensure gradual, symmetric darkening

### B. Comparative Brightness Measurement
- **Luminosity Calculation:** Converts images to grayscale and calculates average pixel intensity for each region
- **Before/After Comparison:** Measures both original and result brightness in edge and center regions
- **Ratio Analysis:** Computes edge-to-center brightness ratios before and after effect application
- **Darkening Quantification:** Calculates percentage reduction in edge brightness while verifying center preservation

### C. Vignette Characteristic Detection
- **Edge Darkening Validation:** Ensures edges became significantly darker (minimum 10% reduction in brightness)
- **Center Preservation:** Confirms center region brightness was largely maintained or minimally affected
- **Gradual Transition:** Verifies that intermediate regions show progressive darkening (not abrupt changes)
- **Symmetry Check:** Validates that darkening is relatively uniform across all edges (not lopsided)

### D. Quality and Naturalness Assessment
- **Reasonable Intensity:** Ensures darkening is noticeable but not extreme (edges still visible, not black)
- **Smooth Gradient:** Checks that transition from dark edges to bright center is gradual
- **No Over-processing:** Verifies that center wasn't brightened excessively or edges made too dark
- **Detail Preservation:** Confirms that edge details remain visible despite darkening

### Verification Checklist
- ✅ **Edges Darkened:** Edge region brightness reduced by ≥10% from original
- ✅ **Center Preserved:** Center region brightness maintained within 95-105% of original
- ✅ **Increased Contrast:** Edge-to-center brightness ratio decreased (edges darker relative to center)
- ✅ **Image Modified:** Clear measurable differences between original and result
- ✅ **Reasonable Intensity:** Edge darkening is between 10-40% (noticeable but not extreme)

### Scoring System
- **100%:** All 5 criteria met with excellent vignette effect (edges 15-30% darker, center preserved)
- **75-99%:** 4/5 criteria met with good vignette effect and minor imperfections
- **50-74%:** 3/5 criteria met with recognizable but suboptimal vignette application
- **0-49%:** <3 criteria met (insufficient darkening, incorrect application, or no effect applied)

**Pass Threshold:** 75% (requires clear vignette effect with appropriate edge darkening and center preservation)

## Technical Implementation

### Files Structure