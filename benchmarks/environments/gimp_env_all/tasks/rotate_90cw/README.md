# GIMP 90-Degree Clockwise Rotation Task (`rotate_90cw@1`)

## Overview

This task tests an agent's ability to use GIMP's transform tools to rotate an image 90 degrees clockwise. The agent must navigate to the appropriate transform menu, select the correct rotation option, and ensure the image is rotated to the proper orientation. This represents a fundamental image orientation operation commonly used for correcting photo orientation and layout adjustments.

## Rationale

**Why this task is valuable:**
- **Transform Tool Progression:** Builds on existing mirror operations with rotational transforms
- **Spatial Reasoning:** Tests understanding of clockwise rotation and orientation concepts
- **Menu Navigation:** Reinforces GIMP's transform menu structure with different options
- **Orientation Correction:** Common real-world use case for photo editing and document preparation
- **Geometric Understanding:** Develops concepts needed for more complex rotations and transforms
- **Immediate Feedback:** Provides clear, verifiable results for successful completion

**Skill Progression:** This task extends transform capabilities beyond mirroring to rotational operations, maintaining simplicity while expanding geometric transformation skills.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through `Image → Transform → Rotate 90° clockwise`
- **Precise Selection:** Choose correct rotation direction among multiple options
- **Visual Confirmation:** Recognize proper 90-degree clockwise orientation
- **Result Assessment:** Verify the image appears in correct rotated position

### B. GIMP Knowledge
- **Transform Menu System:** Navigate GIMP's rotation options within transform submenu
- **Rotation Operations:** Distinguish between clockwise and counter-clockwise rotations
- **Immediate Application:** Understand that rotation applies instantly without dialogs
- **Coordinate System:** Understand how GIMP handles image coordinate transformation
- **Dimension Changes:** Recognize that rotation swaps width/height dimensions

### C. Task-Specific Skills
- **Spatial Orientation:** Understand what 90-degree clockwise rotation means visually
- **Direction Recognition:** Distinguish clockwise from counter-clockwise rotation
- **Orientation Assessment:** Recognize when an image has been properly rotated
- **Quality Verification:** Confirm no quality loss during rotation operation

## Task Steps

### 1. Initial Image Examination
- Examine the portrait-oriented flower image that opens in GIMP
- Note distinctive features that will help verify proper rotation (flower orientation, stem direction)
- Identify the current orientation (portrait format with flower pointing upward)

### 2. Navigate to Transform Menu
- Click "Image" in the menu bar to open the Image menu
- Hover over "Transform" to open the transform submenu
- Locate the rotation options within the submenu

### 3. Select Clockwise Rotation
- Click "Rotate 90° clockwise" from the transform submenu
- Observe that the rotation applies immediately without additional dialogs
- Note the image orientation change from portrait to landscape

### 4. Verify Transformation
- Confirm the image appears rotated 90 degrees to the right
- Verify that the former top edge (flower head) is now on the right side
- Check that image dimensions have swapped (width/height reversed)

### 5. Quality Check
- Ensure no image degradation occurred during rotation
- Verify all details remain crisp and properly positioned
- Confirm the rotation appears natural and correct

### 6. Automatic Export
- The post-task hook will automatically export the result as "flower_rotated_90cw.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **mathematical rotation analysis** with reference comparison:

### A. Reference Generation
- **Perfect Rotation:** Creates mathematically correct 90° clockwise reference using PIL's `rotate(-90, expand=True)`
- **Dimension Verification:** Confirms width/height swap occurred correctly (portrait → landscape)
- **Pixel-Perfect Accuracy:** Generates exact expected result for precise comparison

### B. Structural Similarity Analysis
- **SSIM Comparison:** Uses Structural Similarity Index with high threshold (≥0.95)
- **Rotation Validation:** Ensures result matches expected 90° clockwise transformation
- **Quality Preservation:** Verifies no significant quality loss during rotation

### C. Geometric Validation
- **Dimension Swap:** Confirms original width became new height, height became new width
- **Orientation Check:** Validates proper clockwise rotation direction
- **Corner Analysis:** Verifies corner pixels are in correct rotated positions
- **Aspect Ratio:** Ensures proper aspect ratio transformation occurred

### D. Change Detection
- **Modification Verification:** Confirms image was actually transformed from original
- **Direction Validation:** Ensures clockwise (not counter-clockwise) rotation occurred
- **Completeness Check:** Verifies entire image was rotated uniformly

### Verification Checklist
- ✅ **Perfect Rotation Match:** SSIM ≥ 0.95 with mathematically generated 90° clockwise rotation
- ✅ **Dimensions Swapped:** Width and height properly exchanged (portrait → landscape)
- ✅ **Image Modified:** Clear structural differences from original detected
- ✅ **Quality Maintained:** No significant artifacts or quality degradation

### Scoring System
- **100%:** Perfect 90° clockwise rotation with SSIM ≥ 0.95 and all criteria met
- **75-99%:** Good rotation with minor quality or positioning issues
- **50-74%:** Recognizable rotation but with notable accuracy problems
- **0-49%:** Incorrect rotation direction or failed operation

**Pass Threshold:** 75% (requires high-quality 90° clockwise rotation)

### Mathematical Verification Details
```python
# Rotation Reference Generation
def generate_rotation_reference(original_img):
    # 90° clockwise = -90° in PIL rotation (counterclockwise is positive)
    reference_rotated = original_img.rotate(-90, expand=True)
    return reference_rotated

# Dimension Validation
def verify_dimension_swap(original_img, result_img):
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # After 90° clockwise rotation: original width → result height, original height → result width
    return (orig_w == result_h) and (orig_h == result_w)
```

## Technical Implementation

### Files Structure
```
rotate_90cw/
├── task.json               # Task configuration (5 steps, 60s timeout)
├── setup_rotate_task.sh    # Downloads portrait flower image, launches GIMP
├── export_rotate.sh        # Automates export as "flower_rotated_90cw"
├── verifier.py            # SSIM-based rotation verification with dimension checks
└── README.md             # This documentation
```

### Verification Features
- **Mathematical Precision:** Pixel-perfect reference generation using PIL rotation
- **Robust Similarity Analysis:** SSIM provides reliable structural comparison tolerating minor compression artifacts
- **Dimension Validation:** Explicitly checks that width/height swap occurred correctly
- **Efficient Processing:** Fast verification suitable for automated training workflows
- **Clear Feedback:** Comprehensive scoring with detailed similarity and dimension metrics

### Error Handling
- **Missing File Recovery:** Uses shared verification utilities for fallback file search
- **Format Tolerance:** Handles various image formats and compression levels
- **Quality Preservation:** Distinguishes between compression artifacts and rotation errors
- **Graceful Degradation:** Provides informative error messages for debugging rotation issues

This task provides essential spatial transformation skills that complement existing mirror operations while introducing rotational concepts fundamental to image editing workflows. The 90-degree clockwise rotation is particularly common for correcting portrait/landscape orientation in photography and document preparation.