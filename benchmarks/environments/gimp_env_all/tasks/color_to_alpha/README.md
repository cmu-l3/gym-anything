# GIMP Color to Alpha Task (`color_to_alpha@1`)

## Overview

This task tests an agent's ability to use GIMP's Color to Alpha feature to remove a solid background color from an image and create transparency. The agent must identify the background color, access the Color to Alpha tool, and convert the specified color (typically white) to full transparency. This represents an essential workflow for background removal, logo preparation, and image compositing.

## Rationale

**Why this task is valuable:**
- **Transparency Mastery:** Introduces GIMP's alpha channel and transparency concepts
- **Background Removal:** Tests one of the most common real-world image editing tasks
- **Color Understanding:** Requires understanding which color to target for removal
- **Compositing Foundation:** Essential skill for layering images and creating graphics
- **Real-world Application:** Critical for logo extraction, product photography, web graphics, and design workflows
- **Professional Technique:** Used extensively in commercial design and content creation

**Skill Progression:** This task bridges basic color operations with advanced compositing workflows, introducing transparency concepts essential for professional GIMP usage.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate to `Colors → Color to Alpha` through nested menu system
- **Dialog Interaction:** Work with the Color to Alpha dialog interface
- **Color Selection:** Identify or specify the target color for removal (typically white)
- **Visual Confirmation:** Recognize when transparency has been successfully created
- **Dialog Confirmation:** Apply changes using OK button

### B. GIMP Knowledge
- **Alpha Channel Concepts:** Understand transparency and alpha channel fundamentals
- **Color to Alpha Tool:** Know the purpose and behavior of this specialized filter
- **Transparency Visualization:** Recognize GIMP's checkerboard pattern indicating transparency
- **Layer Requirements:** Understand that layers must support alpha channels for transparency
- **File Format Implications:** Know that some formats (PNG, GIF) support transparency while others (JPEG) don't

### C. Task-Specific Skills
- **Background Color Identification:** Visually determine which color should be removed
- **Tolerance Assessment:** Understand that similar colors may also become transparent
- **Edge Quality Evaluation:** Assess whether transparent edges are clean and appropriate
- **Use Case Recognition:** Understand when color-to-alpha is the appropriate technique
- **Result Verification:** Confirm successful background removal and transparency creation

## Task Steps

### 1. Initial Image Assessment
- Examine the image that opens automatically in GIMP (typically logo or icon with white background)
- Identify the background color that should be removed (usually solid white)
- Note the subject/foreground that should remain opaque

### 2. Verify Alpha Channel Support
- Check that the layer supports transparency (Layer menu shows "Add Alpha Channel" grayed out)
- If needed, add alpha channel via `Layer → Transparency → Add Alpha Channel`
- Most modern GIMP images have alpha channel by default

### 3. Access Color to Alpha Tool
- Navigate to `Colors → Color to Alpha` in the menu bar
- Wait for the Color to Alpha dialog to open
- Observe the preview showing potential transparency effect

### 4. Configure Target Color
- The dialog defaults to white (#FFFFFF) as the target color
- Verify white is the correct color to remove (usually it is)
- If different color needed, click the color swatch to choose alternative

### 5. Preview the Effect
- Observe the preview pane showing how transparency will be applied
- Check that background is becoming transparent (shows checkerboard)
- Verify foreground subject remains properly visible

### 6. Apply Color to Alpha
- Click "OK" button to apply the transparency conversion
- Observe the image canvas now shows checkerboard pattern where background was removed

### 7. Verify Transparency
- Visually confirm transparent areas show the checkerboard pattern
- Ensure foreground subject remains intact with proper opacity
- Check edge quality around the subject

### 8. Automatic Export
- The post-task hook will automatically export the result as "transparent_logo.png"
- PNG format is required as it supports transparency

## Verification Strategy

### Verification Approach
The verifier uses **alpha channel analysis and transparency quantification** to validate background removal:

### A. Alpha Channel Detection
- **Format Verification:** Confirms output is in PNG or other transparency-supporting format
- **Alpha Channel Presence:** Verifies the image contains an alpha channel (RGBA vs RGB)
- **Mode Validation:** Ensures image is in appropriate mode for transparency (RGB + Alpha)

### B. Transparency Quantification
- **Fully Transparent Pixels:** Counts pixels with alpha = 0 (completely transparent)
- **Partially Transparent Pixels:** Analyzes pixels with 0 < alpha < 255 (semi-transparent edges)
- **Opaque Pixels:** Measures pixels with alpha = 255 (fully opaque foreground)
- **Transparency Percentage:** Calculates what portion of image became transparent

### C. Background Removal Analysis
- **White Pixel Reduction:** Measures decrease in pure white (#FFFFFF) pixels compared to original
- **Color Distribution Change:** Analyzes how color histogram shifted after processing
- **Background Coverage:** Estimates how much background was successfully removed
- **Edge Quality:** Examines transition zones between opaque and transparent regions

### D. Structural Integrity
- **Foreground Preservation:** Verifies that non-background elements retained proper opacity
- **Detail Maintenance:** Ensures fine details weren't inadvertently made transparent
- **Color Accuracy:** Confirms foreground colors weren't altered during processing
- **Clean Boundaries:** Checks for smooth, antialiased edges around transparent regions

### Verification Checklist
- ✅ **Alpha Channel Present:** Image contains transparency information (RGBA format)
- ✅ **Significant Transparency:** At least 15% of pixels are fully or partially transparent
- ✅ **Background Removed:** Substantial reduction in white pixels (≥30% decrease from original)
- ✅ **Proper Format:** Exported as PNG or other transparency-supporting format

### Scoring System
- **100%:** Perfect transparency with clean edges, proper alpha channel, excellent background removal
- **75-99%:** Good transparency with minor issues in coverage or edge quality
- **50-74%:** Adequate transparency but incomplete background removal or format issues
- **0-49%:** No transparency, incorrect format, or failed background removal

**Pass Threshold:** 75% (requires good background removal with proper transparency)

## Technical Implementation

### Files Structure