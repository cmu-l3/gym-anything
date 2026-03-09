# GIMP Border Frame Task (`border_frame@1`)

## Overview

This task tests an agent's ability to use GIMP's decorative filter system to add a border (frame) around an image. The agent must navigate to the Border filter, configure the border size and color, and apply it to create a professionally framed image. This represents a common decorative operation used in photo presentation, social media content, certificates, and graphic design.

## Rationale

**Why this task is valuable:**
- **Decorative Filters Introduction:** Introduces GIMP's extensive decorative filter system (Filters → Decor)
- **Multi-parameter Configuration:** Tests ability to set multiple parameters (size, color) within a dialog
- **Dimension-Changing Operations:** Demonstrates filters that expand canvas size, unlike effects that only modify pixels
- **Color Selection Skills:** Requires aesthetic judgment in choosing complementary border colors
- **Real-world Relevance:** Extremely common in photo albums, social media posts, certificates, posters, and professional presentations
- **Visual Enhancement:** Tests understanding of decorative elements that improve presentation quality

**Skill Progression:** This task bridges basic single-parameter filters with more sophisticated multi-parameter decorative operations, ideal for intermediate-level training.

## Skills Required

### A. Interaction Skills
- **Deep Menu Navigation:** Navigate through nested filter hierarchy (`Filters → Decor → Border`)
- **Dialog Management:** Work with multi-parameter filter configuration dialogs
- **Numeric Input:** Enter specific values for border width/size parameters
- **Color Selection:** Use color picker or predefined colors for border styling
- **Preview Interpretation:** Understand preview window to assess changes before applying
- **Parameter Adjustment:** Fine-tune multiple related parameters for desired effect
- **Confirmation Actions:** Apply filter using OK/Apply buttons

### B. GIMP Knowledge
- **Filter System Architecture:** Understand GIMP's filter categories and organization
- **Decorative Filters:** Know the purpose and location of the Decor filter family
- **Border Filter Behavior:** Understand that Border filter increases image dimensions by adding frame
- **Color Picker Interface:** Navigate GIMP's color selection tools and presets
- **Canvas vs. Layer:** Recognize when operations affect canvas size vs. just pixels
- **Preview System:** Use preview windows to iterate on settings before final application

### C. Task-Specific Skills
- **Border Proportions:** Choose border width appropriate to image size and content
- **Color Aesthetics:** Select border colors that complement or appropriately contrast with image content
- **Visual Balance:** Assess whether border thickness enhances rather than overwhelms the image
- **Dimension Planning:** Anticipate how border size affects final output dimensions
- **Quality Assessment:** Evaluate whether the border achieves professional presentation quality

## Task Steps

### 1. Initial Image Analysis
- Examine the landscape/nature photograph that opens automatically in GIMP
- Note the current image dimensions (visible in title bar or Image → Image Properties)
- Observe the dominant colors and tones that might influence border color choice
- Consider what border width would be proportionally appropriate

### 2. Navigate to Border Filter
- Click on `Filters` in the menu bar
- Navigate to `Decor` submenu
- Select `Border` from the decorative filter options
- Wait for the Border filter dialog to open

### 3. Border Width Configuration
- Locate the border size/width parameter in the dialog
- Set the border width to an appropriate value (e.g., 20-30 pixels for typical images)
- Note that this width will be added to all four sides of the image
- Ensure the value is reasonable relative to image dimensions

### 4. Border Color Selection
- Locate the border color option in the dialog
- Click to open the color picker/selector
- Choose a color that complements the image (common choices: white, black, or colors from the image)
- Confirm the color selection

### 5. Preview and Refinement
- Observe the preview window showing how the border will appear
- Assess whether the border width and color work well with the image
- Adjust parameters if the initial configuration doesn't look optimal
- Ensure the border is visible and enhances the presentation

### 6. Apply Border Filter
- Click "OK" or "Apply" button to apply the border
- Observe that the image canvas has expanded to accommodate the border
- Verify that a uniform border appears around all edges of the image
- Confirm the original image content remains unchanged in the center

### 7. Quality Verification (Optional)
- Check the image dimensions to confirm they increased appropriately
- Examine all four edges to ensure border is uniform and clean
- Verify no unwanted artifacts or irregularities were introduced

### 8. Automatic Export
- The post-task hook will automatically export the result as "bordered_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **multi-criteria analysis** combining dimension verification, border detection, uniformity assessment, and content preservation:

### A. Dimension Verification
- **Size Increase Detection:** Confirms that both width and height increased from the original image
- **Minimum Growth Threshold:** Requires at least 10 pixels increase in each dimension (5px border per side minimum)
- **Maximum Growth Validation:** Ensures border size is reasonable (not exceeding 100px per side, which would be excessive)
- **Symmetric Expansion:** Validates that expansion is approximately symmetric (width and height increases are proportional)

### B. Border Detection and Analysis
- **Edge Pixel Analysis:** Examines pixel colors at the outer edges of the result image
- **Color Uniformity Check:** Calculates color variance at edges to detect uniform border regions
- **Four-Side Validation:** Analyzes top, bottom, left, and right edges independently
- **Border Width Estimation:** Measures the actual border width by analyzing edge uniformity depth
- **Contrast Assessment:** Ensures border color differs sufficiently from original image content

### C. Content Preservation
- **Center Region Comparison:** Extracts and compares center region of result with original image
- **Pixel-Level Similarity:** Uses SSIM or correlation to verify original content unchanged
- **No Content Distortion:** Confirms that adding border didn't alter, compress, or degrade the original image
- **Position Verification:** Validates that original content is properly centered within the new border

### D. Quality Assessment
- **Clean Boundaries:** Checks for sharp, clean transitions between border and image content
- **No Artifacts:** Verifies no unwanted visual artifacts, blending, or distortions at boundaries
- **Professional Appearance:** Assesses overall quality and visual appeal of the framed result
- **Appropriate Sizing:** Validates that border width is proportionally suitable (typically 1-5% of image dimensions)

### Verification Checklist
- ✅ **Dimensions Increased:** Both width and height increased by reasonable amounts (10-200px total)
- ✅ **Border Detected:** Uniform border region detected at all four edges through edge pixel analysis
- ✅ **Content Preserved:** Original image content in center region remains unchanged (SSIM ≥ 0.95)
- ✅ **Uniform Border:** Border color variance is low across all four edges (consistent appearance)

### Scoring System
- **100%:** All 4 criteria met (perfect border addition with uniform frame)
- **75-99%:** 3/4 criteria met (good border with minor uniformity or sizing issues)
- **50-74%:** 2/4 criteria met (partial success but notable quality or detection issues)
- **0-49%:** <2 criteria met (border addition failed or severely flawed)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure