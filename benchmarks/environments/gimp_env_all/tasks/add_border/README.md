# GIMP Add Border Task (`add_border@1`)

## Overview

This task tests an agent's ability to use GIMP's decorative filters to add a colored border around an image. The agent must navigate to GIMP's Border filter, configure border parameters (size and color), and apply the effect to create a framed appearance. This represents a common image preparation workflow used for presentations, social media posts, and print materials.

## Rationale

**Why this task is valuable:**
- **Filter System Introduction:** Introduces GIMP's extensive filter library and decorative effects
- **Canvas Concepts:** Teaches how operations can expand image dimensions
- **Practical Presentation Skill:** Borders are commonly used to frame images for professional presentation
- **Parameter Configuration:** Tests ability to work with filter dialogs and numeric parameters
- **Real-world Relevance:** Essential for creating polished images for portfolios, websites, and social media
- **Simple Yet Impactful:** Single operation that produces visually clear, professional results

**Skill Progression:** This task introduces filter usage at a basic level, establishing concepts needed for more complex filter operations while remaining accessible to intermediate learners.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Filters → Decor → Border`)
- **Dialog Interaction:** Work with the Border filter dialog interface
- **Parameter Input:** Enter numeric values for border size (pixels)
- **Color Selection:** Choose border color from color picker or presets
- **Preview Understanding:** Interpret preview to assess border appearance before applying
- **Effect Application:** Confirm and apply the filter operation

### B. GIMP Knowledge
- **Filter System:** Understand GIMP's filter organization and decorative effects category
- **Border Effect Behavior:** Know that borders expand image dimensions rather than overlay existing content
- **Dialog Workflow:** Understand that filter dialogs typically require confirmation (OK/Apply)
- **Dimension Changes:** Recognize that border operations increase image width and height
- **Color Specification:** Work with GIMP's color selection interface
- **Preview Capabilities:** Use preview to validate settings before final application

### C. Task-Specific Skills
- **Border Sizing:** Understand how pixel measurements translate to visual border width
- **Color Choice:** Select appropriate border colors that complement or contrast with image
- **Proportion Judgment:** Choose border sizes that balance with image dimensions
- **Visual Assessment:** Evaluate whether border enhances the image presentation
- **Professional Appearance:** Recognize when border application achieves desired framing effect

## Task Steps

### 1. Initial Image Examination
- Examine the landscape/photo image that opens automatically in GIMP
- Note the current image dimensions and appearance
- Plan an appropriate border size and color for the image

### 2. Navigate to Border Filter
- Click on "Filters" in the menu bar to open the Filters menu
- Hover over "Decor" to open the decorative effects submenu
- Locate "Border" option within the Decor submenu

### 3. Open Border Dialog
- Click on "Border" to open the Border filter dialog
- Observe the dialog interface with size and color options
- Note the preview area (if available) showing border effect

### 4. Configure Border Size
- Locate the border size parameter (typically in pixels)
- Set border size to approximately 20-30 pixels
- Understand this will expand the image by this amount on all sides

### 5. Select Border Color
- Choose border color from the color picker interface
- Select a contrasting color like black or white for clear framing
- Alternatively, choose a color that complements the image

### 6. Preview Assessment (if available)
- Check the preview to see how the border will appear
- Verify the border size looks appropriate for the image
- Adjust parameters if the preview indicates issues

### 7. Apply Border Effect
- Click "OK" or "Apply" button to execute the filter
- Observe that the canvas expands to accommodate the border
- Verify the border appears around all edges of the image

### 8. Visual Verification
- Examine the result to ensure border was applied correctly
- Confirm border is uniform around all sides
- Check that original image content remains intact in the center

### 9. Automatic Export
- The post-task hook will automatically export the result as "bordered_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **dimensional analysis and edge color detection** to validate border application:

### A. Dimension Validation
- **Size Increase Detection:** Verifies that output dimensions are larger than input dimensions
- **Expected Growth:** Checks that width and height both increased by approximately 2× border size
- **Minimum Threshold:** Ensures dimensions increased by at least 20 pixels in each direction
- **Reasonable Bounds:** Validates border isn't excessively large (>100px) or trivially small (<10px)

### B. Edge Color Analysis
- **Border Region Extraction:** Samples pixels from the outer edges of the image (border region)
- **Color Uniformity:** Analyzes whether border regions have consistent, distinct coloring
- **Contrast Detection:** Verifies border color differs significantly from original image content
- **Edge Detection:** Uses gradient analysis to confirm sharp boundaries between border and original content

### C. Content Preservation
- **Center Region Analysis:** Verifies original image content is preserved in central area
- **No Overlay:** Ensures border was added around the image, not overlaid on content
- **Quality Check:** Confirms original image detail wasn't degraded during border application
- **Proper Positioning:** Validates original content is centered within the expanded canvas

### D. Visual Quality Assessment
- **Border Uniformity:** Checks that all four sides received similar border treatment
- **Clean Edges:** Verifies sharp, professional boundaries between border and image
- **No Artifacts:** Ensures no compression artifacts or glitches were introduced
- **Professional Appearance:** Assesses overall quality of the border effect

### Verification Checklist
- ✅ **Dimensions Increased:** Width and height both grew by 20-100px
- ✅ **Edge Color Distinct:** Border regions have uniform, distinguishable color
- ✅ **Content Preserved:** Original image intact in center region
- ✅ **Uniform Border:** All four sides show consistent border treatment

### Scoring System
- **100%:** All 4 criteria met with excellent border application
- **75-99%:** 3/4 criteria met with good border but minor issues
- **50-74%:** 2/4 criteria met with recognizable border but notable problems
- **0-49%:** <2 criteria met, border application failed or minimal

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure