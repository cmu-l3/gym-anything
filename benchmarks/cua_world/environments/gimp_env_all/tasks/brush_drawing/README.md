# GIMP Brush Tool Drawing Task (`brush_drawing@1`)

## Overview

This task tests an agent's ability to use GIMP's brush tool to create simple painted content on a canvas. The agent must select the brush tool, configure basic brush settings, choose an appropriate color, and paint visible strokes on the image. This represents the most fundamental creative operation in digital art and image editing - the ability to directly paint and draw.

## Rationale

**Why this task is valuable:**
- **Core Creative Tool:** The brush tool is fundamental to all digital painting and artistic work in GIMP
- **Direct Manipulation:** Tests direct canvas interaction rather than menu-based operations
- **Tool Configuration:** Introduces brush settings and tool options concepts
- **Color Application:** Combines color selection with tool usage in practical context
- **Hand-Eye Coordination:** Tests precise cursor movement and drawing control
- **Creative Foundation:** Essential skill for photo retouching, digital art, and image enhancement
- **Real-world Relevance:** Used in countless professional workflows for painting, masking, and corrections

**Skill Progression:** This task introduces hands-on creative tool usage, complementing the existing menu-driven operations with direct artistic interaction.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Navigate toolbox to select brush tool or use keyboard shortcut (P)
- **Click and Drag:** Create smooth brush strokes through mouse/cursor movement
- **Pressure Control:** Apply consistent pressure for even stroke appearance
- **Cursor Precision:** Control brush placement and stroke direction accurately
- **Tool Options:** Navigate and modify brush settings in tool options panel
- **Color Selection:** Choose and apply foreground colors for painting

### B. GIMP Knowledge
- **Brush Tool System:** Understand GIMP's brush tool behavior and painting mechanics
- **Tool Options Panel:** Navigate brush size, opacity, and other painting parameters
- **Color Management:** Use foreground/background color system effectively
- **Brush Dynamics:** Understand how brush settings affect stroke appearance
- **Layer Interaction:** Know how brush strokes interact with existing image content
- **Painting Modes:** Understand normal painting mode for direct color application

### C. Task-Specific Skills
- **Stroke Planning:** Plan brush stroke placement for visible, clear results
- **Size Judgment:** Choose appropriate brush size for the canvas and intended effect
- **Color Contrast:** Select colors that will be visible against the background image
- **Movement Control:** Execute smooth, deliberate brush movements
- **Coverage Assessment:** Ensure painted area is substantial enough to be detected
- **Visual Feedback:** Recognize successful paint application through visual changes

## Task Steps

### 1. Initial Canvas Assessment
- Examine the blank or lightly textured canvas that opens automatically in GIMP
- Identify appropriate areas for painting that will show contrast
- Plan where to place brush strokes for maximum visibility

### 2. Brush Tool Selection
- Click on the Brush Tool in the toolbox (paint brush icon) or press P key
- Observe cursor change to brush icon indicating tool is active
- Note the tool options panel updates to show brush settings

### 3. Brush Configuration
- Check brush size in tool options panel (ensure it's reasonably large, 20-50 pixels)
- Adjust brush size if necessary using slider or size input field
- Ensure opacity is set to 100% for full color coverage

### 4. Color Selection
- Click on foreground color in toolbox to open color chooser
- Select a contrasting color (e.g., red, blue, or black depending on background)
- Confirm color selection and close color dialog

### 5. Paint Brush Strokes
- Click and drag on the canvas to create visible brush strokes
- Create at least 2-3 distinct brush strokes in different areas
- Ensure strokes are substantial enough to be easily detected
- Vary stroke direction and length for natural appearance

### 6. Stroke Coverage Verification
- Visually confirm that painted strokes are clearly visible
- Ensure sufficient coverage area (at least 1% of canvas area painted)
- Check that strokes have good contrast against background

### 7. Automatic Export
- The post-task hook will automatically export the result as "brush_painting.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **delta-based paint detection** with coverage analysis to identify painted areas:

### A. Paint Detection Algorithm
- **Pixel Difference Analysis:** Calculates pixel-wise changes between original and painted image
- **Significant Change Threshold:** Identifies pixels with substantial color changes (>30 intensity units)
- **Connected Component Analysis:** Groups painted pixels into coherent stroke regions
- **Noise Filtering:** Removes small artifacts that don't represent intentional brush strokes

### B. Coverage and Quality Assessment
- **Paint Coverage Calculation:** Measures total percentage of canvas area with paint strokes
- **Stroke Coherence Analysis:** Evaluates whether changes form recognizable brush strokes
- **Color Contrast Verification:** Ensures painted areas have sufficient contrast for visibility
- **Distribution Assessment:** Checks that painting is distributed across multiple areas

### C. Brush Stroke Validation
- **Stroke Size Analysis:** Verifies that painted regions match expected brush stroke characteristics
- **Shape Recognition:** Identifies elongated, stroke-like shapes characteristic of brush usage
- **Continuity Check:** Ensures strokes show the continuous nature of brush painting
- **Intensity Consistency:** Validates that strokes show appropriate opacity and color strength

### D. Technical Verification
- **Modification Confirmation:** Verifies substantial changes occurred from original image
- **Quality Preservation:** Ensures no degradation of non-painted areas
- **Color Accuracy:** Confirms painted colors match selected foreground color
- **Tool Usage Evidence:** Detects patterns consistent with brush tool usage

### Verification Checklist
- ✅ **Substantial Paint Coverage:** At least 1% of canvas area shows significant paint changes
- ✅ **Coherent Brush Strokes:** Paint changes form recognizable stroke patterns
- ✅ **Good Contrast:** Painted areas have sufficient contrast for clear visibility
- ✅ **Multiple Strokes:** Evidence of at least 2-3 distinct brush stroke areas

### Scoring System
- **100%:** Excellent brush work with >2% coverage, clear strokes, and good contrast
- **75-99%:** Good painting with adequate coverage and recognizable brush strokes
- **50-74%:** Minimal but detectable painting with some stroke characteristics
- **0-49%:** Insufficient painting or no clear evidence of brush tool usage

**Pass Threshold:** 75% (requires clear evidence of effective brush tool usage)

## Technical Implementation

### Files Structure
```
brush_drawing/
├── task.json               # Task configuration (8 steps, 90s timeout)
├── setup_brush_task.sh     # Creates blank canvas, launches GIMP
├── export_brush.sh         # Automates export as "brush_painting"
├── verifier.py            # Advanced paint detection verification
└── README.md             # This documentation
```

### Verification Features
- **Delta-Based Detection:** Precisely identifies painted areas through pixel comparison
- **Morphological Analysis:** Uses advanced image processing to identify stroke patterns
- **Coverage Metrics:** Quantifies paint coverage and stroke distribution
- **Contrast Assessment:** Ensures painted content is clearly visible
- **Multi-criteria Validation:** Combines coverage, coherence, and quality measures

This task introduces essential creative tool usage skills, providing hands-on experience with GIMP's core painting functionality and establishing foundations for more advanced artistic and retouching operations.