# GIMP Remove White Background Task (`remove_background@1`)

## Overview

This task tests an agent's ability to use GIMP's transparency features and color selection tools to remove a solid background from an image, making it transparent. The agent must add an alpha channel to enable transparency, use the "Select by Color" tool to select the white background, delete it, and export the result as a PNG file with transparency. This represents one of the most common image editing workflows in e-commerce, graphic design, and digital content creation.

## Rationale

**Why this task is valuable:**
- **Universal Workflow:** Background removal is one of the most frequently requested image editing tasks
- **Transparency Concepts:** Introduces alpha channels and transparency, fundamental to modern digital graphics
- **E-commerce Relevance:** Essential for product photography, catalog images, and online retail
- **Selection Tool Practice:** Builds on color selection concepts in a practical application
- **Layer Management:** Teaches understanding of layer properties and alpha channels
- **File Format Awareness:** Reinforces knowledge of which formats support transparency (PNG vs. JPEG)

**Skill Progression:** This task bridges basic selection tools with advanced transparency concepts, making it ideal for intermediate-level workflows.

## Skills Required

### A. Interaction Skills
- **Layer Menu Navigation:** Access `Layer → Transparency → Add Alpha Channel`
- **Tool Selection:** Activate the "Select by Color" tool (Shift+O)
- **Background Clicking:** Click on background areas to create selection
- **Threshold Adjustment:** Fine-tune selection sensitivity to capture all background pixels
- **Deletion:** Use Delete key or Edit menu to remove selected areas
- **Export Navigation:** Access `File → Export As` and configure PNG export settings
- **Selection Management:** Understand when to deselect after operations

### B. GIMP Knowledge
- **Alpha Channel Concept:** Understand what alpha channels are and why they're needed for transparency
- **Layer Transparency:** Know that layers must have alpha channels to support transparent pixels
- **Select by Color Tool:** Understand how color selection works with threshold parameters
- **Threshold Sensitivity:** Know how to adjust threshold to capture color variations
- **File Format Limitations:** Understand that JPEG doesn't support transparency, PNG does
- **Selection Visualization:** Interpret "marching ants" to see what will be deleted
- **Background vs. Foreground:** Distinguish between subject and background areas

### C. Task-Specific Skills
- **Background Recognition:** Identify the background color/region to be removed
- **Threshold Judgment:** Determine appropriate threshold to select all background without selecting subject
- **Edge Preservation:** Ensure clean edges around the subject after background removal
- **Completeness Assessment:** Verify all background areas were successfully removed
- **Quality Control:** Check for residual background pixels or unwanted transparency in subject
- **Format Selection:** Choose PNG export for transparency preservation

## Task Steps

### 1. Initial Image Analysis
- Examine the image that opens automatically in GIMP (object on white background)
- Identify the main subject and the white background to be removed
- Note any color variations in the background that might affect selection

### 2. Add Alpha Channel
- Navigate to `Layer → Transparency → Add Alpha Channel`
- This enables the layer to support transparent pixels
- Note: If the menu item is grayed out, the layer already has an alpha channel

### 3. Activate Select by Color Tool
- Select the "Select by Color Tool" from the toolbox or press Shift+O
- Observe cursor change indicating color selection mode is active
- Ensure tool options show reasonable threshold (typically 10-20)

### 4. Select White Background
- Click on the white background area
- Observe "marching ants" selection appearing around all white/similar areas
- If needed, hold Shift and click additional white areas to add to selection
- Adjust threshold in tool options if selection is incomplete or includes subject

### 5. Verify Selection
- Visually inspect that all background areas show "marching ants"
- Ensure the main subject is NOT selected (no marching ants around it)
- If subject is partially selected, reduce threshold and re-select

### 6. Delete Background
- Press the Delete key to remove the selected background
- Observe that deleted areas now show the checkerboard pattern (transparency indicator)
- The subject should remain intact with clean edges

### 7. Deselect
- Navigate to `Select → None` or press Ctrl+Shift+A
- Remove the selection to see the final result clearly

### 8. Export as PNG
- Navigate to `File → Export As`
- Change filename to "background_removed.png"
- Ensure file format is PNG (not JPEG)
- Click "Export" and confirm any PNG export options
- Note: The post-task hook may handle export automatically

## Verification Strategy

### Verification Approach
The verifier uses **alpha channel analysis and transparency detection** to validate background removal:

### A. Format and Alpha Channel Verification
- **PNG Format Check:** Confirms the output file is PNG format (supports transparency)
- **Alpha Channel Detection:** Verifies the image has an alpha channel/transparency layer
- **Mode Validation:** Ensures image mode is RGBA (not RGB), indicating transparency support

### B. Transparency Analysis
- **Background Region Detection:** Identifies areas that were white/background in the original
- **Alpha Value Measurement:** Measures transparency (alpha channel values) in former background regions
- **Transparency Threshold:** Verifies that background areas have low alpha (transparent/semi-transparent)
- **Coverage Calculation:** Measures what percentage of former background is now transparent

### C. Subject Preservation Analysis
- **Subject Region Detection:** Identifies the main subject area (non-white regions in original)
- **Opacity Verification:** Confirms subject areas remain opaque (high alpha values)
- **Edge Quality Assessment:** Checks for clean transitions between opaque and transparent regions
- **Detail Preservation:** Ensures subject details weren't accidentally removed

### D. Quality Metrics
- **Completeness Score:** Percentage of background successfully made transparent
- **Subject Integrity:** Percentage of subject that remained opaque
- **Edge Cleanliness:** Measurement of clean vs. jagged edges using gradient analysis
- **Residual Background:** Detection of leftover white pixels that should have been removed

### Verification Checklist
- ✅ **PNG with Alpha:** Output is PNG format with alpha channel (RGBA mode)
- ✅ **Background Transparent:** ≥70% of original white background areas now transparent (alpha < 50)
- ✅ **Subject Preserved:** ≥85% of original subject areas remain opaque (alpha > 200)
- ✅ **Clean Execution:** No catastrophic errors (entire image transparent, format wrong, etc.)

### Scoring System
- **100%:** All 4 criteria met with excellent background removal (≥90% background transparent, ≥95% subject preserved)
- **75-99%:** 3-4 criteria met with good background removal but minor edge issues
- **50-74%:** 2-3 criteria met with partial success but significant residual background or subject damage
- **0-49%:** <2 criteria met or fundamental failures (wrong format, no transparency, subject removed)

**Pass Threshold:** 75% (requires good background removal with subject preservation)

## Technical Implementation

### Files Structure