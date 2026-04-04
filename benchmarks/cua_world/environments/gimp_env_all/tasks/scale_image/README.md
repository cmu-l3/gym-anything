# GIMP Scale Image Task (`scale_image@1`)

## Overview

This task tests an agent's ability to use GIMP's scale functionality to resize an image to specific dimensions. The agent must navigate to the Scale Image dialog, input precise dimensions, and apply the scaling operation while maintaining image quality. This represents one of the most fundamental image editing operations used in web design, print preparation, and digital content creation workflows.

## Rationale

**Why this task is valuable:**
- **Fundamental Operation:** Image scaling is essential in virtually every digital media workflow
- **Dimension Control:** Tests precision in working with specific pixel dimensions and measurements  
- **Dialog Interaction:** Introduces GIMP's parameter-based transformation dialogs
- **Aspect Ratio Understanding:** Tests knowledge of proportional vs. non-proportional scaling
- **Quality Considerations:** Builds awareness of scaling effects on image quality
- **Professional Workflow:** Common in web design, social media, print prep, and archival workflows

**Skill Progression:** This task establishes core resize concepts needed for more advanced image manipulation and prepares agents for other dimension-based operations.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate to `Image → Scale Image` through menu hierarchy
- **Dialog Management:** Work with the Scale Image parameter dialog effectively
- **Numerical Input:** Enter precise pixel dimensions in width and height fields
- **Chain Link Control:** Understand and manipulate aspect ratio constraint controls
- **Button Interaction:** Apply changes using the "Scale" button
- **Parameter Validation:** Recognize when dimensions are acceptable for scaling

### B. GIMP Knowledge
- **Image Menu System:** Navigate GIMP's image transformation menu structure
- **Scale Dialog Interface:** Understand width, height, and aspect ratio controls
- **Chain Link Concept:** Know how the chain icon controls proportional scaling
- **Dimension Units:** Work with pixel measurements and understand their impact
- **Quality Implications:** Understand that scaling can affect image sharpness and quality
- **Immediate Application:** Know that scaling applies directly to the current image

### C. Task-Specific Skills
- **Dimension Planning:** Calculate appropriate scaling for specific use cases
- **Aspect Ratio Decisions:** Choose when to maintain vs. break aspect ratio constraints
- **Quality Assessment:** Evaluate whether scaled result meets quality requirements
- **Size Optimization:** Understand relationship between image dimensions and file size
- **Output Validation:** Confirm that final dimensions match specified requirements

## Task Steps

### 1. Initial Image Assessment
- Examine the sample image that opens automatically in GIMP
- Note the current image dimensions (visible in window title or Image → Print Size)
- Prepare to scale to the target dimensions: 600x400 pixels

### 2. Access Scale Dialog
- Navigate to `Image → Scale Image` in the menu bar
- Wait for the Scale Image dialog to open
- Observe the current width and height values displayed

### 3. Configure Target Dimensions
- Identify the width and height input fields in the dialog
- Note the current state of the chain link icon (linked/unlinked for aspect ratio)
- Prepare to enter the specific target dimensions

### 4. Set Width Dimension
- Click in the width field and clear the current value
- Enter `600` as the target width in pixels
- Observe how the height field responds based on chain link state

### 5. Set Height Dimension
- If needed, click the chain link to unlink aspect ratio (break the chain)
- Click in the height field and enter `400` as the target height in pixels
- Ensure both dimensions are set to exactly 600x400 pixels

### 6. Apply Scaling Operation
- Review the final dimensions in the dialog (600x400)
- Click the "Scale" button to apply the transformation
- Wait for the scaling operation to complete

### 7. Verify Result
- Observe that the image canvas now displays at the new dimensions
- Note that the image has been resized to fill the new proportions
- Check that the transformation completed successfully

### 8. Automatic Export
- The post-task hook will automatically export the result as "scaled_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **precise dimension measurement** combined with **quality preservation analysis**:

### A. Dimension Verification
- **Exact Measurement:** Verifies that output image dimensions are exactly 600x400 pixels
- **No Tolerance:** Scaling should achieve precise pixel dimensions with no deviation
- **Format Independence:** Checks dimensions regardless of output file format
- **Efficient Detection:** Uses PIL image properties for fast dimension checking

### B. Scaling Validation
- **Size Change Detection:** Confirms that image dimensions actually changed from original
- **Proportional Analysis:** Analyzes how the scaling affected image aspect ratio
- **Scaling Factor Calculation:** Computes the scaling ratio to ensure reasonable transformation
- **Content Preservation:** Ensures the image content was scaled, not cropped or padded

### C. Quality Assessment
- **Content Integrity:** Verifies that image content remains recognizable after scaling
- **Detail Preservation:** Checks that essential image features are maintained
- **Artifact Detection:** Identifies any obvious scaling artifacts or distortions
- **Color Fidelity:** Ensures scaling didn't introduce unexpected color changes

### D. Process Validation
- **Proper Scaling Method:** Confirms the image was actually scaled (not just canvas-resized)
- **Complete Transformation:** Ensures the entire image was affected by the scaling operation
- **No Cropping:** Validates that scaling occurred without unwanted cropping effects

### Verification Checklist
- ✅ **Exact Dimensions:** Output image is precisely 600x400 pixels
- ✅ **Dimensions Changed:** Image size differs from original dimensions
- ✅ **Content Scaled:** Image content appears scaled rather than cropped or padded
- ✅ **Quality Maintained:** No severe artifacts or quality degradation detected

### Scoring System
- **100%:** Perfect scaling to exact dimensions with good quality preservation
- **75-99%:** Correct dimensions achieved with minor quality or process issues
- **50-74%:** Approximate dimensions or scaling with notable quality problems
- **0-49%:** Failed to achieve target dimensions or severe image corruption

**Pass Threshold:** 75% (requires correct 600x400 dimensions and reasonable quality)

### Dimension Verification Details
```python
# Precise Dimension Checking
def verify_scale_dimensions(result_img):
    """Verify exact pixel dimensions of scaled image."""
    width, height = result_img.size
    
    target_width, target_height = 600, 400
    
    # Check for exact dimension match
    width_correct = (width == target_width)
    height_correct = (height == target_height)
    
    return {
        'width_correct': width_correct,
        'height_correct': height_correct,
        'actual_dimensions': (width, height),
        'target_dimensions': (target_width, target_height),
        'dimensions_match': width_correct and height_correct
    }

# Scaling Analysis
def analyze_scaling_transformation(original_img, result_img):
    """Analyze the scaling transformation applied."""
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    scale_factor_w = result_w / orig_w
    scale_factor_h = result_h / orig_h
    
    # Check if dimensions actually changed
    dimensions_changed = (orig_w != result_w) or (orig_h != result_h)
    
    # Check if scaling factors are reasonable (not too extreme)
    reasonable_scaling = (0.1 <= scale_factor_w <= 10.0) and (0.1 <= scale_factor_h <= 10.0)
    
    return {
        'dimensions_changed': dimensions_changed,
        'scale_factors': (scale_factor_w, scale_factor_h),
        'reasonable_scaling': reasonable_scaling,
        'uniform_scaling': abs(scale_factor_w - scale_factor_h) < 0.1
    }
```

## Technical Implementation

### Files Structure
```
scale_image/
├── task.json              # Task configuration (6 steps, 90s timeout)
├── setup_scale_task.sh    # Downloads sample image, launches GIMP
├── export_scale.sh        # Automates export as "scaled_image"
├── verifier.py           # Dimension verification and quality analysis
└── README.md            # This documentation
```

### Verification Features
- **Pixel-Perfect Accuracy:** Requires exact 600x400 dimensions with no tolerance
- **Comprehensive Analysis:** Evaluates dimensions, scaling factors, and quality preservation
- **Process Validation:** Confirms actual scaling occurred rather than other transformations
- **Quality Monitoring:** Detects obvious artifacts or degradation from scaling operation
- **Fast Execution:** Efficient verification suitable for automated training loops

### Quality Considerations
- **Aspect Ratio Awareness:** Recognizes when aspect ratio changes are expected
- **Scaling Method Independence:** Works regardless of GIMP's internal scaling algorithm
- **Format Flexibility:** Handles various export formats while maintaining dimension accuracy
- **Error Detection:** Identifies common scaling errors like cropping instead of scaling

This task provides essential image scaling skills that are fundamental to professional image editing workflows, while maintaining the straightforward, single-operation focus consistent with other basic GIMP tasks.