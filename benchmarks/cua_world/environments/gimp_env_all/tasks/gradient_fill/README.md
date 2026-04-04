# GIMP Gradient Fill Task (`gradient_fill@1`)

## Overview

This task challenges an agent to use GIMP's gradient tool to apply a smooth color transition across an image or canvas. The agent must select the gradient tool, choose an appropriate gradient preset, and execute a gradient fill by clicking and dragging across the image area. This represents a fundamental digital design skill used extensively in backgrounds, overlays, and artistic effects.

## Rationale

**Why this task is valuable:**
- **Fill Tool Mastery:** Introduces GIMP's gradient system and fill operations
- **Color Theory Application:** Tests understanding of color transitions and gradient concepts  
- **Precise Execution:** Requires controlled click-and-drag movements for desired gradient direction
- **Design Foundation:** Establishes skills needed for background creation and artistic effects
- **Real-world Relevance:** Gradients are ubiquitous in web design, UI design, and digital art
- **Tool Coordination:** Combines tool selection, parameter setting, and execution in one workflow

**Skill Progression:** This task introduces fill operations and gradient concepts, bridging basic tool usage with intermediate design techniques.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Navigate toolbox to select Gradient Tool or use G shortcut
- **Parameter Control:** Access and modify gradient settings in tool options
- **Gradient Execution:** Execute click-and-drag motion to apply gradient across desired area
- **Direction Control:** Control gradient direction and extent through mouse movement
- **Visual Assessment:** Evaluate gradient quality and coverage after application

### B. GIMP Knowledge
- **Gradient Tool System:** Understand GIMP's gradient tool location and basic operation
- **Gradient Presets:** Navigate gradient selector and choose appropriate gradient patterns
- **Fill Concepts:** Understand how gradients fill image areas or active selections
- **Foreground/Background Colors:** Know how gradients relate to current color settings
- **Tool Options Panel:** Access gradient-specific settings and controls

### C. Task-Specific Skills
- **Gradient Direction Planning:** Understand how drag direction affects gradient orientation
- **Smooth Execution:** Execute controlled drag movements for clean gradient application
- **Coverage Assessment:** Ensure gradient covers appropriate portion of canvas/image
- **Quality Evaluation:** Recognize successful vs. failed gradient application
- **Color Transition Understanding:** Appreciate how gradients create smooth color blending

## Task Steps

### 1. Initial Canvas Assessment
- Examine the blank white canvas that opens automatically in GIMP
- Identify the area where gradient will be applied
- Note current foreground and background colors (typically black and white)

### 2. Gradient Tool Selection
- Click on the Gradient Tool in the toolbox or press G key
- Observe cursor change to indicate gradient tool is active
- Note that tool options panel shows gradient-specific controls

### 3. Gradient Selection
- In tool options panel, locate the gradient selector (usually shows current gradient preview)
- Click on gradient selector to open gradient chooser dialog
- Select an appropriate gradient (default "FG to BG (RGB)" is suitable)
- Close gradient selector if needed

### 4. Gradient Application Setup
- Position cursor at desired starting point for gradient (e.g., top of image)
- Prepare to drag to ending point (e.g., bottom of image for vertical gradient)
- Plan gradient direction based on desired visual effect

### 5. Execute Gradient Fill
- Click and hold at starting position
- Drag mouse to ending position while holding button down
- Release mouse button to apply gradient
- Observe gradient fills the canvas from start color to end color

### 6. Verify Gradient Quality
- Check that gradient appears smooth and covers intended area
- Ensure color transition is visible and appropriate
- Confirm gradient direction matches intended effect

### 7. Automatic Export
- The post-task hook will automatically export the result as "gradient_fill.png"

## Verification Strategy

### Verification Approach
The verifier uses **mathematical gradient analysis** to detect and validate smooth color transitions:

### A. Gradient Detection Analysis
- **Color Transition Measurement:** Analyzes pixel values along multiple scan lines to detect gradual color changes
- **Smoothness Verification:** Calculates color gradients (mathematical derivatives) to ensure smooth transitions
- **Coverage Assessment:** Measures what percentage of image shows gradient characteristics vs. solid color
- **Direction Analysis:** Determines primary gradient direction and validates consistent transition

### B. Mathematical Gradient Validation
- **Linear Regression Analysis:** Fits linear models to color channels across the image to detect gradient patterns
- **Variance Analysis:** Measures color variance along gradient direction vs. perpendicular direction
- **Transition Quality:** Calculates smoothness metrics to ensure gradual rather than abrupt color changes
- **Multi-channel Consistency:** Verifies that gradient affects multiple color channels appropriately

### C. Coverage and Quality Metrics
- **Fill Completeness:** Ensures gradient covers substantial portion of canvas (>70% of pixels)
- **Transition Range:** Verifies gradient spans significant color range (not just minor variations)
- **Smoothness Threshold:** Confirms gradient meets smoothness criteria for professional appearance
- **Uniformity Check:** Validates consistent gradient application without irregular patterns

### D. Change Detection
- **Modification Verification:** Confirms significant changes from blank canvas
- **Content Analysis:** Ensures result contains meaningful gradient content vs. solid fill
- **Quality Preservation:** Verifies gradient application didn't introduce artifacts or noise

### Verification Checklist
- ✅ **Gradient Detected:** Mathematical analysis identifies clear gradient patterns
- ✅ **Smooth Transitions:** Color changes are gradual and professional-quality
- ✅ **Adequate Coverage:** Gradient fills substantial portion of canvas (≥70%)
- ✅ **Significant Change:** Clear difference from original blank canvas detected

### Scoring System
- **100%:** Perfect gradient with smooth transitions covering most of canvas
- **75-99%:** Good gradient quality with minor issues in smoothness or coverage  
- **50-74%:** Recognizable gradient present but with notable quality issues
- **0-49%:** No gradient detected or poor quality gradient application

**Pass Threshold:** 75% (requires good gradient quality with adequate coverage)

## Technical Implementation

### Files Structure
```
gradient_fill/
├── task.json              # Task configuration (7 steps, 90s timeout)
├── setup_gradient_task.sh # Creates blank canvas, launches GIMP
├── export_gradient.sh     # Automates export as "gradient_fill"
├── verifier.py           # Mathematical gradient analysis verification
└── README.md            # This documentation
```

### Verification Features
- **Mathematical Precision:** Uses linear regression and variance analysis for objective gradient detection
- **Multi-directional Analysis:** Tests for gradients in horizontal, vertical, and diagonal orientations
- **Quality Assessment:** Evaluates gradient smoothness and professional appearance
- **Coverage Validation:** Ensures gradient fills substantial portion of canvas
- **Robust Detection:** Handles various gradient types and orientations effectively

This task introduces fundamental fill operations while testing tool selection, parameter control, and execution coordination - essential skills for digital design and artistic workflows in GIMP.