# GIMP Indexed Color Mode Conversion Task (`indexed_color@1`)

## Overview

This task tests an agent's ability to convert an image from RGB mode to Indexed Color mode with a reduced color palette. The agent must navigate to the mode conversion menu, configure the palette options, and apply the conversion. This represents a fundamental image mode operation commonly used for GIF creation, file size reduction, and achieving retro/pixel art aesthetics.

## Rationale

**Why this task is valuable:**
- **Mode Understanding:** Introduces GIMP's different color mode systems (RGB, Indexed, Grayscale)
- **Color Palette Concepts:** Teaches how images can be represented with limited color sets
- **File Format Preparation:** Essential for creating GIFs and optimizing web graphics
- **Artistic Technique:** Used to achieve retro, pixel art, and posterized visual styles
- **Optimization Skills:** Demonstrates practical file size reduction while maintaining visual quality
- **Simple Yet Impactful:** Single operation produces dramatic, easily verifiable results

**Skill Progression:** This task introduces color mode concepts that are foundational for understanding image formats, web graphics, and artistic effects, while remaining as simple as basic transform operations.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Image → Mode → Indexed`)
- **Dialog Interaction:** Work with the Indexed Color Conversion dialog
- **Option Selection:** Choose appropriate palette generation method and color count
- **Confirmation Actions:** Apply conversion using OK button
- **Visual Assessment:** Recognize the posterization effect of color reduction

### B. GIMP Knowledge
- **Color Mode System:** Understand the distinction between RGB, Indexed, and Grayscale modes
- **Indexed Color Concept:** Know that indexed mode uses a fixed color palette rather than full RGB spectrum
- **Color Palette:** Understand how images can be represented with 2-256 colors
- **Dithering Options:** Recognize dithering methods for smooth color transitions with limited palettes
- **Mode Restrictions:** Understand that some operations are unavailable in Indexed mode
- **Format Implications:** Know that GIF format requires Indexed mode

### C. Task-Specific Skills
- **Palette Size Selection:** Choose appropriate color count for desired effect (e.g., 16 colors for noticeable effect)
- **Quality Assessment:** Balance between color reduction and visual quality
- **Posterization Recognition:** Identify the characteristic banding/posterization effect of limited palettes
- **Use Case Understanding:** Know when indexed color is appropriate (web graphics, retro effects, file size)

## Task Steps

### 1. Initial Image Examination
- Examine the colorful image that opens automatically in GIMP (e.g., landscape, abstract art)
- Note the full range of colors in the original RGB image
- Identify areas with color gradients that will show posterization clearly

### 2. Navigate to Mode Menu
- Click on "Image" in the menu bar to open the Image menu
- Locate and hover over "Mode" to open the mode submenu
- Identify the "Indexed..." option (note the ellipsis indicating a dialog will open)

### 3. Open Indexed Color Conversion Dialog
- Click on "Indexed..." from the Mode submenu
- Wait for the "Indexed Color Conversion" dialog to appear
- Observe the available options for palette generation and dithering

### 4. Configure Palette Options
- In the conversion dialog, locate the "Maximum number of colors" setting
- Set the color count to **16 colors** for a noticeable, easily verifiable effect
- Choose "Generate optimum palette" option (typically selected by default)
- Select dithering method (None, Floyd-Steinberg, or positioned - any is acceptable)

### 5. Apply Conversion
- Click "Convert" or "OK" button to apply the indexed color mode conversion
- Observe the image transform to use only the limited color palette
- Notice the posterization effect, especially in gradient areas

### 6. Verify Mode Change
- Optionally check Image → Mode menu to confirm "Indexed" is now checked
- Observe the reduced color range in the image

### 7. Automatic Export
- The post-task hook will automatically export the result as "indexed_image.png"

## Verification Strategy

### Verification Approach
The verifier uses **multi-layered mode and palette analysis** to confirm proper conversion:

### A. Image Mode Detection
- **PIL Mode Check:** Uses Python Imaging Library to directly detect image color mode
- **Mode Validation:** Confirms the image is in Palette mode ('P') rather than RGB mode
- **Definitive Test:** This is the primary and most reliable verification criterion

### B. Color Palette Analysis
- **Unique Color Counting:** Counts distinct colors in the converted image
- **Palette Size Validation:** Ensures color count is significantly reduced from typical RGB images
- **Target Range:** Verifies color count is approximately 16 (tolerance: 8-32 colors)
- **Optimization Check:** Confirms GIMP's palette generation created an efficient color set

### C. Visual Effect Verification
- **Posterization Detection:** Analyzes image for characteristic color banding
- **Gradient Simplification:** Detects reduction in smooth color transitions
- **Color Clustering:** Identifies discrete color regions rather than continuous gradients

### D. Image Modification Confirmation
- **Change Detection:** Ensures the image differs significantly from the original
- **Pixel Analysis:** Compares color distributions before and after conversion
- **Non-identical Verification:** Confirms the conversion actually occurred

### Verification Checklist
- ✅ **Mode Converted:** Image is in Indexed/Palette mode (not RGB)
- ✅ **Palette Reduced:** Color count is between 8-32 (target: 16)
- ✅ **Visual Effect:** Posterization/color banding is clearly visible
- ✅ **Image Modified:** Clear structural differences from original RGB image

### Scoring System
- **100%:** Perfect indexed conversion with correct mode and appropriate palette size
- **75-99%:** Indexed mode achieved but palette size slightly outside target range
- **50-74%:** Some color reduction achieved but mode conversion incomplete
- **0-49%:** Failed to convert to indexed mode or no significant color reduction

**Pass Threshold:** 75% (requires successful mode conversion and reasonable palette reduction)

### Technical Verification Details