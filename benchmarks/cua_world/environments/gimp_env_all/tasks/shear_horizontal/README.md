# GIMP Horizontal Shear Task (`shear_horizontal@1`)

## Overview

This task tests an agent's ability to use GIMP's shear transformation tool to slant an image along the horizontal axis. The agent must navigate to the shear transform dialog, enter a specific shear magnitude, and apply the transformation. Shear transforms are commonly used for perspective correction, artistic text effects, and geometric manipulations in graphic design.

## Rationale

**Why this task is valuable:**
- **Geometric Transform Mastery:** Introduces shear as a distinct transformation beyond rotation, scaling, and flipping
- **Numeric Input Precision:** Requires entering exact numeric values for transformation parameters
- **Dialog Interaction:** Tests ability to work with GIMP's transform dialogs and confirmation workflows
- **Real-world Application:** Common in logo design, perspective correction, text effects, and architectural visualization
- **Transform Tool Foundation:** Builds understanding of GIMP's parametric transformation system
- **Visual Spatial Reasoning:** Tests understanding of how shear affects image geometry

**Skill Progression:** This task bridges simple menu-based transforms (flip, rotate 90°) with more advanced parametric transformations requiring numeric input and geometric understanding.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Image → Transform → Shear` or `Layer → Transform → Shear`)
- **Dialog Management:** Work with the Shear dialog interface
- **Numeric Input:** Enter precise numeric values for shear magnitude
- **Preview Understanding:** Interpret the shear preview to assess transformation correctness
- **Confirmation Actions:** Apply the transformation using the "Shear" or "Transform" button
- **Value Units:** Understand whether shear is specified in pixels or degrees (varies by GIMP version)

### B. GIMP Knowledge
- **Transform Menu System:** Understand the organization of geometric transformation operations
- **Shear Concept:** Know what horizontal vs. vertical shear means geometrically
- **Transform Dialogs:** Navigate parameter input fields and preview systems
- **Clipping/Resize Options:** Understand how GIMP handles expanded image boundaries after shear
- **Layer vs. Image Transforms:** Distinguish between transforming entire image vs. single layer
- **Application Finalization:** Know that transform must be explicitly applied/confirmed

### C. Task-Specific Skills
- **Geometric Understanding:** Visualize how shear transformation affects image geometry
- **Direction Recognition:** Distinguish horizontal shear (X-axis slant) from vertical shear
- **Magnitude Judgment:** Understand that shear values represent the amount of slanting
- **Visual Prediction:** Anticipate how the image will look after shear is applied
- **Quality Assessment:** Recognize successful shear execution vs. incorrect parameters

## Task Steps

### 1. Initial Image Examination
- Examine the geometric pattern or portrait image that opens automatically in GIMP
- Note the current orientation and alignment of content
- Identify vertical and horizontal reference lines for assessing shear effect

### 2. Navigate to Shear Transform
- Click on "Image" (or "Layer") in the menu bar
- Navigate to "Transform" submenu
- Select "Shear" from the transform options

### 3. Shear Dialog Opens
- Wait for the Shear transformation dialog to appear
- Observe the preview showing how the shear will affect the image
- Identify the shear magnitude input fields (X and Y displacement)

### 4. Set Horizontal Shear Value
- Locate the horizontal shear parameter (often labeled "Shear magnitude X" or "Horizontal")
- Enter the specified value (e.g., 50 pixels or 15 degrees, depending on units)
- Ensure vertical shear remains at 0 (no Y-axis shear)

### 5. Preview Assessment
- Observe the preview showing the image slanted horizontally
- Verify that vertical lines now appear angled
- Confirm the shear direction and magnitude look correct

### 6. Apply Transformation
- Click "Shear" or "Transform" button to apply the transformation
- Wait for GIMP to process the geometric transformation
- Observe that the image canvas may expand to accommodate the sheared shape

### 7. Visual Verification
- Inspect the result to confirm horizontal slanting occurred
- Note that previously vertical elements now lean at an angle
- Verify that the transformation completed without errors

### 8. Automatic Export
- The post-task hook will automatically export the result as "sheared_image.png"

## Verification Strategy

### Verification Approach
The verifier uses **mathematical shear transformation and structural comparison** to validate results:

### A. Mathematical Shear Reference Generation
- **Affine Transform Matrix:** Applies mathematical shear transformation to original image
- **Precise Geometry:** Uses shear matrix `[[1, shear_x, 0], [0, 1, 0]]` for horizontal shear
- **Reference Creation:** Generates pixel-perfect expected result using PIL/OpenCV
- **Boundary Handling:** Accounts for canvas expansion and edge interpolation

### B. Structural Similarity Analysis
- **SSIM Comparison:** Compares result against mathematically generated reference
- **High Precision Threshold:** Requires SSIM ≥ 0.85 for successful shear verification
- **Tolerance for Interpolation:** Accounts for minor differences in edge smoothing algorithms
- **Multi-scale Assessment:** Evaluates similarity at different image scales

### C. Geometric Validation
- **Dimension Change Detection:** Verifies that image width changed appropriately (horizontal shear increases width)
- **Aspect Ratio Shift:** Confirms that aspect ratio changed as expected
- **Boundary Expansion:** Checks that canvas expanded to accommodate sheared geometry
- **Angle Measurement:** Validates that vertical elements now lean at approximately correct angle

### D. Quality Preservation
- **Content Integrity:** Ensures image content wasn't corrupted during transformation
- **Detail Preservation:** Verifies that important image details remain recognizable
- **No Unexpected Effects:** Checks that only shear was applied, not other transforms
- **Proper Interpolation:** Confirms smooth edges without stair-stepping artifacts

### Verification Checklist
- ✅ **Geometric Accuracy:** SSIM ≥ 0.85 with mathematically generated shear reference
- ✅ **Dimension Change:** Image width increased appropriately for horizontal shear magnitude
- ✅ **Image Modified:** Clear structural differences detected from original
- ✅ **Quality Maintained:** No significant corruption or unexpected artifacts

### Scoring System
- **100%:** Perfect shear transformation with SSIM ≥ 0.85 and all criteria met
- **75-99%:** Good shear with correct direction but minor magnitude or quality issues
- **50-74%:** Recognizable shear but with notable geometric or quality problems
- **0-49%:** Incorrect transformation, wrong direction, or failed operation

**Pass Threshold:** 75% (requires correct shear direction and reasonable magnitude)

### Mathematical Verification Details