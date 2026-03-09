# GIMP Pixelate Effect Task (`pixelate_mosaic@1`)

## Overview

This task tests an agent's ability to apply GIMP's pixelate filter to create a mosaic/blocky effect on an image. The agent must navigate to the blur filters menu, access the Pixelize tool, configure appropriate pixel block size, and apply the effect to create a characteristic "censored" or artistic pixelated appearance. This represents a fundamental privacy-preserving and artistic effect commonly used in photo editing, content moderation, and creative design.

## Rationale

**Why this task is valuable:**
- **Filter System Introduction:** Introduces GIMP's extensive filter menu and blur effects category
- **Privacy Technique:** Teaches a practical method for obscuring sensitive content (faces, text, personal info)
- **Artistic Effect:** Provides creative pixelation effects used in digital art and retro aesthetics
- **Simple Parameter Control:** Tests understanding of single-parameter filter dialogs
- **Common Workflow:** Frequently used in journalism, social media, documentation, and content creation
- **Visual Feedback:** Provides immediate, obvious results that are easy to assess

**Skill Progression:** This task is perfectly suited for beginners, requiring only menu navigation and a single slider adjustment, similar in complexity to the horizontal mirror task.

## Skills Required

### A. Interaction Skills
- **Multi-level Menu Navigation:** Navigate through nested filter menus (`Filters → Blur → Pixelize`)
- **Dialog Interaction:** Work with simple filter dialog boxes
- **Slider/Numeric Control:** Adjust pixel size parameter using slider or numeric input
- **Preview Assessment:** Evaluate the effect preview before applying
- **Confirmation Actions:** Apply filter using OK/Apply buttons

### B. GIMP Knowledge
- **Filter Menu System:** Understand GIMP's filter categorization and organization
- **Blur Filter Category:** Know that pixelation is categorized under blur effects
- **Filter Dialogs:** Recognize standard filter dialog interface patterns
- **Parameter Effects:** Understand how pixel block size affects the visual result
- **Preview System:** Use filter previews to assess effects before application
- **Non-destructive Preview:** Know that filters don't apply until confirmed

### C. Task-Specific Skills
- **Effect Understanding:** Comprehend what "pixelate" means visually (creating uniform color blocks)
- **Parameter Selection:** Choose appropriate pixel block size for effective results
- **Visual Assessment:** Judge when pixelation is sufficient for the intended purpose
- **Effect Intensity:** Balance between recognizable content and effective obscuring/artistic effect

## Task Steps

### 1. Initial Image Examination
- Examine the portrait or detailed image that opens automatically in GIMP
- Note areas with fine detail that will be transformed into pixel blocks
- Prepare to apply a mosaic effect to the entire image

### 2. Navigate to Blur Filters
- Click on "Filters" in the menu bar to open the filters menu
- Locate and hover over "Blur" to open the blur effects submenu
- Identify the pixelation options within the blur category

### 3. Select Pixelize Filter
- Click on "Pixelize" (or "Mosaic" depending on GIMP version) from the Blur submenu
- Wait for the Pixelize filter dialog to open
- Observe the preview showing the current effect

### 4. Configure Pixel Block Size
- Locate the pixel size parameter (typically labeled "Pixel Width" or "Block Size")
- Adjust the value to create noticeable pixelation (recommended: 10-20 pixels)
- Observe the preview update to show the mosaic effect

### 5. Preview Assessment
- Check the preview pane to ensure pixelation is visible and effective
- Verify that the image has a characteristic "blocky" appearance
- Ensure pixel blocks are large enough to be clearly visible

### 6. Apply Filter
- Click "OK" or "Apply" button to apply the pixelization to the full image
- Wait for GIMP to process the filter (may take a moment for large images)
- Observe the pixelated result in the main canvas

### 7. Visual Confirmation
- Verify that the entire image now has a mosaic/pixelated appearance
- Check that fine details have been replaced with uniform color blocks
- Confirm the effect meets expectations for pixel block size

### 8. Automatic Export
- The post-task hook will automatically export the result as "pixelated_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **multi-criteria block detection and detail reduction analysis** to confirm effective pixelation:

### A. Uniform Block Detection
- **Grid Analysis:** Divides the image into small regions and analyzes color uniformity
- **Block Identification:** Detects presence of large uniform color regions characteristic of pixelation
- **Pattern Recognition:** Uses standard deviation within regions to identify pixel blocks
- **Coverage Measurement:** Calculates what percentage of image shows pixelated characteristics

### B. Detail Reduction Analysis
- **Edge Detection Comparison:** Compares edge counts before and after to measure detail loss
- **Variance Reduction:** Measures decrease in local pixel variance indicating uniform blocks
- **Texture Analysis:** Computes texture descriptors to detect characteristic pixelated appearance
- **Detail Loss Percentage:** Quantifies how much fine detail was removed by the effect

### C. Mathematical Validation
- **Standard Deviation Analysis:** Low standard deviation within suspected pixel blocks confirms uniformity
- **Color Clustering:** Analyzes reduction in unique color combinations
- **Spatial Frequency Analysis:** Detects characteristic low-frequency patterns of pixelation
- **Block Size Estimation:** Estimates average pixel block size to ensure it's significant

### D. Quality Assurance
- **Effect Verification:** Confirms pixelation is substantial enough to be considered successful
- **Complete Application:** Ensures effect was applied to entire image, not just portions
- **No Corruption:** Verifies image wasn't corrupted or improperly processed
- **Export Success:** Confirms proper file export and format

### Verification Checklist
- ✅ **Uniform Blocks Detected:** At least 40% of image shows characteristic pixelated regions
- ✅ **Significant Detail Reduction:** Edge count reduced by at least 50% from original
- ✅ **Block Pattern Present:** Low variance regions identified throughout image
- ✅ **Image Modified:** Clear mathematical differences from original image

### Scoring System
- **100%:** All 4 criteria met with strong pixelation effect clearly visible
- **75-99%:** 3/4 criteria met with good pixelation but minor issues
- **50-74%:** 2/4 criteria met with weak or incomplete pixelation
- **0-49%:** <2 criteria met, effect not successfully applied

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure