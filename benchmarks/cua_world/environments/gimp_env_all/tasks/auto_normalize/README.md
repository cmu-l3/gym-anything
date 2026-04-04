# GIMP Auto-Normalize Task (`auto_normalize@1`)

## Overview

This task tests an agent's ability to use GIMP's automatic color normalization feature to improve image contrast and tonal distribution. The agent must navigate to the Auto-Normalize function and apply it to enhance an image with poor contrast or limited tonal range. This represents a fundamental, one-click image enhancement operation commonly used in photography and digital media workflows.

## Rationale

**Why this task is valuable:**
- **One-Click Enhancement:** Introduces GIMP's automatic image improvement tools
- **Histogram Optimization:** Teaches concepts of tonal distribution and dynamic range
- **Professional Workflow:** Standard first step in many photo editing workflows
- **Menu System Mastery:** Builds familiarity with Colors menu and Auto submenu
- **Quick Results:** Demonstrates powerful automatic adjustments without manual parameter tuning
- **Foundation Concept:** Establishes understanding of normalization for more advanced color work

**Skill Progression:** This task provides an entry point to color correction workflows, showing what automatic tools can achieve before manual adjustments.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through nested menu structure (`Colors → Auto → Normalize`)
- **Precise Selection:** Click on the correct auto-enhancement option
- **Immediate Application:** Understand that some operations apply instantly without dialogs
- **Visual Assessment:** Compare before/after to recognize improvement

### B. GIMP Knowledge
- **Colors Menu System:** Understand organization of GIMP's color adjustment tools
- **Auto Enhancement Tools:** Know about automatic image improvement features
- **Instant Application:** Recognize operations that apply without additional dialogs
- **Histogram Concepts:** Understand what normalization does to tonal distribution
- **Undo Capability:** Know that automatic operations can be undone if unsatisfactory

### C. Task-Specific Skills
- **Contrast Assessment:** Recognize images with limited tonal range
- **Histogram Understanding:** Understand how normalization spreads tones across full range
- **Quality Evaluation:** Assess whether automatic adjustment improved the image
- **Tonal Distribution:** Recognize when an image uses full black-to-white range
- **Dynamic Range:** Understand the concept of maximizing available tonal values

## Task Steps

### 1. Initial Image Assessment
- Examine the low-contrast image that opens automatically in GIMP
- Notice that the image appears flat or lacks punch
- Observe limited use of dark shadows or bright highlights

### 2. Navigate to Colors Menu
- Click on "Colors" in the menu bar to open the Colors menu
- Observe the various color adjustment options available

### 3. Access Auto Submenu
- Hover over or click "Auto" to open the automatic enhancement submenu
- Locate "Normalize" among the auto-adjustment options

### 4. Apply Normalization
- Click on "Normalize" to apply the automatic adjustment
- Observe that the operation applies immediately without additional dialogs
- Notice the image now has better contrast and uses fuller tonal range

### 5. Verify Enhancement
- Compare the result with your memory of the original appearance
- Confirm that shadows are darker and highlights are brighter
- Verify that the image has more "pop" and visual impact

### 6. Quality Check
- Ensure the adjustment looks natural and not over-processed
- Confirm that important details remain visible in shadows and highlights
- Verify that colors weren't distorted or clipped

### 7. Automatic Export
- The post-task hook will automatically export the result as "normalized_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **histogram analysis** to measure tonal distribution improvement:

### A. Histogram Distribution Analysis
- **Range Measurement:** Calculates the actual black point and white point in both images
- **Dynamic Range Expansion:** Verifies that result uses more of the 0-255 tonal range
- **Histogram Spread:** Measures how much tones are distributed across available range
- **Clipping Detection:** Ensures normalization didn't excessively clip shadows or highlights

### B. Contrast Enhancement Metrics
- **Standard Deviation Increase:** Measures overall contrast improvement via pixel value variance
- **Tonal Spread Ratio:** Compares the range of tones used before and after
- **Percentile Analysis:** Examines 1st and 99th percentiles to verify range expansion
- **Mean Preservation:** Confirms overall brightness remains reasonable

### C. Quality Assurance
- **Natural Appearance:** Validates that histogram changes represent realistic enhancement
- **No Posterization:** Ensures smooth tonal transitions are maintained
- **Color Balance:** Verifies that color relationships weren't distorted
- **Detail Preservation:** Confirms that detail in shadows and highlights is retained

### D. Mathematical Validation
- **Histogram Entropy:** Measures information content and distribution quality
- **Contrast Ratio:** Calculates quantitative contrast improvement
- **Range Utilization:** Measures percentage of 0-255 range actively used
- **Threshold Validation:** Ensures changes meet minimum thresholds for successful normalization

### Verification Checklist
- ✅ **Dynamic Range Expanded:** Result uses significantly more of 0-255 tonal range (≥20% increase)
- ✅ **Contrast Improved:** Standard deviation of pixel values increased by ≥15%
- ✅ **No Excessive Clipping:** <2% of pixels clipped at pure black (0) or pure white (255)
- ✅ **Image Modified:** Clear measurable histogram differences from original

### Scoring System
- **100%:** All 4 criteria met (excellent normalization with full range utilization)
- **75-99%:** 3/4 criteria met (good normalization with minor limitations)
- **50-74%:** 2/4 criteria met (some improvement but suboptimal)
- **0-49%:** <2 criteria met (insufficient normalization or failed operation)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure