# GIMP Bucket Fill Tool Task (`bucket_fill@1`)

## Overview

This task tests an agent's ability to use GIMP's Bucket Fill tool to fill a connected region with a solid color. The agent must select the bucket fill tool, set the appropriate foreground color, and click within a target area to flood-fill it with the chosen color. This represents one of the most fundamental painting operations in digital image editing and is essential for basic graphic design workflows.

## Rationale

**Why this task is valuable:**
- **Core Painting Tool:** Introduces GIMP's essential bucket fill tool, fundamental to digital painting and editing
- **Color Workflow:** Teaches the relationship between foreground color selection and tool application
- **Flood Fill Algorithm:** Tests understanding of how connected regions are filled based on color similarity
- **Precision Clicking:** Requires accurate cursor placement to fill intended areas
- **Visual Feedback:** Provides immediate, clear results that are easy to assess
- **Foundation Skill:** Establishes concepts needed for more advanced painting and editing operations

**Skill Progression:** This task introduces basic painting tools, building toward more sophisticated brush work and digital art creation.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Select Bucket Fill tool from toolbox or use Shift+B shortcut
- **Color Management:** Access and modify foreground color using color picker
- **Precise Clicking:** Click accurately within target regions to trigger fill operation
- **Visual Assessment:** Recognize when fill operation has completed successfully
- **Color Picker Navigation:** Use color selection dialog to choose specific colors

### B. GIMP Knowledge
- **Bucket Fill Behavior:** Understand how the tool fills connected regions of similar colors
- **Foreground/Background Colors:** Know the relationship between color selection and tool behavior
- **Fill Threshold:** Understand that bucket fill works on color similarity within tolerance
- **Tool Options:** Basic awareness of bucket fill settings and parameters
- **Color System:** Navigate GIMP's color picker interface effectively
- **Immediate Application:** Recognize that bucket fill applies instantly upon clicking

### C. Task-Specific Skills
- **Connected Region Recognition:** Identify which areas will be affected by bucket fill
- **Color Boundary Understanding:** Recognize edges and boundaries that constrain fill operations
- **Target Area Selection:** Choose appropriate click locations within regions to be filled
- **Color Accuracy:** Select and apply the exact color specified in the task
- **Result Verification:** Confirm that the intended area changed to the target color

## Task Steps

### 1. Image Analysis
- Examine the simple line drawing that opens automatically in GIMP
- Identify the target region (a closed shape or bounded area) to be filled
- Note the current colors and boundaries that will constrain the fill operation

### 2. Select Bucket Fill Tool
- Click on the Bucket Fill tool in the toolbox or press Shift+B
- Observe that the cursor changes to indicate bucket fill mode is active
- Confirm the tool is properly selected and ready for use

### 3. Set Foreground Color
- Click on the foreground color square in the toolbox (top color square)
- In the color picker dialog, set the color to red (RGB: 255, 0, 0)
- Click "OK" to apply the color selection
- Verify that the foreground color square now shows red

### 4. Apply Bucket Fill
- Position cursor inside the target region (the bounded area to be filled)
- Click once within the region to trigger the flood fill operation
- Observe that the connected area fills with the selected red color

### 5. Verify Fill Results
- Confirm that the intended area is now filled with red color
- Check that the fill stayed within the expected boundaries
- Ensure no unintended areas were affected by the fill operation

### 6. Automatic Export
- The post-task hook will automatically export the result as "red_filled_shape.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **color analysis and region detection** to validate successful bucket fill operation:

### A. Color Change Detection
- **Pixel-wise Comparison:** Analyzes differences between original and result images
- **Red Color Identification:** Specifically detects presence of red pixels (RGB values near 255, 0, 0)
- **Significant Change Threshold:** Ensures a substantial area (≥500 pixels) changed to red
- **Color Accuracy Validation:** Confirms the filled color matches the target red specification

### B. Fill Quality Assessment
- **Connected Region Analysis:** Verifies that fill created coherent, connected red areas
- **Boundary Respect:** Ensures fill stayed within appropriate boundaries and didn't "leak"
- **Fill Completeness:** Checks that target regions are fully filled, not partially
- **Color Consistency:** Validates that filled areas maintain consistent red coloring

### C. Proper Tool Usage Validation
- **Flood Fill Pattern:** Confirms the color change pattern matches bucket fill behavior
- **Single Region Focus:** Ensures fill operation targeted one main region appropriately
- **Clean Edges:** Verifies fill operation respected existing boundaries and edges
- **No Artifacts:** Checks that fill didn't introduce visual artifacts or distortions

### D. Mathematical Color Analysis
- **RGB Threshold Matching:** Uses tolerance-based matching for red color detection (R≥200, G≤50, B≤50)
- **Area Calculation:** Measures total area of red pixels to ensure significant fill occurred
- **Connectivity Analysis:** Validates that red pixels form connected regions as expected
- **Boundary Detection:** Analyzes edges to confirm proper fill containment

### Verification Checklist
- ✅ **Red Color Present:** Significant red-colored area detected in result image (≥500 pixels)
- ✅ **Proper Fill Pattern:** Red areas show connected, flood-fill-like distribution
- ✅ **Color Accuracy:** Detected red color matches specification (R≥200, G≤50, B≤50)
- ✅ **Image Modified:** Clear evidence of bucket fill operation applied

### Scoring System
- **100%:** Excellent bucket fill with large, well-defined red region and perfect color accuracy
- **75-99%:** Good fill operation with correct color but minor issues in coverage or boundaries
- **50-74%:** Adequate fill present but with notable color inaccuracy or incomplete coverage
- **0-49%:** Insufficient or incorrect bucket fill operation

**Pass Threshold:** 75% (requires successful fill with correct color and reasonable coverage)

### Color Detection Algorithm
```python
def detect_red_fill(original_img, result_img):
    """Detect bucket fill operation by analyzing red color introduction."""
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Define red color criteria (tolerant matching)
    red_mask = (result_array[:,:,0] >= 200) & \
               (result_array[:,:,1] <= 50) & \
               (result_array[:,:,2] <= 50)
    
    # Calculate red pixel statistics
    red_pixel_count = np.sum(red_mask)
    total_pixels = result_array.shape[0] * result_array.shape[1]
    red_percentage = (red_pixel_count / total_pixels) * 100
    
    # Check for connected regions using labeled components
    from scipy.ndimage import label
    labeled_regions, num_regions = label(red_mask)
    
    # Find largest red region
    if num_regions > 0:
        region_sizes = [(labeled_regions == i).sum() for i in range(1, num_regions + 1)]
        largest_region_size = max(region_sizes) if region_sizes else 0
    else:
        largest_region_size = 0
    
    return {
        'red_pixel_count': red_pixel_count,
        'red_percentage': red_percentage,
        'largest_red_region': largest_region_size,
        'num_red_regions': num_regions
    }
```

## Technical Implementation

### Files Structure
```
bucket_fill/
├── task.json              # Task configuration (6 steps, 90s timeout)
├── setup_bucket_task.sh   # Downloads line drawing image, launches GIMP
├── export_bucket.sh       # Automates export as "red_filled_shape"
├── verifier.py           # Color analysis and region detection verification
└── README.md            # This documentation
```

### Verification Features
- **Precise Color Detection:** Uses RGB thresholds to identify target red color accurately
- **Region Analysis:** Employs connected component analysis for fill pattern validation
- **Coverage Assessment:** Measures fill effectiveness through area calculations
- **Pattern Recognition:** Distinguishes bucket fill from other coloring methods
- **Quality Assurance:** Validates clean edges and proper boundary respect

### Task Image Requirements
- **Simple Line Drawing:** Uses clear, black outlines on white background
- **Closed Regions:** Includes at least one fully bounded area suitable for bucket fill
- **Clear Boundaries:** Distinct edges that will constrain fill operation appropriately
- **Appropriate Size:** Large enough target region to produce measurable fill results

This task introduces essential painting functionality while maintaining the simplicity and clear verification criteria consistent with the existing task suite. It teaches fundamental color workflow and tool usage that serves as foundation for more advanced GIMP operations.