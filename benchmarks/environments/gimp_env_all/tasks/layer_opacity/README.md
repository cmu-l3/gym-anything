# GIMP Layer Opacity Adjustment Task (`layer_opacity@1`)

## Overview

This task tests an agent's ability to navigate GIMP's layers panel and modify layer opacity to create transparency effects. The agent must locate the layers panel, identify the opacity control, and adjust the layer's opacity to a specific percentage. This represents one of the most fundamental layer manipulation skills in digital image editing, essential for blending, overlays, and transparency effects.

## Rationale

**Why this task is valuable:**
- **Layer System Foundation:** Introduces GIMP's core layer-based editing paradigm
- **Essential Blending Skill:** Opacity control is fundamental to composite image creation
- **Interface Navigation:** Tests ability to locate and use the layers panel effectively
- **Precision Control:** Requires setting exact numeric values using slider or input controls
- **Professional Technique:** Represents basic skill needed for virtually all advanced GIMP workflows
- **Visual Feedback:** Provides immediate, clear visual feedback for learning reinforcement

**Skill Progression:** This task establishes foundational layer manipulation concepts needed before advancing to complex layer effects, blend modes, or multi-layer compositions.

## Skills Required

### A. Interaction Skills
- **Panel Navigation:** Locate and access the Layers panel (may require enabling if hidden)
- **Slider Manipulation:** Use opacity slider to achieve precise percentage values
- **Numeric Input:** Alternative direct entry of opacity percentage values
- **Visual Assessment:** Recognize when the desired transparency level is achieved
- **Interface Recognition:** Identify layer thumbnail and associated controls

### B. GIMP Knowledge
- **Layers Panel System:** Understand GIMP's layers interface and organization
- **Opacity Concepts:** Know how opacity affects layer visibility and blending
- **Percentage System:** Understand that 100% = opaque, 0% = invisible, 50% = semi-transparent
- **Layer Selection:** Ensure correct layer is active before applying opacity changes
- **Real-time Preview:** Understand that opacity changes show immediately in canvas
- **Layer Properties:** Distinguish opacity from other layer properties (blend modes, etc.)

### C. Task-Specific Skills
- **Transparency Assessment:** Visually judge appropriate transparency levels
- **Precision Targeting:** Achieve specific percentage values (not just approximate)
- **Effect Recognition:** Understand how opacity changes affect the overall image appearance
- **Quality Evaluation:** Recognize when transparency effect looks natural and appropriate

## Task Steps

### 1. Initial Image Examination
- Examine the flower image that opens automatically in GIMP
- Note that it appears as a normal, fully opaque image
- Identify any existing layers in the layers panel

### 2. Locate Layers Panel
- Find the Layers panel in the interface (typically on the right side)
- If layers panel is not visible, access it via `Windows → Dockable Dialogs → Layers`
- Ensure the layers panel is active and visible

### 3. Identify Target Layer
- Locate the image layer in the layers panel (likely named "Background" or similar)
- Confirm this layer is selected/active (highlighted in the layers panel)
- Observe the current opacity setting (should be 100%)

### 4. Locate Opacity Control
- Find the opacity slider/input field in the layers panel
- Identify that it's currently set to 100% (fully opaque)
- Understand the control mechanism (slider and/or numeric input)

### 5. Adjust Opacity to Target Value
- Modify the opacity to exactly 65% using either:
  - Dragging the opacity slider to the appropriate position
  - Directly typing "65" in the opacity input field
- Monitor the canvas to see the transparency effect take place

### 6. Verify Transparency Effect
- Confirm the image now appears semi-transparent
- Check that the opacity value shows exactly 65% in the layers panel
- Ensure the transparency effect looks smooth and even across the image

### 7. Final Quality Check
- Verify the image maintains its visual quality while being semi-transparent
- Confirm the background (checkerboard pattern) is visible through the image
- Ensure the opacity change applied to the entire layer uniformly

### 8. Automatic Export
- The post-task hook will automatically export the result as "flower_65_opacity.png"

## Verification Strategy

### Verification Approach
The verifier uses **mathematical transparency analysis** to measure and validate opacity changes:

### A. Pixel-Level Transparency Analysis
- **Alpha Channel Measurement:** Analyzes the alpha (transparency) channel values across the image
- **Opacity Calculation:** Calculates average opacity by comparing pixel intensity to expected 65% values
- **Statistical Validation:** Uses statistical methods to confirm consistent transparency application
- **Pixel Sampling:** Samples multiple image regions to ensure uniform opacity application

### B. Reference Comparison Method
- **Reference Generation:** Creates a mathematical reference image at exactly 65% opacity
- **Pixel-wise Comparison:** Compares actual result against the mathematically perfect reference
- **Tolerance Analysis:** Accounts for GIMP's rendering variations while maintaining precision
- **Structural Similarity:** Uses advanced similarity metrics to validate transparency quality

### C. Background Blend Analysis
- **Checkerboard Detection:** Verifies that GIMP's transparency checkerboard pattern is visible
- **Blend Calculation:** Measures how much background shows through the semi-transparent layer
- **Edge Preservation:** Ensures opacity changes don't blur or distort image edges
- **Color Consistency:** Confirms colors remain accurate despite transparency

### D. Opacity Precision Validation
- **Target Percentage Check:** Verifies opacity is within ±3% of the target 65%
- **Consistency Analysis:** Ensures opacity is uniform across different image regions
- **Mathematical Accuracy:** Uses precise calculations to validate transparency levels
- **Quality Preservation:** Confirms image quality is maintained during opacity adjustment

### Verification Checklist
- ✅ **Target Opacity Achieved:** Image opacity measures between 62-68% (65% ±3% tolerance)
- ✅ **Transparency Uniform:** Consistent opacity across all image regions
- ✅ **Background Visible:** Checkerboard pattern or background shows through appropriately
- ✅ **Image Quality Preserved:** No degradation in image detail or color accuracy
- ✅ **Proper Export:** Image saved with correct transparency information

### Scoring System
- **100%:** Perfect 65% opacity with uniform application and quality preservation
- **75-99%:** Good transparency with minor deviation from target or slight non-uniformity
- **50-74%:** Recognizable opacity change but notable precision or quality issues
- **0-49%:** Insufficient or incorrect opacity adjustment

**Pass Threshold:** 75% (requires good opacity adjustment close to target value)

## Technical Implementation

### Files Structure
```
layer_opacity/
├── task.json               # Task configuration (7 steps, 90s timeout)
├── setup_opacity_task.sh   # Downloads flower image, launches GIMP
├── export_opacity.sh       # Automates export as "flower_65_opacity"
├── verifier.py            # Mathematical opacity analysis verification
└── README.md             # This documentation
```

### Advanced Verification Features
- **Multi-Method Analysis:** Combines alpha channel reading with intensity comparison
- **Reference Validation:** Creates perfect mathematical reference for comparison
- **Statistical Accuracy:** Uses robust statistical methods for opacity measurement
- **Format Handling:** Properly manages PNG transparency and various image formats
- **Quality Metrics:** Ensures transparency doesn't compromise image quality

This task provides essential foundation skills for layer-based image editing in GIMP, teaching core transparency concepts that are prerequisite for advanced compositing, blending, and professional image editing workflows.