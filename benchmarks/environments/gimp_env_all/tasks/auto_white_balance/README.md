# GIMP Auto White Balance Task (`auto_white_balance@1`)

## Overview

This task tests an agent's ability to use GIMP's automatic white balance correction to fix color temperature issues in photographs. The agent must navigate to the auto white balance tool and apply it with a single click to correct color casts, representing one of the most fundamental photo correction operations in digital photography workflows.

## Rationale

**Why this task is valuable:**
- **Essential Photo Correction:** White balance correction is one of the first steps in professional photo editing workflows
- **Color Theory Foundation:** Introduces concepts of color temperature, color casts, and neutral color balance
- **One-Click Simplicity:** Tests understanding of GIMP's automatic color correction tools without complex parameters
- **Real-world Frequency:** Used in nearly every photo editing workflow to correct indoor/outdoor lighting issues
- **Professional Standard:** Represents industry-standard practice for correcting color temperature problems
- **Visual Problem Solving:** Requires recognizing color cast issues and knowing the appropriate tool to fix them

**Skill Progression:** This task bridges basic color operations (like desaturate) with more advanced color correction, introducing automatic color analysis tools.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate through multi-level menu structure (`Colors → Auto → White Balance`)
- **Precise Selection:** Click on the correct auto-correction option among multiple choices
- **Instant Feedback Recognition:** Understand that the correction applies immediately without dialogs
- **Visual Assessment:** Compare before/after to recognize color correction effects

### B. GIMP Knowledge
- **Auto Color Tools:** Understand GIMP's suite of automatic color correction functions
- **White Balance Concept:** Know that white balance neutralizes color temperature casts
- **Menu Organization:** Navigate the Colors menu and Auto submenu structure
- **Immediate Application:** Recognize that auto corrections apply instantly without parameter dialogs
- **Color Temperature:** Basic understanding of warm (orange/yellow) vs cool (blue) color biases

### C. Task-Specific Skills
- **Color Cast Recognition:** Identify unwanted color tints in photographs (e.g., orange indoor lighting)
- **Neutral Reference Understanding:** Know that white balance aims to make neutral tones truly neutral
- **Correction Evaluation:** Judge whether color correction improved the image's color accuracy
- **Photography Fundamentals:** Understand that different lighting conditions create different color temperatures
- **Tool Selection:** Choose the appropriate automatic correction for the problem at hand

## Task Steps

### 1. Initial Image Examination
- Examine the photograph that opens automatically in GIMP
- Identify the color cast or temperature bias (typically orange/warm indoor lighting or blue/cool shadows)
- Note areas that should be neutral gray or white but appear tinted

### 2. Navigate to Colors Menu
- Click on "Colors" in the menu bar to open the colors menu
- Observe the various color adjustment options available

### 3. Access Auto Corrections
- Hover over "Auto" to open the automatic corrections submenu
- See the list of available automatic correction tools

### 4. Apply White Balance
- Click on "White Balance" from the Auto submenu
- Observe the immediate application of color correction
- Note how the color cast is reduced or eliminated

### 5. Visual Verification
- Observe that previously tinted areas now appear more color-neutral
- Verify that whites appear white and grays appear gray (not tinted)
- Confirm overall improvement in color accuracy

### 6. Automatic Export
- The post-task hook will automatically export the result as "white_balanced.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **color temperature and channel balance analysis** to detect effective white balance correction:

### A. Color Temperature Measurement
- **R/B Ratio Analysis:** Calculates the ratio of red to blue channel intensities as a temperature indicator
- **Temperature Shift Detection:** Measures how much the color temperature changed toward neutral
- **Warm/Cool Assessment:** Determines if an overly warm or cool image moved toward balance
- **Target Neutrality:** Evaluates if the result approaches neutral gray balance

### B. Channel Balance Analysis
- **RGB Mean Comparison:** Measures average values of R, G, B channels before and after
- **Channel Deviation:** Calculates how much RGB channels deviate from each other
- **Neutrality Score:** Quantifies overall color neutrality (lower deviation = more neutral)
- **Balance Improvement:** Confirms that channel relationships became more balanced

### C. Histogram Distribution
- **Channel Alignment:** Checks if RGB histograms are more aligned after correction
- **Midtone Analysis:** Focuses on midtone regions where neutral balance is most critical
- **Cast Reduction:** Measures reduction in color cast intensity across tonal ranges
- **Uniform Correction:** Verifies correction affects the full tonal range appropriately

### D. Change Detection
- **Modification Verification:** Confirms significant color changes occurred throughout the image
- **Appropriate Magnitude:** Ensures changes are substantial enough to represent real correction
- **Direction Validation:** Verifies correction moved toward neutrality, not away from it
- **Quality Preservation:** Ensures no introduction of color artifacts or posterization

### Verification Checklist
- ✅ **Color Temperature Shifted:** R/B ratio changed significantly toward neutral (1.0)
- ✅ **Channel Balance Improved:** RGB channel standard deviation reduced by ≥10%
- ✅ **Neutrality Enhanced:** Overall color cast intensity decreased measurably
- ✅ **Image Modified:** At least 15% of pixels changed by ≥15 intensity units

### Scoring System
- **100%:** All 4 criteria met (excellent white balance correction)
- **75-99%:** 3/4 criteria met (good color correction with minor residual cast)
- **50-74%:** 2/4 criteria met (partial correction but incomplete)
- **0-49%:** <2 criteria met (insufficient color correction)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

### Color Temperature Analysis Details