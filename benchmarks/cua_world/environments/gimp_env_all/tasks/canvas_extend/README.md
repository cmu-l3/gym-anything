# GIMP Canvas Size Extension Task (`canvas_extend@1`)

## Overview

This task tests an agent's ability to use GIMP's Canvas Size tool to extend the working area of an image beyond its current boundaries. The agent must navigate to the canvas size dialog, increase canvas dimensions, position the original image appropriately, and fill new areas with a background color. This represents a fundamental composition technique used when creating space for text, adjusting aspect ratios, or preparing images for specific output formats.

## Rationale

**Why this task is valuable:**
- **Composition Control:** Teaches how to modify working space without altering original image content
- **Canvas Concepts:** Introduces the distinction between image size and canvas size in digital editing
- **Positioning Skills:** Requires understanding of image anchoring and placement within expanded canvas
- **Practical Workflow:** Common in social media formatting, document preparation, and design layouts
- **Non-destructive Extension:** Adds space without modifying existing content
- **Background Management:** Tests color selection and fill strategies for new areas

**Skill Progression:** This task bridges basic transforms with advanced composition techniques, introducing concepts essential for professional layout and formatting work.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Access `Image → Canvas Size` through menu system
- **Dialog Interaction:** Work with the Canvas Size dialog and its multiple controls
- **Dimension Input:** Enter specific width/height values for expanded canvas
- **Anchor Selection:** Click anchor points to position original image within new canvas
- **Color Selection:** Choose or configure fill color for newly added canvas areas
- **Preview Understanding:** Interpret visual preview showing canvas expansion
- **Confirmation Actions:** Apply changes using OK/Apply buttons

### B. GIMP Knowledge
- **Canvas vs. Image Size:** Understand that canvas can be larger than image content
- **Anchor System:** Know how to position existing content using the 9-point anchor grid
- **Layer System:** Understand that canvas expansion may add transparent or filled areas
- **Fill Options:** Know options for filling new canvas areas (color, transparency, patterns)
- **Dimension Units:** Work with pixel measurements for precise canvas sizing
- **Layer Management:** Understand how canvas changes affect layer boundaries

### C. Task-Specific Skills
- **Spatial Planning:** Determine appropriate canvas dimensions for the desired result
- **Centering Judgment:** Position original image appropriately within expanded canvas
- **Aspect Ratio Awareness:** Understand how canvas extension affects overall composition
- **Background Selection:** Choose appropriate fill colors that complement the image
- **Proportional Thinking:** Calculate extension amounts to achieve specific aspect ratios or sizes

## Task Steps

### 1. Initial Image Assessment
- Examine the image that opens automatically in GIMP
- Note current dimensions (visible in image window title or status bar)
- Plan how much space to add and where to position the original content

### 2. Access Canvas Size Dialog
- Navigate to `Image → Canvas Size` in the menu bar
- Wait for the Canvas Size dialog to open
- Observe the current dimensions and anchor position preview

### 3. Configure New Canvas Dimensions
- Increase the canvas width by 200 pixels (add 100 pixels on each side)
- Increase the canvas height by 150 pixels (add 75 pixels top and bottom)
- For example: if original is 400×300, new canvas should be 600×450

### 4. Set Image Anchor Position
- Click the center anchor point in the 3×3 anchor grid
- This centers the original image within the expanded canvas
- Observe the preview showing image position within new canvas bounds

### 5. Configure Fill Color
- Select "Fill with: Foreground color" or specify white/neutral color
- Ensure new canvas areas will have appropriate background
- Alternatively, choose appropriate fill pattern or transparency

### 6. Apply Canvas Extension
- Click "Resize" or "OK" button to apply the canvas size change
- Wait for the operation to complete
- Observe that the canvas has expanded with the original image centered

### 7. Verify Result
- Confirm canvas dimensions increased as specified
- Verify original image content is intact and properly centered
- Check that new canvas areas are filled with the specified color

### 8. Automatic Export
- The post-task hook will automatically export the result as "extended_canvas.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **dimensional analysis and content preservation validation**:

### A. Dimension Verification
- **Size Increase Detection:** Confirms canvas dimensions are larger than original
- **Specific Dimension Check:** Validates width increased by ~200px and height by ~150px (±10px tolerance)
- **Proportional Growth:** Ensures both dimensions grew appropriately
- **Aspect Ratio Change:** Confirms the aspect ratio changed as expected from canvas extension

### B. Content Preservation Analysis
- **Original Content Intact:** Verifies the original image content appears unchanged
- **Central Positioning:** Confirms original image is centered or appropriately positioned
- **No Cropping:** Ensures no part of original image was lost
- **Quality Maintenance:** Validates original content maintains its quality

### C. New Area Detection
- **Border Presence:** Detects new canvas areas surrounding original content
- **Uniform Fill:** Checks that new areas have consistent color/pattern
- **Complete Extension:** Verifies extension occurred on multiple sides (not just one edge)
- **Background Appropriateness:** Ensures new areas are distinguishable from original content

### D. Composition Analysis
- **Center-Weighted Position:** Validates original image is reasonably centered
- **Symmetrical Extension:** Checks that space was added relatively evenly
- **Clean Boundaries:** Ensures smooth transition between original and new areas
- **No Artifacts:** Confirms no distortion or unwanted effects introduced

### Verification Checklist
- ✅ **Dimensions Increased:** Canvas is approximately 200px wider and 150px taller
- ✅ **Content Preserved:** Original image content appears intact in center region
- ✅ **Border Added:** New canvas areas visible surrounding original content
- ✅ **Proper Positioning:** Original content centered or appropriately placed

### Scoring System
- **100%:** All 4 criteria met (perfect canvas extension)
- **75-99%:** 3/4 criteria met (good extension with minor positioning or size issues)
- **50-74%:** 2/4 criteria met (partial success but significant issues)
- **0-49%:** <2 criteria met (canvas extension failed or severely incorrect)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

### Verification Algorithm Details