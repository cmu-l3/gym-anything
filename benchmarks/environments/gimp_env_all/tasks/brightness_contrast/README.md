# GIMP Brightness/Contrast Adjustment Task (`brightness_contrast@1`)

## Overview

This task tests an agent's ability to use GIMP's brightness and contrast adjustment tools to improve the appearance of an underexposed or flat image. The agent must navigate to the Colors menu, access the Brightness-Contrast dialog, make appropriate adjustments to enhance image visibility and visual appeal, and apply the changes. This represents one of the most fundamental image correction operations in digital photography and image editing.

## Rationale

**Why this task is valuable:**
- **Core Image Adjustment:** Brightness/contrast is the foundation of photo editing and image correction workflows
- **Colors Menu Introduction:** Introduces GIMP's extensive color adjustment system in its most accessible form
- **Visual Assessment Skills:** Tests the agent's ability to evaluate and improve image quality
- **Slider Interface Mastery:** Builds familiarity with GIMP's adjustment dialog interfaces
- **Real-world Relevance:** Essential for photo correction, scanned document enhancement, and general image improvement
- **Foundation for Advanced Adjustments:** Establishes concepts needed for curves, levels, and other advanced color tools

**Skill Progression:** This task serves as the perfect introduction to GIMP's image adjustment capabilities, building skills needed for more sophisticated color correction operations.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate to `Colors → Brightness-Contrast` through the menu system
- **Dialog Management:** Work with the Brightness-Contrast adjustment dialog interface
- **Slider Manipulation:** Use slider controls to adjust brightness and contrast values
- **Preview Assessment:** Evaluate real-time preview changes to judge improvement quality
- **Value Input:** Optionally use numeric input fields for precise adjustments
- **Change Application:** Apply adjustments using OK button or Enter key

### B. GIMP Knowledge
- **Colors Menu System:** Understand the organization of GIMP's color adjustment tools
- **Adjustment Dialogs:** Know how brightness-contrast dialogs work with live preview
- **Value Ranges:** Understand typical adjustment ranges (-100 to +100 for both parameters)
- **Preview System:** Recognize how GIMP shows before/after comparisons in real-time
- **Non-destructive Preview:** Understand that changes aren't applied until confirmation
- **Image Enhancement Concepts:** Know that brightness affects overall lightness, contrast affects range

### C. Task-Specific Skills
- **Image Quality Assessment:** Visually evaluate whether an image appears too dark or too flat
- **Adjustment Planning:** Determine appropriate direction and magnitude for brightness/contrast changes
- **Visual Balance:** Balance brightness and contrast to achieve natural, appealing results
- **Enhancement Recognition:** Recognize when adjustments improve rather than degrade image quality
- **Restraint Application:** Avoid over-adjustment that leads to blown highlights or crushed shadows

## Task Steps

### 1. Image Analysis
- Examine the underexposed landscape image that opens automatically in GIMP
- Identify areas that appear too dark or lack sufficient contrast
- Note overall image tonality and areas that would benefit from enhancement

### 2. Access Brightness-Contrast Tool
- Navigate to `Colors → Brightness-Contrast` in the menu bar
- Wait for the Brightness-Contrast dialog to open
- Observe the initial slider positions (both typically at 0)

### 3. Assess Current Image State
- Look at the image in the main canvas with the dialog open
- Note the preview functionality that shows changes in real-time
- Identify whether brightness, contrast, or both need adjustment

### 4. Adjust Brightness
- Move the Brightness slider to the right (positive values) to lighten the image
- Aim for a moderate adjustment (typically +20 to +40) that improves visibility
- Watch the preview to ensure details remain visible without overexposure

### 5. Adjust Contrast
- Move the Contrast slider to the right (positive values) to increase contrast
- Aim for enhancement that makes the image more vivid (typically +15 to +35)
- Balance contrast to avoid harsh shadows or blown highlights

### 6. Fine-tune Adjustments
- Make small adjustments to both sliders to achieve optimal balance
- Ensure the image looks natural and improved compared to the original
- Use the preview to evaluate the overall enhancement quality

### 7. Apply Changes
- Click "OK" button to apply the brightness and contrast adjustments
- Observe that the dialog closes and changes are permanently applied to the image

### 8. Automatic Export
- The post-task hook will automatically export the result as "enhanced_landscape.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **statistical luminance analysis** combined with **contrast measurement** to objectively assess image enhancement:

### A. Brightness Analysis
- **Mean Luminance Calculation:** Converts images to LAB color space and measures L* (lightness) channel
- **Brightness Improvement Detection:** Compares mean brightness before and after adjustment
- **Reasonable Enhancement Range:** Validates that brightness increase is meaningful but not excessive (5-50 units)
- **Histogram Analysis:** Examines luminance distribution to ensure proper tonal adjustment

### B. Contrast Measurement
- **Standard Deviation Analysis:** Measures luminance standard deviation as contrast indicator
- **Contrast Enhancement Validation:** Confirms that contrast increased from original image
- **Dynamic Range Assessment:** Ensures contrast improvement doesn't cause clipping or loss of detail
- **Tonal Separation:** Verifies that contrast adjustment improved tonal distinction

### C. Quality Preservation
- **Clipping Detection:** Checks for excessive highlights (>95th percentile) or crushed shadows (<5th percentile)
- **Natural Appearance:** Ensures adjustments remain within realistic enhancement bounds
- **Detail Preservation:** Confirms that enhancement doesn't destroy image detail or introduce artifacts
- **Overall Improvement:** Validates that changes represent actual enhancement rather than degradation

### D. Mathematical Enhancement Validation
- **LAB Color Space Analysis:** Uses perceptually uniform color space for accurate brightness measurement
- **Statistical Significance:** Ensures changes are substantial enough to represent meaningful enhancement
- **Range Validation:** Confirms adjustments fall within typical photo enhancement parameters
- **Balanced Adjustment:** Checks that brightness and contrast work together harmoniously

### Verification Checklist
- ✅ **Brightness Improved:** Mean luminance increased by 5-50 LAB units (meaningful but not excessive)
- ✅ **Contrast Enhanced:** Luminance standard deviation increased by at least 3 units
- ✅ **No Severe Clipping:** Less than 2% of pixels at extreme values (0 or 255 in RGB)
- ✅ **Image Modified:** Clear statistical differences detected from original image

### Scoring System
- **100%:** Excellent enhancement meeting all criteria with optimal brightness and contrast improvement
- **75-99%:** Good enhancement with 3/4 criteria met, minor issues in one area
- **50-74%:** Adequate improvement with 2/4 criteria met, notable quality concerns
- **0-49%:** Insufficient or poor quality enhancement, <2 criteria met

**Pass Threshold:** 75% (requires good enhancement with minimal quality issues)

## Technical Implementation

### Files Structure
```
brightness_contrast/
├── task.json                    # Task configuration (6 steps, 90s timeout)
├── setup_brightness_task.sh     # Downloads underexposed image, launches GIMP
├── export_brightness.sh         # Automates export as "enhanced_landscape"
├── verifier.py                 # LAB color space statistical analysis
└── README.md                  # This documentation
```

### Verification Features
- **Perceptual Color Analysis:** Uses LAB color space for human-vision-aligned brightness measurement
- **Statistical Validation:** Objective measurement of enhancement quality using mathematical analysis
- **Quality Protection:** Prevents acceptance of over-processed images with clipping or artifacts
- **Balanced Assessment:** Evaluates both brightness and contrast improvements together
- **Scientific Accuracy:** Uses established computer vision techniques for reliable image analysis

This task introduces essential image enhancement skills while maintaining the straightforward difficulty level of existing tasks, providing a foundation for more advanced color correction workflows in GIMP.