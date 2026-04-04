# GIMP Threshold (High Contrast Black & White) Task (`threshold_bw@1`)

## Overview

This task tests an agent's ability to use GIMP's threshold tool to convert an image into a pure black-and-white (binary) image with no grayscale values. Unlike desaturation (which creates grayscale), the threshold operation creates high-contrast, two-tone artwork where each pixel is either pure black or pure white based on a brightness cutoff. This represents a fundamental image processing technique used in document scanning, stencil creation, and high-contrast artistic effects.

## Rationale

**Why this task is valuable:**
- **Histogram Understanding:** Introduces GIMP's threshold tool and histogram-based adjustments
- **Binary Processing:** Tests understanding of converting continuous tone to binary values (distinct from grayscale)
- **Artistic Applications:** Used for creating stencils, silhouettes, and high-contrast art
- **Document Processing:** Essential for cleaning up scanned documents and improving text legibility
- **Clear Success Criteria:** Binary output is objectively verifiable through pixel value analysis
- **Color Theory Foundation:** Reinforces understanding of luminosity independent of color information

**Skill Progression:** This task bridges color adjustments with technical image processing operations, introducing histogram-based tools that are foundational for advanced editing workflows.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Access `Colors → Threshold` through the hierarchical menu system
- **Threshold Dialog Interaction:** Work with the threshold adjustment dialog interface
- **Histogram Reading:** Interpret the visual histogram representation of brightness distribution
- **Slider Manipulation:** Adjust threshold slider(s) to find appropriate cutoff value
- **Preview Observation:** Monitor real-time preview to assess threshold effectiveness
- **Dialog Confirmation:** Apply changes using OK button

### B. GIMP Knowledge
- **Threshold Tool Purpose:** Understand that threshold converts to pure black and white (not grayscale)
- **Histogram Concepts:** Recognize how pixel brightness distribution affects threshold results
- **Threshold Range Understanding:** Know that pixels below threshold become black, above become white
- **Preview System:** Understand that changes preview in real-time before applying
- **Colors Menu Organization:** Navigate the extensive Colors menu to locate threshold
- **Binary vs. Grayscale:** Distinguish threshold from desaturate and other color reduction operations

### C. Task-Specific Skills
- **Brightness Assessment:** Visually evaluate appropriate threshold value for the image content
- **Subject Preservation:** Choose threshold that preserves important image details and features
- **Contrast Judgment:** Balance between retaining recognizable detail and creating clean binary result
- **Artistic Vision:** Understand when threshold operation is appropriate for desired visual effect
- **Quality Evaluation:** Assess whether the binary result successfully represents the original subject

## Task Steps

### 1. Initial Image Assessment
- Examine the color photograph that opens automatically in GIMP
- Identify the key subjects and their relative brightness levels
- Consider what threshold value might effectively separate subjects from background
- Note areas of high contrast vs. subtle gradations

### 2. Access Threshold Tool
- Navigate to `Colors → Threshold` in the menu bar
- Wait for the Threshold dialog to open
- Observe the histogram showing the brightness distribution of all pixels

### 3. Examine Histogram
- Study the histogram to understand brightness distribution in the image
- Identify peaks and valleys that suggest natural separation points
- Note where the majority of subject pixels vs. background pixels are concentrated

### 4. Adjust Threshold Value
- Move the threshold slider(s) to adjust the black/white cutoff point
- Typically start around 127 (middle gray) but adjust based on image characteristics
- Observe the real-time preview to see immediate effects on the image
- Watch how different threshold values affect subject visibility

### 5. Optimize Threshold for Best Result
- Fine-tune the threshold to preserve important subject details and edges
- Ensure the result creates a clean, recognizable binary image
- Balance between maintaining detail and achieving high contrast separation
- Avoid extreme values that create solid black or solid white images

### 6. Apply Threshold
- Click "OK" to apply the threshold operation permanently
- Observe that the image is now pure black and white with no gray values
- Verify that important subject features remain clearly visible and recognizable

### 7. Automatic Export
- The post-task hook will automatically export the result as "threshold_bw.png"

## Verification Strategy

### Verification Approach
The verifier uses **rigorous pixel value distribution analysis** to confirm complete binary conversion:

### A. Binary Purity Check
- **Comprehensive Pixel Analysis:** Examines every pixel to determine if values are at extremes (near 0 or 255)
- **Grayscale Elimination:** Counts pixels that fall in the gray range (30-225)
- **Binary Percentage Calculation:** Determines what percentage of pixels are pure black or pure white
- **Compression Tolerance:** Allows small tolerance for JPEG/PNG compression artifacts near extremes

### B. Image Transformation Verification
- **Significant Change Detection:** Ensures the image was substantially modified from the color original
- **Contrast Amplification:** Verifies dramatic increase in contrast through bimodal distribution
- **Complete Color Removal:** Confirms all color information has been eliminated (R=G=B for all pixels)
- **Structure Preservation:** Ensures recognizable features and shapes remain in binary form

### C. Distribution Quality Assessment
- **Bimodal Histogram Analysis:** Examines histogram to verify distinct peaks at black and white extremes
- **Black/White Balance:** Checks that there's reasonable distribution (not 95%+ of single color)
- **Mid-tone Elimination:** Ensures middle-gray values (80-175) are virtually eliminated
- **Subject Visibility:** Validates that threshold value preserved meaningful image content

### D. Mathematical Validation
- **High Variance Confirmation:** Standard deviation should be high, indicating distinct black/white regions
- **Peak Detection:** Validates that pixel value histogram has clear peaks near 0 and 255
- **Range Collapse:** Confirms that the full 0-255 range collapsed to just endpoints
- **Channel Consistency:** Verifies R=G=B for all pixels (true achromatic result)

### Verification Checklist
- ✅ **High Binary Purity:** ≥95% of pixels are near-black (≤25) or near-white (≥230)
- ✅ **Bimodal Distribution:** Histogram shows clear concentration at black and white extremes
- ✅ **Balanced Result:** Neither black nor white dominates >90% of total image area
- ✅ **Image Substantially Modified:** Clear evidence of threshold transformation from color original

### Scoring System
- **100%:** Perfect binary conversion with ≥98% pure black/white pixels and excellent balance
- **75-99%:** Strong binary conversion with ≥95% pure black/white pixels
- **50-74%:** Partial conversion with remaining gray values (90-95% binary)
- **0-49%:** Failed conversion, significant gray values remain (<90% binary)

**Pass Threshold:** 75% (requires strong binary conversion with minimal intermediate gray values)

## Technical Implementation

### Files Structure