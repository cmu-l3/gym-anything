# GIMP Arbitrary Rotation Task (`rotate_45@1`)

## Overview

This task tests an agent's ability to use GIMP's arbitrary rotation tool to rotate an image by a specific angle (45 degrees). Unlike the fixed 90°/180° rotation commands, this requires using the Rotate dialog with manual angle input, representing a more flexible transformation workflow common in photo straightening and creative composition.

## Rationale

**Why this task is valuable:**
- **Flexible Transform Introduction:** Bridges fixed-angle rotations (90°/180°) with arbitrary angle transformations
- **Parameter Input Skills:** Tests ability to enter precise numeric values in transformation dialogs
- **Photo Correction Workflow:** Simulates common operations like straightening tilted photos or artistic diagonal composition
- **Dialog Interaction:** Builds experience with GIMP's interactive transformation interfaces
- **Preview and Confirmation:** Teaches agents to work with real-time previews before applying changes
- **Real-world Relevance:** Arbitrary rotation is essential for correcting camera tilt, creating dynamic layouts, and artistic effects

**Skill Progression:** This task advances beyond simple menu-based transforms (flip, 90° rotate) to parameter-driven transformations, preparing agents for more complex geometric operations.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate to `Image → Transform → Arbitrary Rotation` or `Layer → Transform → Arbitrary Rotation`
- **Dialog Management:** Work with the Rotate transformation dialog interface
- **Numeric Input:** Enter specific angle values (45.0 degrees) in input fields
- **Unit Understanding:** Distinguish between degrees, radians, and other angle units
- **Preview Interpretation:** Understand real-time preview of rotation effect
- **Confirmation Actions:** Apply transformation using OK/Rotate button

### B. GIMP Knowledge
- **Transform System:** Understand GIMP's flexible transformation framework
- **Arbitrary Rotation:** Know that custom angles require the Rotate dialog (not quick transform menu)
- **Angle Conventions:** Understand positive angles rotate counter-clockwise, negative clockwise
- **Canvas vs. Layer Rotation:** Recognize difference between rotating layer content vs. entire image
- **Interpolation Awareness:** Basic understanding that rotation may introduce slight smoothing
- **Center of Rotation:** Understand that rotation typically occurs around image center

### C. Task-Specific Skills
- **Angle Estimation:** Understand what 45° rotation looks like visually
- **Diagonal Composition:** Recognize the aesthetic effect of 45° rotation (diamond orientation)
- **Precision Input:** Enter exact angle values rather than using visual adjustment
- **Result Validation:** Confirm that the rotation angle matches the specified value
- **Canvas Size Awareness:** Understand that rotation may require canvas expansion to avoid clipping

## Task Steps

### 1. Initial Image Examination
- Examine the landscape or object image that opens automatically in GIMP
- Note the current orientation and identify key visual features
- Prepare to rotate the entire image by 45 degrees

### 2. Access Rotation Dialog
- Navigate to `Image → Transform → Arbitrary Rotation` in the menu bar
- Alternative: Use `Layer → Transform → Rotate` if working with layer
- Wait for the Rotate dialog to open

### 3. Angle Input
- Locate the angle input field in the Rotate dialog
- Clear any default value if present
- Enter `45` (or `45.0`) degrees in the angle field
- Ensure the unit is set to degrees (not radians)

### 4. Preview Observation (Optional)
- If available, observe the preview showing the 45° rotation effect
- Verify that the image will be rotated to a diamond orientation
- Confirm the rotation direction is as expected (counter-clockwise)

### 5. Apply Rotation
- Click "Rotate" or "OK" button to apply the transformation
- Wait for GIMP to process the rotation operation
- Observe that the image is now rotated 45° from its original orientation

### 6. Result Assessment
- Verify that the image appears in diamond orientation
- Confirm that no excessive clipping or quality loss occurred
- Check that rotation direction and angle appear correct

### 7. Automatic Export
- The post-task hook will automatically export the result as "rotated_45.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **mathematical rotation detection and angle measurement** to validate the transformation:

### A. Rotation Angle Detection
- **Feature-based Analysis:** Uses image feature detection to identify rotation angle
- **Edge Orientation Analysis:** Analyzes dominant edge angles in the image to detect rotation
- **Cross-correlation Method:** Compares rotated versions to find best match angle
- **Mathematical Precision:** Measures rotation angle with ±3° tolerance for practical accuracy

### B. Rotation Quality Assessment
- **Full Image Rotation:** Confirms entire image was rotated (not just cropped or resized)
- **Interpolation Quality:** Checks that rotation didn't introduce excessive artifacts
- **Aspect Ratio Preservation:** Verifies proper geometric transformation occurred
- **Canvas Size Adjustment:** Confirms canvas was expanded appropriately to fit rotated image

### C. Visual Validation
- **Diamond Orientation Check:** Validates that horizontal/vertical elements are now diagonal
- **Corner Analysis:** Examines image corners to detect diagonal presentation
- **No Identity Transform:** Ensures rotation actually occurred (not 0° or 360°)

### Verification Checklist
- ✅ **Rotation Angle Correct:** Detected rotation is 45° ± 3° tolerance
- ✅ **Image Fully Transformed:** Entire image rotated, not just portions
- ✅ **Quality Preserved:** No excessive artifacts or degradation
- ✅ **Proper Geometry:** Image maintains proper aspect ratio and proportions
- ✅ **Image Modified:** Clear difference from original orientation detected

### Scoring System
- **100%:** Perfect 45° rotation with angle within ±1° and excellent quality
- **85-99%:** Very good rotation within ±3° with minor quality issues
- **70-84%:** Acceptable rotation within ±5° but with noticeable imperfections
- **50-69%:** Rotation detected but angle significantly off or quality problems
- **0-49%:** Incorrect rotation angle (>±8°) or transformation failed

**Pass Threshold:** 85% (requires accurate 45° rotation with good quality)

## Technical Implementation

### Files Structure