# GIMP Horizontal Mirror Task (`horizontal_mirror@1`)

## Overview

This task tests an agent's ability to use GIMP's transform tools to create a horizontal mirror (flip) of an image. The agent must navigate to the appropriate transform tool, apply the horizontal flip operation, and ensure the resulting image is a perfect mirror reflection of the original. This represents one of the most fundamental transform operations in digital image editing.

## Rationale

**Why this task is valuable:**
- **Transform Tool Introduction:** Introduces GIMP's extensive transform tool system in its simplest form
- **Spatial Understanding:** Tests the agent's comprehension of horizontal vs. vertical orientation
- **Menu Navigation:** Builds familiarity with GIMP's hierarchical menu structure
- **Immediate Feedback:** Provides clear, binary success criteria that are easy to verify
- **Foundation Operation:** Establishes concepts needed for more complex transformations (rotate, scale, perspective)
- **Common Use Case:** Horizontal flips are frequently used in design composition and image correction

**Skill Progression:** This task serves as the perfect introduction to GIMP's transform capabilities, building confidence before progressing to more complex geometric operations.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Image → Transform → Flip Horizontal`)
- **Precise Selection:** Click on the correct menu item among similar options
- **Visual Confirmation:** Recognize when the transform has been successfully applied
- **Result Assessment:** Compare before/after to verify correct transformation

### B. GIMP Knowledge
- **Transform Menu System:** Understand the organization of GIMP's transform operations
- **Flip Operations:** Distinguish between horizontal and vertical flip options
- **Immediate Application:** Recognize that flips apply instantly without additional dialogs
- **Image Coordinate System:** Understand GIMP's x/y axis orientation for transforms
- **Non-destructive Preview:** Know that transforms show immediate results in the canvas

### C. Task-Specific Skills
- **Spatial Orientation:** Understand what "horizontal mirror" means visually
- **Direction Recognition:** Distinguish left-to-right flip from other orientations
- **Symmetry Assessment:** Recognize when an image has been properly mirrored
- **Quality Verification:** Confirm that no image degradation occurred during transform

## Task Steps

### 1. Initial Image Examination
- Examine the berry image that opens automatically in GIMP
- Note distinctive features that will help verify the flip (asymmetric elements, text, directional objects)
- Identify left and right sides of the image for comparison after transformation

### 2. Navigate to Transform Menu
- Click on "Image" in the menu bar to open the Image menu
- Locate and hover over "Transform" to open the transform submenu
- Identify the flip options within the transform submenu

### 3. Select Horizontal Flip
- Click on "Flip Horizontal" from the Transform submenu
- Observe that the operation applies immediately without additional dialogs

### 4. Verify Transformation
- Compare the result with your mental image of the original
- Confirm that left and right sides have been swapped
- Verify that the image appears as a mirror reflection

### 5. Quality Check
- Ensure no image degradation or artifacts were introduced
- Confirm that all details remain sharp and properly positioned
- Verify that the image dimensions remain unchanged

### 6. Automatic Export
- The post-task hook will automatically export the result as "berry_mirror.png"

## Verification Strategy

### Verification Approach
The verifier uses **pixel-perfect mathematical comparison** with the expected mirror result:

### A. Mirror Generation
- **Reference Creation:** Creates a mathematically perfect horizontal mirror of the original image
- **Pixel-level Flip:** Uses PIL's `Image.FLIP_LEFT_RIGHT` for precise reference generation
- **Exact Positioning:** Ensures every pixel is mapped to its correct mirror position

### B. Structural Similarity Analysis
- **SSIM Comparison:** Uses Structural Similarity Index Measure for robust image comparison
- **High Precision Threshold:** Requires SSIM ≥ 0.95 for nearly identical structural match
- **Noise Tolerance:** SSIM accounts for minor compression artifacts while detecting major differences
- **Perceptual Accuracy:** SSIM correlates well with human visual perception of similarity

### C. Dimension Verification
- **Size Preservation:** Confirms that image dimensions remain exactly the same
- **Format Integrity:** Ensures proper export format and file structure
- **Quality Maintenance:** Verifies no significant compression or quality loss occurred

### D. Change Detection
- **Modification Verification:** Confirms the image was actually transformed from the original
- **Direction Validation:** Ensures the change represents a horizontal (not vertical) flip
- **Completeness Check:** Verifies the entire image was transformed, not just portions

### Verification Checklist
- ✅ **Perfect Mirror Match:** SSIM ≥ 0.95 with mathematically generated horizontal flip
- ✅ **Dimensions Preserved:** Output image has same width and height as input
- ✅ **Image Modified:** Clear structural differences detected from original
- ✅ **Quality Maintained:** No significant degradation or artifacts introduced

### Scoring System
- **100%:** Perfect horizontal mirror with SSIM ≥ 0.95 and all criteria met
- **75-99%:** Very good mirror match with minor imperfections
- **50-74%:** Recognizable as mirror but with notable quality issues
- **0-49%:** Incorrect transformation or failed operation

**Pass Threshold:** 75% (requires high-quality horizontal flip)

### Mathematical Verification Details
```python
# Mirror Comparison Process
def verify_horizontal_mirror(original_img, result_img):
    # Generate perfect reference mirror
    reference_mirror = original_img.transpose(Image.FLIP_LEFT_RIGHT)
    
    # Calculate structural similarity
    from skimage.metrics import structural_similarity as ssim
    ssim_score = ssim(np.array(reference_mirror), np.array(result_img), 
                     multichannel=True, channel_axis=2)
    
    return ssim_score >= 0.95
```

## Technical Implementation

### Files Structure
```
horizontal_mirror/
├── task.json                # Task configuration (5 steps, 60s timeout)
├── setup_mirror_task.sh     # Downloads berry image, launches GIMP
├── export_mirror.sh         # Automates export as "berry_mirror"
├── verifier.py             # SSIM-based mirror verification
└── README.md              # This documentation
```

### Verification Features
- **Mathematical Precision:** Uses pixel-perfect reference generation for comparison
- **Robust Similarity Analysis:** SSIM provides reliable structural comparison
- **Efficient Processing:** Fast verification suitable for automated training
- **Clear Feedback:** Binary pass/fail with detailed similarity scores
- **Format Flexibility:** Handles various image formats and compression levels

### Error Handling
- **Missing File Recovery:** Uses shared verification utilities for fallback file search
- **Format Conversion:** Handles different image formats transparently
- **Quality Tolerance:** Accommodates minor compression differences while maintaining accuracy
- **Graceful Degradation:** Provides informative error messages for debugging
