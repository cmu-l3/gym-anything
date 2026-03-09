# GIMP Color Inversion Task (`color_invert@1`)

## Overview

This task tests an agent's ability to use GIMP's color adjustment tools to invert all colors in an image. The agent must navigate to the appropriate color menu, apply the invert operation, and ensure the resulting image shows a perfect color negative of the original. This represents one of the most fundamental color manipulation operations in digital image editing, commonly used for artistic effects and technical analysis.

## Rationale

**Why this task is valuable:**
- **Color Menu Introduction:** Introduces GIMP's comprehensive color adjustment system in its simplest form
- **Color Theory Foundation:** Tests understanding of color inversion and negative image concepts
- **Instant Feedback Operation:** Provides immediate, clear visual results that are easy to assess
- **Creative Application:** Color inversion is used in artistic workflows, night vision effects, and technical imaging
- **Menu Navigation Skills:** Builds familiarity with GIMP's color adjustment menu hierarchy
- **Mathematical Precision:** Represents a perfect mathematical transformation (255-RGB values)

**Skill Progression:** This task serves as the perfect introduction to GIMP's color manipulation capabilities, establishing concepts needed for more advanced color adjustments like curves, levels, and selective color modifications.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Colors → Invert`)
- **Precise Selection:** Click on the correct menu item among numerous color options
- **Visual Assessment:** Recognize when the color inversion has been successfully applied
- **Result Verification:** Compare before/after to confirm complete color transformation

### B. GIMP Knowledge
- **Colors Menu System:** Understand the organization of GIMP's color adjustment operations
- **Invert Operation:** Know that invert creates a perfect color negative of the image
- **Immediate Application:** Recognize that color invert applies instantly without additional dialogs
- **Color Space Understanding:** Understand how RGB values are mathematically inverted
- **Non-destructive Preview:** Know that color adjustments show immediate results in the canvas

### C. Task-Specific Skills
- **Color Negative Concept:** Understand what "color inversion" means visually
- **Mathematical Transformation:** Recognize that inversion means 255 minus each RGB component
- **Complete Coverage:** Ensure the entire image is affected by the transformation
- **Quality Preservation:** Confirm that no image degradation occurred during the process

## Task Steps

### 1. Initial Image Examination
- Examine the colorful image that opens automatically in GIMP
- Note the dominant colors and bright areas that will show dramatic change when inverted
- Identify distinctive color elements to help verify the inversion (sky, grass, objects)

### 2. Navigate to Colors Menu
- Click on "Colors" in the menu bar to open the Colors menu
- Observe the extensive list of color adjustment options available
- Locate the "Invert" option within the color adjustment menu

### 3. Apply Color Inversion
- Click on "Invert" from the Colors menu
- Observe that the operation applies immediately without additional dialogs
- Notice the dramatic color transformation across the entire image

### 4. Verify Color Transformation
- Compare the result with the original (mental comparison)
- Confirm that bright colors became dark and dark colors became bright
- Verify that the image appears as a color negative with all hues inverted

### 5. Quality Assessment
- Ensure no image degradation or artifacts were introduced
- Confirm that all details remain sharp and properly defined
- Verify that the image dimensions and overall structure remain unchanged

### 6. Automatic Export
- The post-task hook will automatically export the result as "inverted_colors.png"

## Verification Strategy

### Verification Approach
The verifier uses **pixel-perfect mathematical validation** of the color inversion transformation:

