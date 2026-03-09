# GIMP Layer Offset Task (`layer_offset@1`)

## Overview

This task tests an agent's ability to use GIMP's layer transform system to shift/wrap image content using the Offset function. The agent must navigate to the Layer Transform menu, apply a specific pixel offset in horizontal and/or vertical directions, and use wrap-around mode to seamlessly shift the image content. This operation is fundamental for texture creation, pattern alignment, and checking seamless tiling in digital art workflows.

## Rationale

**Why this task is valuable:**
- **Layer Transform Introduction:** Introduces GIMP's layer-specific transform operations (distinct from image transforms)
- **Practical Texture Workflow:** Essential skill for game texture artists and pattern designers checking seamless tiles
- **Coordinate Understanding:** Tests comprehension of pixel-based positioning and wrap-around behavior
- **Non-destructive Visualization:** Helps identify seams in textures that should tile seamlessly
- **Real-world Application:** Used in game development, web backgrounds, textile design, and 3D texture creation
- **Spatial Reasoning:** Requires understanding how content wraps from one edge to appear on the opposite edge

**Skill Progression:** This task bridges basic image transforms with layer-specific operations, introducing concepts needed for more advanced layer manipulation and texture work.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Layer → Transform → Offset`)
- **Dialog Interaction:** Work with the Offset dialog box and its parameters
- **Numeric Input:** Enter specific pixel offset values for X and Y directions
- **Option Selection:** Choose "Wrap around" mode from offset type options
- **Preview Understanding:** Interpret the preview to see how content will shift
- **Change Application:** Confirm and apply the offset transformation

### B. GIMP Knowledge
- **Layer vs Image Operations:** Distinguish between layer transforms and image transforms
- **Offset Behavior:** Understand how positive/negative offset values affect content positioning
- **Wrap-Around Concept:** Know that wrap mode makes content disappearing from one edge appear on the opposite edge
- **Pixel Coordinate System:** Understand X (horizontal) and Y (vertical) pixel positioning
- **Dialog Preview:** Recognize that offset dialogs often show real-time preview
- **Layer Boundaries:** Understand how layer content relates to layer/canvas boundaries

### C. Task-Specific Skills
- **Seamless Texture Testing:** Understand why offset is used to check texture tileability
- **Direction Mapping:** Correctly interpret which direction (left/right, up/down) corresponds to positive/negative values
- **Offset Planning:** Calculate appropriate offset values for the image dimensions
- **Wrap Verification:** Recognize when wrap-around is working correctly vs. other offset modes
- **Pattern Recognition:** Identify how content repositioning affects the overall composition

## Task Steps

### 1. Initial Image Examination
- Examine the texture/pattern image that opens automatically in GIMP
- Note distinctive features that will help verify the offset (edges, patterns, identifiable elements)
- Consider how a 50% shift would reveal whether the texture tiles seamlessly

### 2. Navigate to Layer Transform Menu
- Click on "Layer" in the menu bar to open the Layer menu
- Locate and hover over "Transform" to open the transform submenu
- Identify the "Offset" option within the transform submenu

### 3. Open Offset Dialog
- Click on "Offset" from the Transform submenu
- Wait for the Offset dialog box to appear
- Observe the current offset values (typically 0, 0) and available options

### 4. Set Horizontal Offset
- Locate the X (horizontal) offset input field
- Enter a value to shift the content horizontally (e.g., width/2 to shift by 50%)
- For a 512px wide image, enter 256 to shift content halfway

### 5. Set Vertical Offset (Optional)
- Locate the Y (vertical) offset input field
- Enter a value to shift the content vertically if desired (e.g., height/2)
- For a 512px tall image, enter 256 to shift content halfway

### 6. Select Wrap-Around Mode
- Locate the offset type/edge behavior options in the dialog
- Select "Wrap around" mode (not "Fill with background" or other options)
- Verify this option is selected to ensure seamless wrapping

### 7. Preview and Apply
- Observe the preview (if available) to see the offset effect
- Verify that content wraps from edges correctly
- Click "OK" or "Offset" button to apply the transformation

### 8. Verify Transformation
- Examine the result to confirm content has shifted appropriately
- Verify that content from the right edge now appears on the left (and vice versa)
- Check that no gaps or non-wrapped areas exist

### 9. Automatic Export
- The post-task hook will automatically export the result as "offset_texture.png"

## Verification Strategy

### Verification Approach
The verifier uses **pixel displacement analysis** combined with **wrap-around pattern matching**:

### A. Offset Detection via Cross-Correlation
- **Reference Generation:** Creates expected offset versions with various shift amounts
- **Cross-Correlation Analysis:** Uses 2D cross-correlation to detect the shift amount
- **Peak Detection:** Identifies the displacement that produces maximum correlation (excluding zero)
- **Directional Analysis:** Determines both horizontal and vertical offset components

### B. Wrap-Around Verification
- **Edge Continuity Analysis:** Checks that content from one edge appears on the opposite edge
- **Pixel Mapping Validation:** Verifies pixel-perfect mapping from source to destination locations
- **Seamless Transition:** Confirms no gaps, fills, or artifacts at wrap boundaries
- **Mathematical Verification:** Uses modulo arithmetic to validate wrap-around behavior

### C. Offset Magnitude Assessment
- **Minimum Displacement:** Ensures offset is substantial enough to be meaningful (≥10% of dimension)
- **Non-trivial Shift:** Verifies the offset isn't zero or negligibly small
- **Reasonable Range:** Confirms offset is within image dimensions (not exceeding width/height)
- **Direction Validation:** Checks that offset occurred in expected directions

### D. Quality and Mode Verification
- **No Artifacts:** Ensures wrap-around mode was used (not fill-with-background or other modes)
- **Pixel Preservation:** Verifies all original pixels are present in new positions
- **Dimension Maintenance:** Confirms image dimensions remain unchanged
- **Content Integrity:** Ensures no pixel values were altered, only repositioned

### Verification Checklist
- ✅ **Significant Offset Detected:** Cross-correlation shows clear displacement peak (≥10% of image dimension)
- ✅ **Wrap-Around Mode Used:** Edge analysis confirms seamless wrapping (no fills or gaps)
- ✅ **Correct Direction:** Offset occurred in appropriate horizontal and/or vertical directions
- ✅ **Pixel-Perfect Mapping:** Mathematical validation of wrap-around pixel repositioning
- ✅ **Quality Preserved:** No artifacts, degradation, or unintended alterations

### Scoring System
- **100%:** Perfect offset with clear displacement, proper wrap-around, and all criteria met
- **75-99%:** Good offset with minor imperfections in execution or verification
- **50-74%:** Recognizable offset but with issues in wrap-around mode or displacement amount
- **0-49%:** Incorrect transformation, insufficient offset, or wrong mode used

**Pass Threshold:** 75% (requires clear offset with proper wrap-around behavior)

### Mathematical Verification Details