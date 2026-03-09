# GIMP 90-Degree Rotation Task (`rotate_90@1`)

## Overview

This task tests an agent's ability to use GIMP's transform tools to rotate an image by 90 degrees clockwise. The agent must navigate to the appropriate transform menu, apply the rotation operation, and ensure the resulting image is properly rotated with correctly swapped dimensions. This represents a fundamental geometric transformation commonly used in image editing workflows for orientation correction and creative composition.

## Rationale

**Why this task is valuable:**
- **Geometric Transform Mastery:** Introduces rotation concepts alongside existing mirroring operations
- **Spatial Reasoning:** Tests understanding of clockwise rotation and coordinate system changes
- **Dimension Awareness:** Requires understanding that rotation swaps width and height dimensions  
- **Menu Navigation Reinforcement:** Builds familiarity with GIMP's transform menu structure
- **Orientation Correction:** Represents common real-world use case for fixing image orientation
- **Creative Composition:** Essential skill for design and artistic image manipulation

**Skill Progression:** This task complements the horizontal_mirror task by introducing rotational transforms, building toward more complex geometric operations like arbitrary angle rotation and perspective correction.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Image → Transform → Rotate 90° clockwise`)
- **Transform Selection:** Choose the correct rotation direction among available options
- **Visual Assessment:** Recognize correct 90-degree clockwise rotation result
- **Immediate Application:** Understand that rotation applies instantly without additional dialogs
- **Result Verification:** Compare rotated result with expected orientation

### B. GIMP Knowledge
- **Transform Menu System:** Understand organization of GIMP's geometric transformation tools
- **Rotation Operations:** Distinguish between different rotation angles and directions
- **Coordinate System:** Understand how GIMP handles image coordinates during rotation
- **Dimension Changes:** Know that 90-degree rotation swaps image width and height
- **Quality Preservation:** Understand that 90-degree rotations are lossless operations
- **Canvas Behavior:** Know how GIMP handles canvas size changes during rotation

### C. Task-Specific Skills
- **Clockwise Understanding:** Visually understand what "90 degrees clockwise" means
- **Orientation Assessment:** Recognize proper vertical-to-horizontal or horizontal-to-vertical transformation
- **Reference Point Recognition:** Understand how image content should appear after rotation
- **Quality Verification:** Confirm no image degradation occurred during transformation
- **Dimension Logic:** Understand the mathematical relationship between original and rotated dimensions

## Task Steps

### 1. Initial Image Analysis
- Examine the landscape image that opens automatically in GIMP
- Note the current orientation (typically wider than tall)
- Identify distinctive features that will help verify correct rotation (asymmetric elements, text, directional objects)
- Observe current dimensions in the status bar or image window

### 2. Navigate to Transform Menu
- Click on "Image" in the menu bar to open the Image menu
- Locate and hover over "Transform" to open the transform submenu
- Identify the rotation options within the transform submenu

### 3. Select Clockwise 90-Degree Rotation
- Click on "Rotate 90° clockwise" from the Transform submenu
- Observe that the operation applies immediately without additional dialogs
- Note the visual change in image orientation

### 4. Verify Rotation Result
- Confirm that the image appears rotated 90 degrees to the right
- Verify that what was previously on the left side is now at the bottom
- Check that what was at the top is now on the right side
- Observe that the image canvas dimensions have been swapped

### 5. Dimension Verification
- Check that the image width and height have been swapped appropriately
- Confirm that content fits properly within the new canvas dimensions
- Ensure no cropping or content loss occurred during rotation

### 6. Quality Assessment
- Verify that image sharpness and detail are preserved
- Confirm no artifacts or distortions were introduced
- Ensure colors and contrast remain unchanged

### 7. Automatic Export
- The post-task hook will automatically export the result as "rotated_landscape.png"

## Verification Strategy

### Verification Approach
The verifier uses **pixel-perfect mathematical rotation comparison** with dimensional validation:

### A. Reference Rotation Generation
- **Mathematical Transform:** Creates a perfect 90-degree clockwise rotation reference using PIL's `rotate(90, expand=True)`
- **Pixel-level Accuracy:** Ensures every pixel is mapped to its correct rotated position
- **Dimension Handling:** Properly swaps width/height dimensions during rotation
- **Quality Preservation:** Uses lossless rotation algorithms for reference generation

### B. Structural Similarity Analysis
- **SSIM Comparison:** Uses Structural Similarity Index Measure for robust image comparison
- **High Precision Threshold:** Requires SSIM ≥ 0.95 for nearly identical structural match
- **Rotation Verification:** SSIM specifically validates the rotational transformation accuracy
- **Quality Assessment:** Ensures no significant quality degradation during rotation

### C. Dimensional Validation
- **Size Swap Verification:** Confirms that original width becomes new height and vice versa
- **Exact Dimension Match:** Validates precise dimensional transformation
- **Canvas Integrity:** Ensures proper canvas size adjustment to accommodate rotated content
- **No Content Loss:** Verifies that all original image content is preserved in rotated form

### D. Transformation Correctness
- **Direction Validation:** Confirms rotation is specifically clockwise (not counter-clockwise)
- **Angle Precision:** Ensures rotation is exactly 90 degrees (not 89° or 91°)
- **Content Mapping:** Verifies that specific image regions moved to expected positions
- **Reference Point Tracking:** Uses corner and edge analysis to validate proper rotation

### Verification Checklist
- ✅ **Perfect Rotation Match:** SSIM ≥ 0.95 with mathematically generated 90° clockwise rotation
- ✅ **Dimensions Properly Swapped:** Width and height correctly exchanged
- ✅ **Image Modified:** Clear evidence of rotational transformation from original
- ✅ **Quality Preserved:** No significant degradation or artifacts introduced

### Scoring System
- **100%:** Perfect 90-degree clockwise rotation with SSIM ≥ 0.95 and correct dimensions
- **75-99%:** Very good rotation with minor precision issues
- **50-74%:** Recognizable rotation but with notable quality or angle issues
- **0-49%:** Incorrect rotation angle, wrong direction, or failed operation

**Pass Threshold:** 75% (requires accurate 90-degree clockwise rotation)

### Mathematical Verification Details
```python
# Rotation Verification Process
def verify_90_degree_rotation(original_img, result_img):
    # Generate perfect reference rotation (90 degrees clockwise)
    reference_rotated = original_img.rotate(90, expand=True)
    
    # Verify dimensions are swapped correctly
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    ref_w, ref_h = reference_rotated.size
    
    dimensions_correct = (result_w == orig_h and result_h == orig_w and 
                         result_w == ref_w and result_h == ref_h)
    
    # Calculate structural similarity
    from skimage.metrics import structural_similarity as ssim
    ssim_score = ssim(np.array(reference_rotated), np.array(result_img), 
                     multichannel=True, channel_axis=2)
    
    return ssim_score >= 0.95 and dimensions_correct