### A. Mathematical Inversion Verification
- **Reference Generation:** Creates a mathematically perfect color inversion of the original image
- **RGB Inversion Formula:** Applies the transformation (R', G', B') = (255-R, 255-G, 255-B) to each pixel
- **Pixel-level Accuracy:** Ensures every pixel is correctly transformed according to inversion mathematics
- **Exact Positioning:** Verifies that spatial relationships remain unchanged

### B. Structural Similarity Analysis
- **SSIM Comparison:** Uses Structural Similarity Index Measure for robust image comparison
- **High Precision Threshold:** Requires SSIM ≥ 0.95 between result and mathematically generated reference
- **Noise Tolerance:** SSIM accounts for minor compression artifacts while detecting incorrect transformations
- **Perceptual Accuracy:** SSIM correlates well with human visual perception of inversion quality

### C. Transformation Completeness
- **Full Image Coverage:** Confirms that every pixel in the image was affected by the inversion
- **Color Range Validation:** Ensures both dark and bright regions were properly inverted
- **Uniformity Check:** Verifies consistent transformation across the entire image area
- **Edge Preservation:** Confirms that image boundaries and details remain intact

### D. Quality and Integrity Assessment
- **Dimension Preservation:** Confirms that image dimensions remain exactly the same
- **Format Integrity:** Ensures proper export format and file structure maintenance
- **No Artifacts:** Verifies that inversion didn't introduce unwanted visual artifacts
- **Complete Transformation:** Ensures the image is genuinely different from the original

### Verification Checklist
- ✅ **Perfect Inversion Match:** SSIM ≥ 0.95 with mathematically generated color inversion
- ✅ **Dimensions Preserved:** Output image has same width and height as input
- ✅ **Complete Transformation:** Every pixel shows evidence of proper color inversion
- ✅ **Quality Maintained:** No degradation or artifacts introduced during transformation

### Scoring System
- **100%:** Perfect color inversion with SSIM ≥ 0.95 and all criteria met
- **75-99%:** Very good inversion with minor imperfections or compression artifacts
- **50-74%:** Recognizable as color inversion but with notable quality issues
- **0-49%:** Incorrect transformation, partial inversion, or failed operation

**Pass Threshold:** 75% (requires high-quality complete color inversion)

### Mathematical Verification Details
```python
# Color Inversion Verification Process
def verify_color_inversion(original_img, result_img):
    # Generate perfect reference inversion
    original_array = np.array(original_img.convert('RGB'))
    reference_inversion = 255 - original_array
    reference_img = Image.fromarray(reference_inversion.astype(np.uint8))
    
    # Calculate structural similarity
    from skimage.metrics import structural_similarity as ssim
    result_array = np.array(result_img.convert('RGB'))
    ssim_score = ssim(np.array(reference_img), result_array, 
                     multichannel=True, channel_axis=2)
    
    return ssim_score >= 0.95

# Pixel-wise Inversion Check
def check_inversion_accuracy(original_img, result_img):
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Perfect inversion should satisfy: result + original = 255 for each channel
    inversion_sum = orig_array.astype(np.int16) + result_array.astype(np.int16)
    expected_sum = np.full_like(inversion_sum, 255)
    
    # Allow small tolerance for compression artifacts
    difference = np.abs(inversion_sum - expected_sum)
    accuracy = np.mean(difference <= 2)  # 2-unit tolerance per channel
    
    return accuracy >= 0.95  # 95% of pixels must be accurately inverted
```

## Technical Implementation

### Files Structure
```
color_invert/
├── task.json                # Task configuration (5 steps, 60s timeout)
├── setup_invert_task.sh     # Downloads colorful test image, launches GIMP
├── export_invert.sh         # Automates export as "inverted_colors"
├── verifier.py             # Mathematical inversion verification
└── README.md              # This documentation
```

### Verification Features
- **Mathematical Precision:** Uses pixel-perfect mathematical inversion for reference generation
- **Dual Verification Method:** Combines SSIM structural analysis with pixel-wise mathematical validation
- **Compression Tolerance:** Handles minor artifacts from image compression while maintaining accuracy
- **Clear Binary Results:** Provides definitive pass/fail with detailed similarity scores
- **Format Flexibility:** Handles various image formats and bit depths transparently

### Error Handling
- **Missing File Recovery:** Uses shared verification utilities for robust file discovery
- **Format Conversion:** Handles different image formats and color spaces automatically
- **Quality Assessment:** Distinguishes between compression artifacts and genuine transformation errors
- **Informative Feedback:** Provides detailed diagnostic information for debugging and improvement

### Mathematical Foundation
The verification is based on the fundamental color inversion formula:
- **RGB Inversion:** For each pixel (R, G, B), the inverted pixel is (255-R, 255-G, 255-B)
- **Additive Property:** Original + Inverted = (255, 255, 255) for perfect inversion
- **Bijective Transformation:** Inversion is its own inverse - inverting twice returns to original
- **Structural Preservation:** Spatial relationships and edge information remain unchanged

This task provides essential introduction to GIMP's color manipulation system while maintaining the simplicity and clear verification criteria that characterize the fundamental skill-building tasks in this educational sequence.