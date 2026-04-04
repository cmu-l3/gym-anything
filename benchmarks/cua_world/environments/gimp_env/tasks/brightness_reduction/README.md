# GIMP Brightness Reduction Task (`brightness_reduction@1`)

## Overview

This task tests an agent's ability to use GIMP's brightness and contrast adjustment tools to make an image visually darker while preserving its essential structure and details. The agent must evaluate the current brightness level, apply appropriate adjustments using the Brightness-Contrast dialog, and ensure the result maintains good visual quality without over-darkening or losing important image information.

## Rationale

**Why this task is valuable:**
- **Visual Assessment Skills:** Tests the agent's ability to evaluate image brightness and make subjective quality judgments
- **Adjustment Tool Mastery:** Introduces the fundamental Colors adjustment menu system used throughout GIMP
- **Slider Control Precision:** Requires fine motor control and understanding of real-time preview systems
- **Quality Balance:** Teaches the balance between achieving the desired effect and preserving image quality
- **Common Workflow:** Brightness adjustment is one of the most frequently used image editing operations
- **Foundation Building:** Establishes concepts needed for more advanced color and exposure corrections

**Skill Progression:** This task serves as an entry point to GIMP's powerful color adjustment systems, building essential skills for photo enhancement and artistic image manipulation.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menus (`Colors → Brightness-Contrast`)
- **Dialog Management:** Work with the Brightness-Contrast adjustment dialog interface
- **Slider Manipulation:** Precise control of brightness slider for gradual adjustments
- **Real-time Preview:** Monitor live preview while making adjustments to assess quality
- **Value Assessment:** Determine appropriate adjustment levels through visual evaluation
- **Confirmation Actions:** Apply changes using OK button or Enter key

### B. GIMP Knowledge
- **Colors Menu System:** Understand GIMP's color adjustment hierarchy and organization
- **Brightness-Contrast Tool:** Know the purpose and behavior of brightness/contrast adjustments
- **Preview System:** Understand how GIMP's real-time preview works during adjustments
- **Non-destructive Workflow:** Recognize that adjustments can be refined before applying
- **Adjustment Range:** Understand the -100 to +100 scale for brightness adjustments
- **Quality Assessment:** Recognize signs of over-adjustment (clipping, loss of detail)

### C. Task-Specific Skills
- **Visual Evaluation:** Assess current image brightness and determine need for reduction
- **Target Recognition:** Understand what constitutes appropriate "darker" while maintaining quality
- **Detail Preservation:** Balance darkness with maintaining visible detail in shadow areas
- **Histogram Reading:** (Advanced) Understand how brightness changes affect tonal distribution
- **Aesthetic Judgment:** Determine when the image achieves the desired visual appeal

## Task Steps

### 1. Initial Image Assessment
- Examine the woman-by-tree image that opens automatically in GIMP
- Evaluate the current brightness level and overall exposure
- Identify areas that might become too dark with adjustment (shadows, dark clothing)

### 2. Access Brightness-Contrast Tool
- Navigate to `Colors → Brightness-Contrast` in the menu bar
- Wait for the Brightness-Contrast dialog to open
- Observe the current settings (typically 0 for both brightness and contrast)

### 3. Preview Setup
- Ensure the Preview checkbox is enabled (should be by default)
- This allows real-time visualization of changes before applying

### 4. Brightness Adjustment
- Click and drag the Brightness slider to the left (negative values)
- Start with small adjustments (around -10 to -20) and gradually increase
- Monitor the preview to see how the image darkness changes

### 5. Quality Assessment
- Evaluate whether the image is sufficiently darker but not over-darkened
- Check that important details remain visible in darker areas
- Ensure the adjustment creates a pleasing visual result

### 6. Fine-tuning (Optional)
- Make small additional adjustments if needed
- Consider slight contrast adjustments if they improve the overall result

### 7. Apply Changes
- Click "OK" to apply the brightness adjustment
- Observe the final result in the main GIMP window

### 8. Automatic Export
- The post-task hook will automatically export the result as "edited_darker.png"

## Verification Strategy

### Verification Approach
The verifier uses **mathematical brightness analysis** combined with **structural preservation assessment**:

### A. Brightness Calculation
- **Luminance Analysis:** Calculates the mathematical brightness using standard RGB-to-luminance conversion (0.299*R + 0.587*G + 0.114*B)
- **Normalized Comparison:** Compares brightness values on a 0-1 scale for consistent measurement
- **Reduction Threshold:** Validates that brightness was meaningfully reduced (minimum 5% decrease)
- **Statistical Validation:** Uses average pixel brightness across the entire image for robust measurement

### B. Structural Preservation
- **Mean Squared Error (MSE):** Measures pixel-level differences to ensure structure is maintained
- **Quality Threshold:** Ensures MSE stays below threshold indicating excessive quality loss
- **Detail Analysis:** Verifies that important image features remain recognizable
- **Edge Preservation:** Checks that major edges and shapes are preserved

### C. Range Validation
- **Over-darkening Prevention:** Ensures brightness wasn't reduced excessively (maximum 40% reduction)
- **Under-adjustment Detection:** Confirms adjustment was substantial enough to be meaningful
- **Quality Bounds:** Validates that the result maintains acceptable visual quality

### D. Image Integrity
- **Format Preservation:** Confirms exported image maintains proper format and dimensions
- **Modification Verification:** Ensures the image was actually changed from the original
- **Export Success:** Validates that the adjustment was properly saved

### Verification Checklist
- ✅ **Brightness Reduced:** Mathematical brightness decreased by at least 5%
- ✅ **Structure Preserved:** MSE below threshold indicating maintained quality
- ✅ **Reasonable Adjustment:** Brightness reduction within acceptable range (5-40%)
- ✅ **Image Modified:** Clear differences detected from original image

### Scoring System
- **100%:** All 4 criteria met with excellent brightness reduction and quality preservation
- **75-99%:** 3/4 criteria met (good adjustment with minor quality or range issues)
- **50-74%:** 2/4 criteria met (partial success but needs improvement)
- **0-49%:** <2 criteria met (adjustment failed or inadequate)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

### Mathematical Analysis Details
```python
# Brightness Calculation
def calculate_brightness(image):
    rgb_array = np.array(image.convert('RGB'))
    # Standard luminance formula
    brightness = 0.299 * rgb_array[:,:,0] + 0.587 * rgb_array[:,:,1] + 0.114 * rgb_array[:,:,2]
    return np.mean(brightness) / 255.0  # Normalize to 0-1

# Structure Preservation  
def structure_check_by_mse(original, result, threshold=0.02):
    mse = np.mean((np.array(original) - np.array(result.convert(original.mode))) ** 2) / (255**2)
    return mse < threshold
```

## Technical Implementation

### Files Structure
```
brightness_reduction/
├── task.json                 # Task configuration (10 steps, 120s timeout)
├── setup_brightness_task.sh  # Downloads source image, launches GIMP
├── export_result.sh          # Automates export as "edited_darker"
├── verifier.py              # Mathematical brightness analysis verification
└── README.md               # This documentation
```

### Verification Features
- **Robust Mathematical Analysis:** Uses industry-standard luminance calculations
- **Quality Preservation:** Ensures adjustment doesn't compromise image integrity
- **Flexible Thresholds:** Accommodates various degrees of brightness reduction
- **Comprehensive Feedback:** Provides detailed analysis of brightness changes and quality impact
- **Fallback File Search:** Uses shared verification utilities for reliable file handling