```

## Technical Implementation

### Files Structure
```
rotate_90/
├── task.json                # Task configuration (5 steps, 60s timeout)
├── setup_rotate_task.sh     # Downloads landscape image, launches GIMP
├── export_rotate.sh         # Automates export as "rotated_landscape"
├── verifier.py             # SSIM and dimension-based rotation verification
└── README.md              # This documentation
```

### Verification Features
- **Mathematical Precision:** Uses pixel-perfect reference generation for rotation comparison
- **Dual Validation:** Combines SSIM analysis with dimensional verification
- **Direction Accuracy:** Specifically validates clockwise rotation vs other directions
- **Quality Assurance:** Ensures rotation maintains image quality and completeness
- **Robust Comparison:** Handles minor compression differences while maintaining accuracy

### Advanced Validation
- **Corner Tracking:** Analyzes corner pixel positions to verify rotation direction
- **Content Mapping:** Validates that specific image regions appear in expected rotated positions
- **Edge Analysis:** Uses edge detection to confirm proper geometric transformation
- **Fallback Methods:** Includes alternative verification approaches for edge cases

### Error Handling
- **Missing File Recovery:** Uses shared verification utilities for fallback file search
- **Format Flexibility:** Handles various image formats transparently
- **Quality Tolerance:** Accommodates minor export compression while maintaining precision
- **Clear Diagnostics:** Provides detailed feedback on rotation accuracy and dimension correctness

This task introduces essential rotational transform skills that complement existing mirroring capabilities, preparing agents for more advanced geometric operations while maintaining the simplicity and clear verification standards of other foundational GIMP tasks.