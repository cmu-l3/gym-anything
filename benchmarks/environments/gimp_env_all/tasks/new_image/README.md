# GIMP New Image Creation Task (`new_image@1`)

## Overview

This task tests an agent's ability to create a new blank image document in GIMP using the File → New dialog. The agent must specify exact dimensions, set the background color, and successfully create a new document. This represents the foundational skill required at the beginning of every digital art and design workflow, where users must create appropriately sized canvases before beginning creative work.

## Rationale

**Why this task is valuable:**
- **Foundational Workflow:** Every GIMP project begins with creating a new image or opening an existing one
- **Dialog Mastery:** Introduces GIMP's "Create a New Image" dialog and its various parameters
- **Precision Requirements:** Tests ability to enter exact specifications for professional workflows
- **Parameter Understanding:** Builds familiarity with image properties (dimensions, resolution, color mode)
- **Real-world Relevance:** Essential for web design, print design, digital art, and photo editing workflows
- **Document Setup:** Establishes proper canvas preparation skills needed for subsequent operations

**Skill Progression:** This task provides essential document creation skills that underpin all other GIMP operations, making it ideal for foundational agent training.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Access `File → New` through the menu system
- **Dialog Management:** Work with the multi-parameter "Create a New Image" dialog
- **Numeric Input:** Enter precise width and height values in input fields
- **Dropdown Navigation:** Select background fill options from dropdown menus
- **Unit Understanding:** Work with pixel units and understand dimension specifications
- **Confirmation Actions:** Apply settings using OK button to create the new document

### B. GIMP Knowledge
- **Document Creation:** Understand GIMP's new image creation process and dialog options
- **Image Properties:** Know the relationship between width, height, resolution, and color mode
- **Background Options:** Understand different background fill choices (white, black, transparent)
- **Canvas Concepts:** Recognize that new images create blank canvases for subsequent work
- **Default Settings:** Navigate and override GIMP's default new image parameters
- **Document Management:** Understand that new images replace the current workspace

### C. Task-Specific Skills
- **Specification Compliance:** Create images with exact dimensions as requested
- **Color Selection:** Choose appropriate background colors for the intended use case
- **Size Planning:** Understand appropriate dimensions for different types of projects
- **Parameter Verification:** Ensure all settings are correct before confirming creation
- **Quality Standards:** Create documents that meet professional specifications

## Task Steps

### 1. Access New Image Dialog
- Navigate to `File → New` in the menu bar
- Wait for the "Create a New Image" dialog to open
- Observe the various parameter options available

### 2. Set Image Dimensions
- Locate the width and height input fields
- Enter the specified width: 640 pixels
- Enter the specified height: 480 pixels
- Ensure the unit is set to "pixels" if not already

### 3. Configure Background
- Locate the "Fill with" dropdown menu
- Select "White" as the background color option
- Verify that the background preview shows white

### 4. Verify Settings
- Double-check that width is 640 pixels
- Double-check that height is 480 pixels
- Confirm background is set to white
- Review other parameters (resolution should be fine at default)

### 5. Create the Image
- Click "OK" button to create the new image
- Observe that a new blank white document appears in the workspace
- Verify the canvas displays the correct dimensions

### 6. Automatic Export
- The post-task hook will automatically export the result as "new_blank_image.png"

## Verification Strategy

### Verification Approach
The verifier uses **direct image property analysis** combined with **content verification**:

### A. Dimension Verification
- **Exact Size Check:** Verifies image dimensions are precisely 640x480 pixels
- **Aspect Ratio Validation:** Ensures proper 4:3 aspect ratio (640/480 = 1.333...)
- **Pixel Count Analysis:** Confirms total pixel count matches expected (307,200 pixels)
- **No Scaling Issues:** Ensures dimensions weren't approximated or rounded incorrectly

### B. Background Color Analysis
- **Color Uniformity Check:** Analyzes entire image to ensure consistent white background
- **White Color Verification:** Confirms RGB values are (255, 255, 255) or very close
- **No Content Detection:** Ensures the image is truly blank with no existing content
- **Color Space Validation:** Verifies standard RGB color space usage

### C. Image Properties Assessment
- **Format Validation:** Ensures proper image format and structure
- **Color Depth Check:** Verifies appropriate bit depth (typically 8-bit per channel)
- **Metadata Analysis:** Examines image metadata for creation information
- **File Integrity:** Confirms the exported image is properly formed

### D. Creation Verification
- **New Document Confirmation:** Verifies this is a newly created image, not a modified existing one
- **Clean Canvas Check:** Ensures no artifacts, noise, or unintended content exists
- **Professional Standards:** Confirms the image meets standard specifications for digital work

### Verification Checklist
- ✅ **Correct Dimensions:** Image is exactly 640x480 pixels
- ✅ **White Background:** Entire image has uniform white background (RGB ~255,255,255)
- ✅ **Clean Canvas:** No artifacts, content, or unintended elements present
- ✅ **Proper Format:** Valid image file exported successfully

### Scoring System
- **100%:** Perfect new image creation with exact specifications
- **75-99%:** Correct creation with minor dimension or color variations
- **50-74%:** Image created but with notable specification deviations
- **0-49%:** Failed to create proper new image or major specification errors

**Pass Threshold:** 75% (requires correct dimensions and background color)

## Technical Implementation

### Files Structure
```
new_image/
├── task.json                # Task configuration (6 steps, 90s timeout)
├── setup_new_task.sh        # Launches GIMP without pre-loading any image
├── export_new_image.sh      # Exports the created image as "new_blank_image"
├── verifier.py             # Image property and content verification
└── README.md              # This documentation
```

### Verification Features
- **Precise Dimension Checking:** Pixel-perfect dimension validation using PIL
- **Color Uniformity Analysis:** Statistical analysis to ensure solid white background
- **Content Cleanliness Verification:** Ensures truly blank canvas with no artifacts
- **Professional Standards:** Validates image meets standard digital workflow requirements
- **Robust Error Handling:** Graceful handling of various image formats and edge cases

This task establishes fundamental document creation skills essential for all subsequent GIMP workflows, providing agents with the foundational ability to create properly configured blank canvases for digital art and design projects.