# GIMP Autocrop to Content Task (`autocrop_content@1`)

## Overview

This task tests an agent's ability to use GIMP's automatic cropping feature to intelligently remove uniform borders or empty space from an image. The agent must navigate to the autocrop function and let GIMP automatically detect and crop to the actual image content, removing extraneous background. This represents a common workflow operation used to clean up scanned images, screenshots, and artwork with unnecessary borders.

## Rationale

**Why this task is valuable:**
- **Intelligent Automation:** Introduces GIMP's smart content-detection capabilities beyond manual tools
- **Workflow Efficiency:** Tests understanding of automated operations that save time vs. manual cropping
- **Common Use Case:** Frequently used for cleaning up scans, screenshots, and imported artwork
- **Content Awareness:** Requires trusting GIMP's algorithm to identify meaningful content boundaries
- **Practical Skill:** Essential for batch processing and standardizing images with varying border sizes
- **Foundation for Advanced Tools:** Establishes concepts needed for other auto-detection features

**Skill Progression:** This task bridges manual cropping (crop_resize) with automatic content-aware operations, introducing intelligent tool usage.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through Image menu to find autocrop functionality
- **Command Selection:** Identify and click "Crop to Content" or similar autocrop command
- **Immediate Application:** Recognize that autocrop applies instantly without dialogs
- **Visual Verification:** Assess that borders were successfully removed
- **Result Evaluation:** Confirm that content remains intact after automatic cropping

### B. GIMP Knowledge
- **Auto-detection Tools:** Understand GIMP's automatic content detection capabilities
- **Crop Operations:** Distinguish between manual crop and automatic content-based crop
- **Border Detection:** Know how GIMP identifies uniform regions for removal
- **Canvas Reduction:** Understand that autocrop reduces canvas to content boundaries
- **Non-destructive Concept:** Recognize this is a canvas operation, not content modification
- **Menu Organization:** Navigate Image menu's crop-related functions

### C. Task-Specific Skills
- **Content Identification:** Visual understanding of what constitutes "content" vs. "border"
- **Algorithm Trust:** Ability to rely on automated detection rather than manual control
- **Boundary Assessment:** Recognize appropriate crop boundaries for the specific image
- **Result Validation:** Confirm that cropping preserved important content without cutting into it
- **Efficiency Recognition:** Understand when automated cropping is preferable to manual methods

## Task Steps

### 1. Initial Image Analysis
- Examine the image that opens automatically in GIMP
- Observe the significant white/uniform borders surrounding the central content
- Identify the actual content area that should be preserved
- Note the current image dimensions

### 2. Access Image Menu
- Click on "Image" in the menu bar to open the Image menu
- Look for crop-related functions in the menu structure
- Locate "Crop to Content" (or "Autocrop Image" in some GIMP versions)

### 3. Execute Autocrop
- Click on "Image → Crop to Content"
- Observe that GIMP immediately analyzes the image for content boundaries
- The operation applies instantly without additional dialog boxes

### 4. Visual Verification
- Confirm that uniform borders have been removed
- Verify that the canvas now tightly bounds the actual content
- Check that no important content was inadvertently cropped
- Observe the reduced canvas size

### 5. Dimension Check (Optional)
- Optionally check Image → Image Properties to see new dimensions
- Confirm that width and height are smaller than the original
- Verify the reduction is significant (substantial borders were removed)

### 6. Automatic Export
- The post-task hook will automatically export the result as "autocropped_image.png"

## Verification Strategy

### Verification Approach
The verifier uses **multi-dimensional analysis** combining dimension reduction, content preservation, and border removal:

### A. Dimension Reduction Analysis
- **Size Comparison:** Verifies that result dimensions are smaller than original in both width and height
- **Meaningful Reduction:** Ensures cropping removed substantial area (minimum 10% reduction)
- **Crop Percentage Calculation:** Measures how much of the original canvas was removed
- **Appropriate Bounds:** Validates that reduction isn't excessive (suggesting content was cut)

### B. Content Preservation Verification
- **Center Region Analysis:** Compares the central content area before and after cropping
- **Structural Similarity:** Uses SSIM or correlation to verify content remained intact
- **Detail Preservation:** Ensures image details in content region maintained quality
- **No Content Loss:** Confirms important subject matter wasn't cropped away

### C. Border Removal Assessment
- **Edge Analysis:** Verifies that original border regions were successfully removed
- **Uniform Area Detection:** Confirms that removed areas were indeed uniform/empty
- **Edge Proximity:** Checks that crop boundaries are close to actual content (not too loose)
- **Corner Validation:** Ensures all four borders were appropriately handled

### D. Autocrop Success Metrics
- **Non-identity Check:** Confirms image was actually modified (not just re-saved)
- **Aspect Ratio Change:** Validates that crop changed proportions if borders were uneven
- **Boundary Tightness:** Measures how closely the new canvas bounds the content
- **Algorithm Execution:** Verifies the operation was autocrop, not manual crop to fixed size

### Verification Checklist
- ✅ **Dimensions Reduced:** Image width and height both smaller than original
- ✅ **Substantial Cropping:** At least 10% area reduction from original canvas
- ✅ **Content Preserved:** Center content region maintains high similarity (SSIM ≥ 0.95)
- ✅ **Borders Removed:** Original border areas no longer present in result
- ✅ **Tight Cropping:** Result canvas closely bounds the content without excessive space

### Scoring System
- **100%:** All 5 criteria met (perfect autocrop with content preservation)
- **75-99%:** 4/5 criteria met (good autocrop with minor imperfections)
- **50-74%:** 3/5 criteria met (partial success but needs improvement)
- **0-49%:** <2 criteria met (autocrop failed or not executed)

**Pass Threshold:** 75% (requires at least 4 out of 5 criteria)

## Technical Implementation

### Files Structure