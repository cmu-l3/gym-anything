# GIMP Eraser Tool Task (`eraser_transparency@1`)

## Overview

This task tests an agent's ability to use GIMP's Eraser tool to remove content and create transparent regions in an image. The agent must select the eraser tool, adjust its size appropriately, and erase a visible portion of the image to demonstrate transparency creation. This represents a fundamental image editing operation essential for photo manipulation, graphic design, and compositing workflows.

## Rationale

**Why this task is valuable:**
- **Fundamental Tool:** The eraser is one of the most basic and frequently-used tools in any image editor
- **Transparency Concepts:** Introduces alpha channel and transparency, critical for compositing and layering
- **Photo Editing Foundation:** Essential skill for background removal, object isolation, and photo retouching
- **Simple but Powerful:** Straightforward operation that enables complex workflows
- **Universal Application:** Used across photography, graphic design, web design, and digital art
- **Destructive Editing:** Teaches when and how to remove content permanently (vs. using masks)

**Skill Progression:** This task provides foundational knowledge of transparency and pixel removal, preparing agents for more advanced compositing and non-destructive editing techniques.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Access Eraser tool from toolbox or use Shift+E keyboard shortcut
- **Cursor Recognition:** Identify when eraser tool is active via cursor change
- **Brush Size Adjustment:** Modify eraser size using tool options or [ ] bracket keys
- **Click and Drag:** Perform continuous erasing strokes across image regions
- **Visual Feedback:** Recognize the checkerboard pattern indicating transparency

### B. GIMP Knowledge
- **Eraser Tool Behavior:** Understand that eraser removes pixels revealing transparency
- **Alpha Channel Concepts:** Know that transparency requires an alpha channel
- **Tool Options Panel:** Navigate and adjust eraser parameters (size, hardness, opacity)
- **Background vs. Layer:** Understand difference between background layers and layers with alpha
- **Checkerboard Pattern:** Recognize GIMP's visual representation of transparent areas
- **Brush-based Tools:** Know that eraser uses brush dynamics similar to paintbrush

### C. Task-Specific Skills
- **Strategic Erasing:** Choose appropriate areas to erase for clear visual demonstration
- **Size Judgment:** Select eraser size appropriate for the task (not too small, not too large)
- **Transparency Verification:** Visually confirm that transparent regions were created
- **Controlled Erasing:** Apply eraser strokes deliberately rather than randomly
- **Partial vs. Complete Removal:** Understand how to erase specific regions while preserving others

## Task Steps

### 1. Initial Image Analysis
- Examine the image (e.g., simple subject on background) that opens automatically in GIMP
- Note that the setup script has already ensured the layer has an alpha channel
- Identify a good region to erase that will clearly demonstrate transparency (e.g., upper-left corner, part of background)

### 2. Select Eraser Tool
- Click on the Eraser tool in the toolbox, or press Shift+E shortcut
- Observe cursor changes to indicate eraser mode is active
- Verify tool options panel shows eraser settings

### 3. Adjust Eraser Size
- In the Tool Options panel, locate the "Size" slider
- Increase the brush size to ~100-150 pixels for efficient erasing
- Alternatively, use [ and ] bracket keys to adjust size
- Ensure eraser is large enough to create a clearly visible transparent area

### 4. Erase Image Region
- Click and drag across a chosen region of the image (e.g., upper corner or edge area)
- Continue erasing until a substantial transparent area is created
- Observe the checkerboard pattern appearing where pixels were removed
- Erase enough area to be clearly visible but don't erase the entire image

### 5. Verify Transparency
- Visually confirm that transparent regions are present (checkerboard pattern visible)
- Ensure erased area is substantial and clearly demonstrates transparency
- Verify that significant portions of the image remain unerased

### 6. Automatic Export
- The post-task hook will automatically export the result as "erased_image.png"
- PNG format preserves transparency information for verification

## Verification Strategy

### Verification Approach
The verifier uses **alpha channel analysis** to detect and quantify transparency creation:

### A. Transparency Detection
- **Alpha Channel Verification:** Confirms output image has an alpha channel
- **Transparent Pixel Counting:** Precisely counts pixels with alpha < 255 (partially or fully transparent)
- **Transparency Percentage:** Calculates what percentage of image became transparent
- **Coverage Analysis:** Ensures transparent region is substantial (>2% of image area)

### B. Change Validation
- **Original Comparison:** Confirms original image had minimal or no transparency
- **Significant Modification:** Verifies that substantial transparency was added (not just 1-2 pixels)
- **Transparency Distribution:** Checks that erased area forms contiguous region (not just random pixels)
- **Excessive Erasure Check:** Ensures agent didn't erase too much (>80% would indicate over-erasure)

### C. Quality Assessment
- **Content Preservation:** Verifies that significant image content remains unerased
- **Reasonable Erasure:** Ensures erased amount is appropriate (typically 5-40% of image)
- **Clean Edges:** Checks that transparency edges are relatively clean (not excessively noisy)
- **Deliberate Action:** Confirms erasure pattern suggests intentional action vs. random clicking

### D. Format and Export Validation
- **PNG Format:** Confirms output is PNG (required for transparency preservation)
- **Alpha Channel Preservation:** Verifies alpha channel data was properly saved
- **Image Integrity:** Ensures image dimensions and remaining content are intact
- **No Corruption:** Validates file is properly formatted and readable

### Verification Checklist
- ✅ **Transparency Created:** Substantial transparent pixels detected (>2% of image area)
- ✅ **Significant Change:** Transparency increased meaningfully from original
- ✅ **Content Preserved:** At least 20% of image remains non-transparent
- ✅ **Reasonable Amount:** Erased area is between 2-80% of image
- ✅ **Proper Format:** Image exported as PNG with alpha channel

### Scoring System
- **100%:** Excellent transparency creation with 5-40% erased (ideal range)
- **90%:** Good transparency creation with 2-60% erased (acceptable range)
- **75%:** Adequate transparency with minor issues (too little or too much erased)
- **50%:** Minimal transparency created or technical issues
- **0%:** No meaningful transparency created or task failed

**Pass Threshold:** 75% (requires clear transparency creation with reasonable erasure amount)

## Technical Implementation

### Files Structure