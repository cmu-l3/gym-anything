# GIMP Threshold (High Contrast) Task (`threshold_effect@1`)

## Overview

This task tests an agent's ability to use GIMP's Threshold tool to convert an image into a high-contrast black-and-white effect. The agent must navigate to the Threshold dialog, adjust the threshold value to create a visually balanced result, and apply the transformation. This represents a fundamental tone manipulation operation commonly used for artistic effects, logo creation, and graphic design.

## Rationale

**Why this task is valuable:**
- **Tone Manipulation Introduction:** Introduces GIMP's powerful tonal adjustment tools in their simplest form
- **Binary Decision Making:** Tests understanding of converting grayscale values to pure black/white
- **Threshold Concept:** Builds foundation for understanding histograms and tonal distributions
- **Slider Interaction:** Teaches precise value adjustment using interactive controls
- **Artistic Application:** Demonstrates common technique for creating dramatic, high-contrast artistic effects
- **Logo/Graphics Design:** Essential skill for creating clean, printer-friendly graphics

**Skill Progression:** This task bridges basic menu navigation with tonal understanding, serving as an entry point to GIMP's more advanced color adjustment tools (Levels, Curves).

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through color adjustment menus (`Colors → Threshold`)
- **Dialog Management:** Work with interactive preview dialogs
- **Slider Manipulation:** Adjust threshold slider to achieve desired balance
- **Visual Assessment:** Preview results in real-time to evaluate quality
- **Value Confirmation:** Apply changes using OK/Apply buttons
- **Histogram Reading:** (Optional) Interpret histogram to understand tonal distribution

### B. GIMP Knowledge
- **Color Menu System:** Navigate GIMP's extensive color adjustment menu hierarchy
- **Threshold Concept:** Understand how threshold converts grayscale to binary black/white
- **Value Ranges:** Know that threshold values typically range 0-255 (8-bit)
- **Preview System:** Use live preview to assess effects before applying
- **Tonal Understanding:** Recognize that pixels above threshold become white, below become black
- **Layer Preservation:** Understand that threshold modifies pixel values directly

### C. Task-Specific Skills
- **Balance Assessment:** Evaluate when the black/white distribution creates a good effect
- **Detail Preservation:** Adjust threshold to maintain important features while creating contrast
- **Subject Recognition:** Identify the main subject and ensure it remains distinguishable
- **Artistic Judgment:** Recognize when the high-contrast effect is visually appealing
- **Threshold Selection:** Choose appropriate value based on image brightness and desired outcome

## Task Steps

### 1. Initial Image Analysis
- Examine the portrait or object image that opens automatically in GIMP
- Identify the overall brightness level and main subject
- Note which areas should become black vs. white for best effect

### 2. Access Threshold Tool
- Navigate to `Colors → Threshold` in the menu bar
- Observe the Threshold dialog opening with histogram display
- Notice the live preview showing current threshold effect

### 3. Understand the Threshold Dialog
- Observe the histogram showing the distribution of tones in the image
- Note the threshold range slider (typically two handles defining the range)
- Understand that areas between the handles become white, outside become black

### 4. Adjust Threshold Value
- Move the lower threshold slider to approximately 120-140 (mid-range)
- Observe the preview update in real-time
- Aim to keep the main subject clearly defined while creating dramatic contrast

### 5. Refine for Balance
- Fine-tune the slider position to achieve good detail preservation
- Ensure the subject doesn't become completely black or white
- Balance between too much black (muddy) vs. too much white (blown out)

### 6. Apply Threshold Effect
- Click "OK" or "Apply" button to apply the threshold transformation
- Observe that the image now contains only pure black and white pixels
- Verify the result shows clear, high-contrast separation

### 7. Automatic Export
- The post-task hook will automatically export the result as "threshold_effect.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **statistical color distribution analysis** to confirm proper threshold application:

### A. Binary Color Detection
- **Color Palette Analysis:** Counts the number of unique colors in the result image
- **Binary Verification:** Confirms image contains primarily pure black (0,0,0) and pure white (255,255,255)
- **Gray Elimination:** Ensures middle-tone gray values have been eliminated (≤5% of pixels)
- **JPEG Tolerance:** Accounts for minor compression artifacts that may introduce slight color variations

### B. Distribution Balance Analysis
- **Black Percentage Calculation:** Measures proportion of pure black pixels
- **White Percentage Calculation:** Measures proportion of pure white pixels
- **Balance Assessment:** Ensures neither black nor white dominates excessively (15%-85% each)
- **Visual Quality:** Validates that the distribution creates a meaningful, interpretable image

### C. Contrast Enhancement Verification
- **Histogram Transformation:** Compares original histogram to result histogram
- **Bimodal Distribution:** Confirms result shows strong peaks at 0 (black) and 255 (white)
- **Middle Tone Removal:** Verifies that middle-gray values have been eliminated
- **Contrast Ratio:** Ensures maximum contrast has been achieved

### D. Content Preservation
- **Detail Analysis:** Checks that major structures from original are still recognizable
- **Subject Visibility:** Uses edge detection to confirm main subject remains distinguishable
- **Information Retention:** Ensures the threshold didn't completely eliminate important features

### Verification Checklist
- ✅ **Binary Color Palette:** Image contains ≥90% pure black and white pixels
- ✅ **Gray Values Eliminated:** ≤5% of pixels are intermediate gray tones
- ✅ **Balanced Distribution:** Black and white each occupy 15%-85% of image
- ✅ **Image Modified:** Clear transformation from original multi-tone image

### Scoring System
- **100%:** Perfect threshold application with proper binary conversion and good balance
- **75-99%:** Good threshold effect with minor gray values remaining
- **50-74%:** Partial threshold with significant gray values still present
- **0-49%:** Threshold not properly applied or extreme imbalance

**Pass Threshold:** 75% (requires successful binary conversion with reasonable balance)

## Technical Implementation

### Files Structure