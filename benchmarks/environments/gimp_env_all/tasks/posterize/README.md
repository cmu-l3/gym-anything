# GIMP Posterize Effect Task (`posterize@1`)

## Overview

This task tests an agent's ability to apply GIMP's posterize effect to reduce the number of color levels in an image, creating a poster-like or simplified graphic appearance. The agent must navigate to the posterize tool, adjust the number of color levels to a specific value, and apply the effect. This represents a creative color quantization technique commonly used in graphic design, pop art, and digital illustration.

## Rationale

**Why this task is valuable:**
- **Color Quantization Concept:** Introduces the idea of reducing continuous color spaces to discrete levels
- **Artistic Effect Creation:** Demonstrates transformation from photographic realism to stylized graphic art
- **Simple Single-Parameter Filter:** Easy-to-understand effect with immediate visual feedback
- **Real-world Applications:** Used in poster design, pop art, screen printing preparation, and social media graphics
- **Foundation for Understanding:** Builds intuition about color depth and digital color representation
- **Quick Creative Workflow:** Represents rapid artistic transformation common in digital design

**Skill Progression:** This task bridges basic color adjustments with creative artistic effects, making it ideal for learning color manipulation concepts.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate to `Colors → Posterize` through GIMP's menu system
- **Dialog Interaction:** Work with the Posterize dialog interface
- **Numeric Adjustment:** Set posterize levels using slider or numeric input (typically 3-5 levels)
- **Preview Assessment:** Evaluate effect preview before applying
- **Confirmation Actions:** Apply changes using OK button

### B. GIMP Knowledge
- **Color Menu System:** Navigate GIMP's color adjustment menu hierarchy
- **Posterize Concept:** Understand that posterize reduces the number of tones per color channel
- **Effect Parameters:** Know that lower posterize levels create more dramatic, graphic effects
- **Preview Functionality:** Use GIMP's preview to see changes before committing
- **Non-destructive Workflow:** Understand that effects apply to the current layer

### C. Task-Specific Skills
- **Quantization Understanding:** Recognize how reducing color levels creates poster-like appearance
- **Level Selection:** Choose appropriate posterize levels for desired stylization
- **Visual Assessment:** Evaluate when an image has been appropriately posterized
- **Artistic Judgment:** Balance between stylization and image recognizability

## Task Steps

### 1. Initial Image Assessment
- Examine the colorful photo that opens automatically in GIMP
- Note the smooth color gradations and tonal range in the original
- Identify areas where posterize effect will be most visible

### 2. Navigate to Posterize
- Click on "Colors" in the menu bar to open the Colors menu
- Locate and click on "Posterize" in the menu list
- Wait for the Posterize dialog to open

### 3. Observe Default Settings
- Note the current posterize levels setting (typically 3 by default)
- Observe the preview showing the initial effect
- Understand that lower values create more dramatic simplification

### 4. Adjust Posterize Levels
- Set the posterize levels to **4** (or as specified in the task description)
- Use the slider or directly type the numeric value
- Observe the preview update to show distinct color bands and reduced gradations

### 5. Evaluate Effect Preview
- Review the preview to confirm poster-like appearance is achieved
- Verify that smooth color transitions have become stepped/banded
- Ensure image remains recognizable despite color reduction

### 6. Apply Posterize Effect
- Click the "OK" button to apply the posterize effect to the image
- Observe that the full image now displays the simplified color palette
- Note the characteristic flat color areas and sharp color transitions

### 7. Automatic Export
- The post-task hook will automatically export the result as "posterized_image.png"

## Verification Strategy

### Verification Approach
The verifier uses **multi-method color analysis** combining unique color counting, histogram analysis, and color clustering detection:

### A. Unique Color Reduction Analysis
- **Dramatic Color Reduction:** Counts unique colors before and after posterization
- **Reduction Threshold:** Posterized images should show significant color palette reduction
- **Quantization Detection:** For posterize level 4, theoretical maximum is 4³ = 64 unique colors (ignoring edge artifacts)
- **Practical Validation:** Accounts for anti-aliasing and compression artifacts that may add colors

### B. Color Distribution Pattern Analysis
- **Histogram Band Detection:** Analyzes RGB histograms for characteristic discrete peaks
- **Gradient Elimination:** Verifies that smooth color transitions have become stepped
- **Peak Identification:** Detects distinct color level peaks rather than continuous distribution
- **Channel Analysis:** Validates quantization occurred across all RGB channels

### C. Color Clustering Verification
- **Dominant Color Detection:** Identifies whether colors cluster around discrete values
- **Value Distribution:** Checks if pixel values tend toward specific posterize levels (e.g., 0, 85, 170, 255 for 4 levels)
- **Clustering Strength:** Measures how tightly colors group around quantized values
- **Statistical Validation:** Uses variance and standard deviation to detect quantization

### D. Visual Change Detection
- **Significant Modification:** Ensures substantial difference from original image
- **Pattern Recognition:** Detects characteristic posterize artifacts (banding, flat color areas)
- **Edge Behavior:** Analyzes whether posterize created sharp color boundaries
- **Spatial Analysis:** Checks for regions of uniform color typical of posterized images

### Verification Checklist
- ✅ **Significant Color Reduction:** Unique color count reduced substantially (typically to <500 colors for level 4)
- ✅ **Histogram Shows Banding:** RGB histograms display distinct peaks rather than smooth curves
- ✅ **Color Clustering:** Pixel values cluster around expected posterize levels
- ✅ **Image Modified:** Clear visual differences detected from original (>15% pixels significantly changed)

### Scoring System
- **100%:** Strong posterize effect with all 4 criteria met (excellent quantization)
- **75-99%:** Good posterize effect with 3/4 criteria met (clear color reduction)
- **50-74%:** Moderate posterize effect with 2/4 criteria met (some quantization visible)
- **0-49%:** Weak or no posterize effect (<2 criteria met)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure