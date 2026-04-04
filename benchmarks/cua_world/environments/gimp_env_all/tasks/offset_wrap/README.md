# GIMP Offset (Wrap-Around) Task (`offset_wrap@1`)

## Overview

This task tests an agent's ability to use GIMP's Offset tool to shift image content by a specific amount with wrap-around. The agent must navigate to the Offset dialog, enter precise X and Y offset values, ensure wrap-around mode is enabled, and apply the transformation. This operation is fundamental for creating seamless patterns, checking texture tileability, and adjusting image composition for repeating designs.

## Rationale

**Why this task is valuable:**
- **Pattern Creation Workflow:** Essential for creating seamless textures and repeating patterns in game development, web design, and textile design
- **Spatial Understanding:** Tests comprehension of coordinate systems and modular arithmetic in image space
- **Dialog Proficiency:** Requires working with multi-parameter dialogs and understanding different offset modes
- **Transform Fundamentals:** Introduces a unique transformation type distinct from rotation, scaling, or flipping
- **Real-world Application:** Common in texture artists' workflows for seam detection and correction
- **Practical Utility:** Used to reposition content without losing any image data

**Skill Progression:** This task bridges basic transforms (like mirroring) with more sophisticated spatial operations, making it ideal for intermediate-level training.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through `Layer → Transform → Offset` menu hierarchy
- **Dialog Interaction:** Work with the Offset dialog interface
- **Numeric Input:** Enter precise pixel values for X and Y offsets
- **Mode Selection:** Understand and select wrap-around vs. other offset modes
- **Visual Preview:** Interpret the preview to understand the transformation effect
- **Confirmation:** Apply changes using OK button

### B. GIMP Knowledge
- **Transform Menu System:** Navigate to layer transformation tools
- **Offset Concepts:** Understand what "offset" means in terms of pixel displacement
- **Wrap-Around Mode:** Comprehend how wrap-around creates seamless shifting (modular arithmetic)
- **Coordinate System:** Understand GIMP's X/Y coordinate system (origin at top-left)
- **Dialog Parameters:** Know how offset values relate to image dimensions
- **Non-destructive Preview:** Use preview to verify settings before applying

### C. Task-Specific Skills
- **Spatial Visualization:** Mentally predict how content will shift with given offset values
- **Seamless Pattern Understanding:** Recognize how wrap-around maintains image continuity
- **Tileability Assessment:** Understand how offset reveals or tests pattern seamlessness
- **Precision Planning:** Calculate appropriate offset values for desired effects
- **Quality Verification:** Confirm the offset was applied correctly by examining the result

## Task Steps

### 1. Initial Image Examination
- Examine the pattern or texture image that opens automatically in GIMP
- Note distinctive features or regions that will help verify the offset
- Identify the image dimensions for reference

### 2. Access Offset Dialog
- Navigate to `Layer → Transform → Offset` in the menu bar
- Wait for the Offset dialog to open
- Observe the current offset values (typically 0, 0)

### 3. Set X Offset Value
- Locate the X offset input field (horizontal displacement)
- Enter the specified offset value (e.g., 100 pixels to the right)
- Observe the preview update if preview is enabled

### 4. Set Y Offset Value
- Locate the Y offset input field (vertical displacement)
- Enter the specified offset value (e.g., 80 pixels down)
- Observe how the preview shows the combined X and Y displacement

### 5. Enable Wrap-Around Mode
- Locate the offset mode options in the dialog
- Select "Wrap around" mode (as opposed to "Fill with background color")
- Confirm that preview shows content wrapping at edges rather than leaving gaps

### 6. Apply Offset Transformation
- Click "OK" or "Apply" to apply the offset
- Observe that image content has shifted with wrap-around behavior
- Verify that no content was lost (wrap-around preserved all pixels)

### 7. Automatic Export
- The post-task hook will automatically export the result as "offset_result.png"

## Verification Strategy

### Verification Approach
The verifier uses **modular arithmetic-based pixel position validation** to confirm correct offset:

### A. Offset Detection and Validation
- **Pixel Position Mapping:** Creates a mathematical model of where pixels should move with the specified offset
- **Wrap-Around Verification:** Uses modulo operation to verify pixel wrapping at boundaries
- **Reference Generation:** Generates a perfect reference by programmatically applying the same offset with wrap
- **Position Accuracy:** Checks that pixels at (x, y) appear at ((x + offset_x) % width, (y + offset_y) % height)

### B. Structural Similarity Analysis
- **SSIM Comparison:** Uses Structural Similarity Index Measure to compare result with reference
- **High Precision Threshold:** Requires SSIM ≥ 0.95 for accurate offset match
- **Wrap Integrity:** Ensures wrap-around was used rather than other offset modes
- **Content Preservation:** Verifies all original pixels are present in shifted positions

### C. Boundary Region Analysis
- **Edge Examination:** Specifically checks that boundary regions show wrapped content
- **Seam Detection:** Verifies content from opposite edges meets correctly at boundaries
- **Continuity Check:** Confirms no gaps or black areas introduced at edges
- **Mode Validation:** Distinguishes wrap-around from background-fill modes

### D. Mathematical Validation
- **Coordinate Transform:** Applies modular coordinate transformation: (x', y') = ((x + dx) mod W, (y + dy) mod H)
- **Sample Point Testing:** Checks multiple sample points to verify correct position mapping
- **Full Image Comparison:** Compares entire result against mathematically generated reference
- **Precision Metrics:** Uses pixel-perfect comparison with tolerance for compression artifacts

### Verification Checklist
- ✅ **Correct Offset Applied:** SSIM ≥ 0.95 with reference offset image
- ✅ **Wrap-Around Used:** Boundary regions show wrapped content (no black gaps)
- ✅ **Proper Direction:** Offset applied in correct X and Y directions
- ✅ **Content Preserved:** All original pixels present in new positions
- ✅ **Dimensions Maintained:** Image dimensions unchanged

### Scoring System
- **100%:** Perfect offset with SSIM ≥ 0.95 and all criteria met
- **75-99%:** Very good offset with minor imperfections or slight position errors
- **50-74%:** Recognizable offset but with notable issues (wrong mode, partial offset)
- **0-49%:** Incorrect transformation or failed operation

**Pass Threshold:** 75% (requires accurate offset with wrap-around)

### Mathematical Verification Details