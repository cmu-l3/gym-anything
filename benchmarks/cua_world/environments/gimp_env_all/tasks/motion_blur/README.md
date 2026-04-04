# GIMP Motion Blur Task (`motion_blur@1`)

## Overview

This task tests an agent's ability to use GIMP's motion blur filter to create a directional blur effect that simulates movement or speed. The agent must navigate to the Motion Blur filter, configure the blur angle and distance parameters, and apply the effect to create a dynamic sense of motion in the image. This represents a common creative technique used in photography, sports imagery, and dynamic visual effects.

## Rationale

**Why this task is valuable:**
- **Creative Filter Application:** Introduces directional blur effects that differ from standard gaussian blur
- **Parameter Understanding:** Tests ability to work with angle and distance parameters in filters
- **Motion Simulation:** Teaches how to create visual effects that suggest speed and movement
- **Filter Menu Navigation:** Builds familiarity with GIMP's extensive blur filter options
- **Real-world Relevance:** Common in action photography, automotive imagery, sports graphics, and dynamic compositions
- **Preview-based Adjustment:** Requires understanding of real-time preview and parameter refinement

**Skill Progression:** This task extends basic filter knowledge (like gaussian blur) to directional, parameter-driven effects, representing intermediate filter mastery.

## Skills Required

### A. Interaction Skills
- **Multi-level Menu Navigation:** Navigate through `Filters → Blur → Motion Blur` menu hierarchy
- **Dialog Box Interaction:** Work with the Motion Blur parameter dialog
- **Angle Input:** Set blur angle using either slider or direct numeric input
- **Distance Adjustment:** Configure blur length/distance parameter appropriately
- **Preview Monitoring:** Observe real-time preview to assess effect quality
- **Parameter Refinement:** Adjust values based on visual feedback
- **Dialog Confirmation:** Apply changes using OK button

### B. GIMP Knowledge
- **Filter System Architecture:** Understand GIMP's hierarchical filter organization
- **Blur Filter Variants:** Distinguish motion blur from other blur types (gaussian, zoom, radial)
- **Directional Effects:** Understand how angle parameter affects blur direction
- **Distance/Length Concept:** Know how distance parameter controls blur intensity
- **Preview Functionality:** Recognize that filter previews show effect before application
- **Parameter Ranges:** Understand reasonable ranges for angle (0-360°) and distance values

### C. Task-Specific Skills
- **Motion Direction Choice:** Select appropriate angle to simulate desired movement direction
- **Effect Intensity:** Determine suitable distance/length for visible but not overwhelming blur
- **Visual Assessment:** Judge when motion blur creates desired dynamic effect
- **Artistic Intent:** Understand that horizontal blur (0° or 180°) suggests horizontal motion
- **Quality Balance:** Balance blur strength with image detail preservation

## Task Steps

### 1. Initial Image Examination
- Examine the sports/action image that opens automatically in GIMP
- Identify the subject and determine appropriate motion blur direction
- Plan the blur angle to suggest forward or lateral movement

### 2. Access Blur Filters
- Navigate to `Filters` in the menu bar
- Hover over or click `Blur` to open the blur submenu
- Locate and identify `Motion Blur` among the blur options

### 3. Open Motion Blur Dialog
- Click on `Motion Blur` to open the parameter dialog
- Observe the preview window showing the current effect
- Note the angle and length/distance parameter controls

### 4. Configure Blur Angle
- Set the blur angle to create horizontal motion effect (0° or 180°)
- Use either the angle dial, slider, or direct numeric input
- Observe preview update to show directional blur

### 5. Set Blur Distance
- Adjust the length/distance parameter to create noticeable motion (typically 15-30 pixels)
- Use slider or numeric input to set appropriate value
- Ensure blur is visible but doesn't completely destroy image detail
- Monitor preview to assess effect strength

### 6. Preview Assessment
- Examine the preview to confirm motion blur creates desired effect
- Check that blur direction is correct (horizontal for this task)
- Verify blur length creates clear sense of motion
- Make final adjustments if needed

### 7. Apply Motion Blur
- Click "OK" button to apply the motion blur effect
- Wait for GIMP to process the entire image
- Observe that the canvas now shows the motion-blurred result

### 8. Quality Verification
- Visually confirm that directional blur is applied across the image
- Check that blur creates sense of horizontal movement
- Verify image maintains recognizable subject despite blur

### 9. Automatic Export
- The post-task hook will automatically export the result as "motion_blur_result.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **directional blur analysis and pixel variance measurement** to detect motion blur:

### A. Directional Blur Detection
- **Gradient Analysis:** Calculates image gradients in horizontal and vertical directions
- **Directional Variance:** Measures pixel variance along horizontal vs. vertical axes
- **Blur Anisotropy:** Compares blur strength in different directions to detect directional effect
- **Edge Direction Analysis:** Examines edge orientations to identify dominant blur direction

### B. Blur Magnitude Assessment
- **Pixel Variance Change:** Measures overall reduction in pixel variance due to smoothing
- **Edge Softening Detection:** Analyzes edge sharpness reduction from blur application
- **High-frequency Reduction:** Uses frequency domain analysis to detect blur-induced smoothing
- **Directional Consistency:** Ensures blur is applied consistently across the image

### C. Horizontal Blur Verification
- **Horizontal Gradient Reduction:** Confirms stronger blur in horizontal direction
- **Vertical Edge Preservation:** Verifies vertical edges are more blurred than horizontal edges
- **Aspect-specific Analysis:** Measures blur strength along 0° axis vs. 90° axis
- **Directional Ratio:** Calculates ratio of horizontal to vertical blur strength

### D. Quality Preservation
- **Moderate Blur Check:** Ensures blur is noticeable but not excessive (image not destroyed)
- **Detail Retention:** Verifies that recognizable features remain in the image
- **Blur Range Validation:** Confirms blur distance is within reasonable range (10-50 pixels)
- **No Over-processing:** Ensures image isn't completely smoothed into uniformity

### Verification Checklist
- ✅ **Motion Blur Applied:** Clear evidence of blur filter application detected
- ✅ **Directional Effect:** Horizontal blur significantly stronger than vertical blur
- ✅ **Appropriate Magnitude:** Blur strength is noticeable but not excessive (20-60% variance reduction)
- ✅ **Image Modified:** Significant pixel-level changes detected from original
- ✅ **Quality Maintained:** Image retains recognizable subject and reasonable detail

### Scoring System
- **100%:** Perfect motion blur with clear horizontal direction and appropriate strength
- **75-99%:** Good motion blur with correct direction but minor magnitude issues
- **50-74%:** Motion blur detected but weak directionality or inappropriate strength
- **0-49%:** No clear motion blur or wrong blur type applied

**Pass Threshold:** 75% (requires clear directional motion blur with appropriate parameters)

## Technical Implementation

### Files Structure