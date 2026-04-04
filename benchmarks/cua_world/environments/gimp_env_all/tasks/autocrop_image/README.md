# GIMP Autocrop Image Task (`autocrop_image@1`)

## Overview

This task tests an agent's ability to use GIMP's automatic cropping feature to remove unnecessary borders, whitespace, or uniform-color areas from an image. The agent must navigate to the autocrop function and apply it to intelligently trim the image to its essential content. This represents a fundamental optimization workflow used in photography, graphic design, and document preparation.

## Rationale

**Why this task is valuable:**
- **Automatic Operation Introduction:** Introduces GIMP's intelligent automation features that analyze and modify images
- **Efficiency Workflow:** Tests understanding of one-click optimization operations common in production environments
- **Content-Aware Processing:** Demonstrates GIMP's ability to analyze image content and make smart decisions
- **Common Use Case:** Removing whitespace/borders is extremely frequent in scanning, screenshot processing, and photo editing
- **Foundation for Advanced Operations:** Builds understanding of automatic image analysis features
- **Professional Time-Saving:** Represents efficient workflows that avoid manual measurement and selection

**Skill Progression:** This task bridges basic manual operations (like manual crop) with intelligent automatic processing, introducing the concept of content-aware image manipulation.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through menu structure (`Image → Crop to Content` or `Image → Autocrop Image`)
- **Precise Selection:** Click on the correct menu item among similar options
- **Visual Confirmation:** Recognize when the autocrop has been successfully applied
- **Result Assessment:** Compare before/after to verify appropriate content preservation
- **Understanding Automation:** Trust and verify automatic operations

### B. GIMP Knowledge
- **Autocrop Functionality:** Understand what autocrop analyzes (uniform borders, transparency, whitespace)
- **Content Detection:** Know that GIMP identifies the "content boundaries" automatically
- **Immediate Application:** Recognize that autocrop applies instantly without additional dialogs
- **Image vs. Layer Operations:** Distinguish between "Autocrop Image" and "Autocrop Layer"
- **Boundary Analysis:** Understand how GIMP determines what constitutes "empty" space
- **Non-destructive Concept:** Know that autocrop removes pixels but can be undone

### C. Task-Specific Skills
- **Visual Analysis:** Identify that the image has trimmable borders or whitespace
- **Content Identification:** Understand what constitutes "content" vs. "border"
- **Dimension Awareness:** Recognize that image dimensions should decrease after autocrop
- **Quality Verification:** Confirm that no important content was inadvertently removed
- **Efficiency Recognition:** Appreciate the time-saving benefit over manual crop operations

## Task Steps

### 1. Initial Image Examination
- Examine the image that opens automatically in GIMP
- Identify visible borders, whitespace, or uniform-color areas around the main content
- Note the current image dimensions (visible in title bar or Image → Canvas Size)
- Recognize that the image has unnecessary space that can be removed

### 2. Navigate to Autocrop Function
- Click on "Image" in the menu bar to open the Image menu
- Locate the autocrop function (may be labeled "Crop to Content" or "Autocrop Image" depending on GIMP version)
- Hover over the menu item to see its description/tooltip

### 3. Apply Autocrop
- Click on the autocrop menu item
- Observe that the operation applies immediately without additional dialogs
- Watch as GIMP automatically removes borders and trims to content

### 4. Verify Automatic Crop Results
- Observe that the canvas/image dimensions have decreased
- Confirm that the main content is now positioned closer to image edges
- Verify that no important content was removed, only borders/whitespace
- Check that the image appears properly trimmed

### 5. Quality Assessment
- Ensure the cropping was appropriate (not too aggressive or too conservative)
- Verify that content boundaries are clean and properly detected
- Confirm that the image maintains its essential composition
- Note the new, optimized dimensions

### 6. Automatic Export
- The post-task hook will automatically export the result as "autocropped_image.png"

## Verification Strategy

### Verification Approach
The verifier uses **dimensional analysis and border detection** to validate intelligent cropping:

### A. Dimension Reduction Verification
- **Size Comparison:** Confirms that output dimensions are smaller than input dimensions
- **Significant Reduction:** Ensures meaningful cropping occurred (not just 1-2 pixels)
- **Both Dimensions:** Checks that at least one dimension (width or height) was substantially reduced
- **Reasonable Bounds:** Validates that the image wasn't over-cropped to near-zero size

### B. Border Removal Analysis
- **Edge Proximity Detection:** Analyzes how close content extends to new image edges
- **Content Density:** Measures pixel variance/activity near edges before and after
- **Whitespace Reduction:** Quantifies the removal of uniform or near-uniform border regions
- **Edge Distribution:** Ensures content is more evenly distributed to edges in result

### C. Content Preservation
- **Core Content Matching:** Uses SSIM or correlation to verify that central content remains intact
- **No Information Loss:** Confirms that only border regions were removed, not interior content
- **Aspect Ratio Analysis:** Checks that aspect ratio changes are consistent with border removal
- **Center Alignment:** Verifies that the content center is preserved appropriately

### D. Intelligent Cropping Assessment
- **Uniform Border Detection:** Analyzes whether removed regions were indeed uniform/low-content
- **Content Boundary Accuracy:** Validates that GIMP correctly identified content edges
- **Appropriate Aggressiveness:** Ensures cropping was neither too conservative nor too aggressive
- **Professional Result:** Confirms the result appears properly optimized

### Verification Checklist
- ✅ **Dimensions Reduced:** At least one dimension decreased by ≥5% (minimum 10 pixels)
- ✅ **Content Preserved:** Core image content remains intact (SSIM ≥ 0.90 for center region)
- ✅ **Borders Removed:** Edge regions show increased content density
- ✅ **Professional Result:** Image appears properly trimmed without over-cropping

### Scoring System
- **100%:** Perfect autocrop with appropriate border removal and content preservation
- **75-99%:** Good crop with minor imperfections in boundary detection
- **50-74%:** Adequate cropping but overly conservative or slightly aggressive
- **0-49%:** Failed to crop, over-cropped, or removed important content

**Pass Threshold:** 75% (requires effective border removal with content preservation)

## Technical Implementation

### Files Structure