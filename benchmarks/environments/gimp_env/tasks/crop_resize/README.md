# GIMP Crop and Resize Task (`crop_resize@1`)

## Overview

This task tests an agent's ability to use GIMP's selection and scaling tools to crop an image to focus on the main subject and resize it to specific dimensions. The task simulates a common image editing workflow where users need to extract a key element from a larger composition and standardize the output size.

## Rationale

**Why this task is valuable:**
- **Essential Workflow:** Cropping and resizing are fundamental image editing operations used in nearly every digital media workflow
- **Composition Skills:** Tests the agent's ability to identify and focus on the most important subject in an image
- **Precision Requirements:** Requires exact dimension control, testing precision in tool usage
- **Tool Mastery:** Combines two core GIMP tools (Crop Tool + Scale Image) in a logical sequence
- **Real-world Relevance:** Common in photography, web design, social media content creation, and document preparation

**Skill Progression:** This task bridges basic operations (like mirroring) with more advanced composition decisions, making it ideal for intermediate-level agent training.

## Skills Required

### A. Interaction Skills
- **Precise Clicking:** Select the Crop Tool from toolbox or use keyboard shortcut
- **Click and Drag:** Create crop selection by dragging around the desired subject area
- **Menu Navigation:** Access `Image → Scale Image` through multi-level menu system
- **Input Field Manipulation:** Enter specific numeric values (400x300) in dialog boxes
- **Dialog Interaction:** Understand and use the Scale Image dialog interface
- **Confirmation Actions:** Apply changes using Enter key or OK buttons

### B. GIMP Knowledge
- **Tool Understanding:** Know the purpose and behavior of the Crop Tool (Shift+C)
- **Selection Concepts:** Understand how crop selections define the final image boundaries
- **Image Menu System:** Navigate to scaling functions within GIMP's menu hierarchy
- **Dialog Box Interface:** Work with the Scale Image dialog and its parameters
- **Dimension Units:** Understand pixel dimensions and maintain aspect ratio options
- **Workflow Sequence:** Know the logical order: crop first, then scale

### C. Task-Specific Skills
- **Subject Identification:** Visually analyze the image to identify the main subject/focal point
- **Composition Assessment:** Determine appropriate crop boundaries to enhance the subject
- **Proportion Judgment:** Balance tight cropping with maintaining context around the subject
- **Dimension Planning:** Understand how the target size (400x300) affects the final composition
- **Quality Preservation:** Recognize that cropping before scaling helps maintain image quality

## Task Steps

### 1. Initial Assessment
- Examine the portrait image that opens automatically in GIMP
- Identify the main subject (person's face/upper body area)
- Plan the crop boundaries to focus on the subject while maintaining visual balance

### 2. Crop Tool Selection
- Select the Crop Tool from the toolbox (or use Shift+C shortcut)
- Observe that the cursor changes to indicate crop mode is active

### 3. Define Crop Area
- Click and drag to create a rectangular selection around the main subject
- Aim to include the subject prominently while removing extraneous background
- Adjust the selection boundaries if needed by dragging the corner/edge handles

### 4. Apply Crop
- Press Enter key or click inside the selection to apply the crop
- Verify that the image is now cropped to focus on the subject

### 5. Access Scale Dialog
- Navigate to `Image → Scale Image` in the menu bar
- Wait for the Scale Image dialog to open

### 6. Set Target Dimensions
- Change the width value to 400 pixels
- Change the height value to 300 pixels
- Ensure the chain link icon is broken if you need exact dimensions regardless of aspect ratio

### 7. Apply Scaling
- Click "Scale" button to apply the resize operation
- Verify that the image is now 400x300 pixels

### 8. Automatic Export
- The post-task hook will automatically export the result as "cropped_resized.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **multi-criteria analysis** combining dimension accuracy, crop effectiveness, and quality preservation:

### A. Dimension Verification
- **Exact Measurement:** Checks that final image dimensions are 400x300 pixels (±5px tolerance)
- **Tolerance Reasoning:** Small tolerance accounts for potential rounding in GIMP's scaling algorithms

### B. Crop Effectiveness Analysis
- **Size Reduction Check:** Verifies significant cropping occurred (minimum 20% area reduction from original)
- **Subject Focus Assessment:** Analyzes whether cropping improved the subject prominence using center-weighted analysis
- **Crop Ratio Calculation:** Measures how much of the original image was retained

### C. Quality Preservation
- **Detail Analysis:** Compares image detail (standard deviation) in center regions before/after
- **Structure Integrity:** Ensures that cropping and resizing maintained essential image characteristics
- **Aspect Ratio Evaluation:** Analyzes how the composition changed through the process

### D. Change Detection
- **Modification Verification:** Confirms the image was actually altered from the original
- **Meaningful Transformation:** Ensures changes are substantial enough to represent successful task completion

### Verification Checklist
- ✅ **Dimensions Correct:** Final image is 400x300 pixels (±5px)
- ✅ **Significantly Cropped:** Image area reduced by at least 20%
- ✅ **Detail Preserved:** Center region detail maintained at 80%+ of original
- ✅ **Image Modified:** Clear differences from original image detected

### Scoring System
- **100%:** All 4 criteria met (perfect crop and resize)
- **75-99%:** 3/4 criteria met (good execution with minor issues)
- **50-74%:** 2/4 criteria met (partially successful but needs improvement)
- **0-49%:** <2 criteria met (task not successfully completed)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure
```
crop_resize/
├── task.json           # Task configuration (10 steps, 120s timeout)
├── setup_crop_task.sh  # Downloads portrait image, launches GIMP
├── export_crop.sh      # Automates export as "cropped_resized"
├── verifier.py         # Multi-criteria verification logic
└── README.md          # This documentation
```

### Verification Utilities
- Uses shared `verification_utils.py` for robust file handling and fallback search
- Implements advanced image analysis using PIL and NumPy
- Includes automatic cleanup of temporary verification files
