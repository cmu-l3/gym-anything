# GIMP Canvas Size Adjustment Task (`canvas_resize@1`)

## Overview

This task tests an agent's ability to use GIMP's canvas size adjustment feature to expand the working area around an existing image. The agent must navigate to the Canvas Size dialog, modify the canvas dimensions to add extra space around the image, and ensure the original content remains centered with appropriate padding. This represents a fundamental image preparation workflow commonly used when images need to fit specific aspect ratios or require additional space for design elements.

## Rationale

**Why this task is valuable:**
- **Canvas Concepts:** Introduces the important distinction between canvas size (working area) and image scaling (content resize)
- **Image Preparation:** Tests skills needed for format preparation, social media sizing, and design layout workflows
- **Dialog Navigation:** Builds familiarity with GIMP's sizing dialogs and numeric input systems
- **Non-destructive Editing:** Demonstrates how to modify image dimensions without altering original content
- **Real-world Relevance:** Common in web design, print preparation, social media content, and digital art workflows
- **Foundation Skill:** Establishes concepts needed for more advanced canvas manipulation and composition work

**Skill Progression:** This task bridges basic operations with intermediate image preparation skills, introducing concepts essential for professional design workflows.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate to `Image → Canvas Size` through the menu system
- **Dialog Management:** Work with the Canvas Size dialog interface effectively
- **Numeric Input:** Enter specific pixel dimensions in input fields
- **Anchor Understanding:** Comprehend how content positioning works during canvas changes
- **Unit Recognition:** Work with pixel measurements and dimension relationships
- **Change Application:** Apply canvas modifications using the appropriate dialog controls

### B. GIMP Knowledge
- **Canvas vs. Image Size:** Understand the difference between canvas adjustment and image scaling
- **Dialog Interface:** Navigate the Canvas Size dialog and its various options
- **Anchor Position:** Understand how anchor points control content positioning during canvas changes
- **Dimension Relationships:** Recognize how width and height changes affect the final composition
- **Background Fill:** Understand how new canvas areas are filled (typically with background color)
- **Content Preservation:** Know that canvas changes don't alter the original image content

### C. Task-Specific Skills
- **Size Calculation:** Determine appropriate canvas dimensions based on requirements
- **Aspect Ratio Awareness:** Understand how canvas changes affect overall image proportions
- **Centering Concepts:** Recognize how to keep original content properly positioned
- **Layout Planning:** Consider how additional canvas space will be used in design workflows
- **Format Preparation:** Understand common canvas size requirements for different media

## Task Steps

### 1. Image Analysis and Planning
- Examine the landscape image that opens automatically in GIMP (typically 800x600 pixels)
- Note the current dimensions and content positioning
- Plan the canvas expansion to accommodate the new dimensions (1000x800 pixels)

### 2. Access Canvas Size Dialog
- Navigate to `Image → Canvas Size` in the menu bar
- Wait for the Canvas Size dialog to open
- Observe the current dimensions displayed in the dialog

### 3. Configure New Canvas Dimensions
- Change the width field from 800 to 1000 pixels
- Change the height field from 600 to 800 pixels
- Verify that the new dimensions are properly entered

### 4. Set Content Positioning
- Ensure the anchor/positioning is set to center the original content
- Verify that the original image will remain centered in the expanded canvas
- Check that the positioning preview shows appropriate content placement

### 5. Apply Canvas Size Change
- Click "OK" or "Resize" button to apply the canvas size modification
- Observe that the canvas expands around the original image content
- Verify that new areas are filled with the background color (typically white)

### 6. Result Verification
- Confirm that the image now shows additional space around the original content
- Verify that the original image content remains intact and properly centered
- Check that the overall dimensions match the target size (1000x800)

### 7. Automatic Export
- The post-task hook will automatically export the result as "expanded_canvas.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **dimensional analysis and content preservation checking** to validate the canvas adjustment:

### A. Dimension Verification
- **Exact Size Check:** Verifies that final image dimensions are 1000x800 pixels (±5px tolerance)
- **Size Increase Validation:** Confirms significant expansion occurred from original dimensions
- **Aspect Ratio Analysis:** Ensures the new canvas provides additional working space as intended
- **Tolerance Reasoning:** Small tolerance accommodates potential GIMP rounding in dimension calculations

### B. Content Preservation Analysis
- **Original Content Detection:** Verifies that the original image content remains completely intact
- **Centering Assessment:** Analyzes whether original content is properly centered in expanded canvas
- **Content Integrity:** Ensures no cropping, scaling, or distortion of original image occurred
- **Quality Maintenance:** Confirms that image quality wasn't degraded during canvas expansion

### C. Canvas Addition Detection
- **Background Area Analysis:** Identifies new canvas areas that should be filled with background color
- **Edge Detection:** Analyzes image edges to confirm canvas expansion rather than content scaling
- **Color Analysis:** Verifies that new canvas areas contain appropriate background fill (typically white)
- **Uniform Expansion:** Ensures canvas was expanded evenly to center original content

### D. Change Validation
- **Modification Verification:** Confirms the image was actually changed from original dimensions
- **Proper Operation:** Ensures canvas size change (not scale) operation was performed
- **Success Criteria:** Validates that the expansion serves the intended purpose

### Verification Checklist
- ✅ **Correct Dimensions:** Final image is 1000x800 pixels (±5px tolerance)
- ✅ **Significant Expansion:** Canvas area increased by at least 40% from original
- ✅ **Content Preserved:** Original image content remains intact and unscaled
- ✅ **Proper Centering:** Original content is appropriately centered in expanded canvas

### Scoring System
- **100%:** All 4 criteria met (perfect canvas expansion with content preservation)
- **75-99%:** 3/4 criteria met (good canvas adjustment with minor positioning issues)
- **50-74%:** 2/4 criteria met (partial success but significant issues)
- **0-49%:** <2 criteria met (canvas adjustment failed or incorrect operation performed)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure
```
canvas_resize/
├── task.json              # Task configuration (8 steps, 90s timeout)
├── setup_canvas_task.sh   # Downloads landscape image, launches GIMP
├── export_canvas.sh       # Automates export as "expanded_canvas"
├── verifier.py           # Dimensional and content preservation verification
└── README.md            # This documentation
```

### Verification Features
- **Precise Dimension Checking:** Validates exact target dimensions with appropriate tolerance
- **Content Preservation Analysis:** Ensures original image remains intact during canvas expansion
- **Centering Verification:** Confirms proper content positioning within expanded canvas
- **Operation Validation:** Distinguishes canvas resize from image scaling operations
- **Quality Assessment:** Verifies no degradation or unwanted modifications occurred

This task introduces essential canvas management skills while maintaining simplicity and clear verification criteria. It represents a fundamental skill needed for image preparation and design workflows in professional GIMP usage.