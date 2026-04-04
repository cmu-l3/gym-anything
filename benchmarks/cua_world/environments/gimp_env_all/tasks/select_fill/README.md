# GIMP Rectangle Selection and Fill Task (`select_fill@1`)

## Overview

This task tests an agent's ability to use GIMP's selection tools combined with fill operations to add a colored rectangle to an image. The agent must select the Rectangle Select tool, create a rectangular selection in a specific area, set the foreground color, fill the selection, and properly deselect. This represents fundamental selection and fill workflows essential for basic image editing and graphic design.

## Rationale

**Why this task is valuable:**
- **Selection Tool Introduction:** Introduces GIMP's powerful selection system with the most basic tool
- **Fill Operations:** Teaches fundamental fill techniques used throughout GIMP workflows
- **Color Management:** Introduces foreground/background color concepts and manipulation
- **Multi-step Workflow:** Combines tool selection, area definition, color setting, and fill application
- **Foundation Skill:** Establishes selection concepts needed for advanced masking, editing, and compositing
- **Real-world Application:** Common in logo creation, graphic design, photo editing, and digital art

**Skill Progression:** This task bridges basic tool usage with more advanced selection and painting concepts, preparing agents for complex selection-based operations.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Access Rectangle Select tool from toolbox or use R keyboard shortcut
- **Click and Drag:** Create rectangular selection by dragging from one corner to opposite corner
- **Color Management:** Set foreground color using color picker or color dialog
- **Fill Execution:** Apply fill operation using Edit menu or Bucket Fill tool
- **Selection Management:** Clear selection using Select → None menu option
- **Area Targeting:** Position selection accurately in specified image region

### B. GIMP Knowledge
- **Selection Tools:** Understand Rectangle Select tool behavior and selection creation
- **Selection Visualization:** Interpret "marching ants" selection indicators
- **Color System:** Understand foreground/background color concepts and switching
- **Fill Methods:** Know different ways to fill selections (menu vs. tools)
- **Selection States:** Understand when selections are active vs. cleared
- **Color Picker Interface:** Navigate color selection dialogs and controls

### C. Task-Specific Skills
- **Spatial Positioning:** Accurately place rectangular selection in upper-left area
- **Size Estimation:** Create appropriately sized selection (not too small or large)
- **Color Selection:** Choose bright, distinct red color for clear visibility
- **Workflow Sequence:** Execute steps in correct order: select → color → fill → deselect
- **Visual Assessment:** Verify that fill operation completed successfully
- **Clean Completion:** Ensure selection is properly cleared after filling

## Task Steps

### 1. Tool Activation
- Select the Rectangle Select tool from the toolbox or press R key
- Observe that cursor changes to crosshair indicating selection mode
- Prepare to create rectangular selection

### 2. Create Selection Area
- Position cursor in the upper-left area of the image (approximately top-left quadrant)
- Click and drag to create a rectangular selection roughly 100-150 pixels in size
- Observe "marching ants" indicating active selection

### 3. Set Foreground Color
- Click on the foreground color square in the toolbox (usually black by default)
- In the color picker dialog, set color to bright red (RGB: 255, 0, 0)
- Click OK to confirm color selection

### 4. Fill the Selection
- Navigate to Edit → Fill with Foreground Color (or use Alt+Backspace shortcut)
- Alternatively, select Bucket Fill tool and click inside the selection
- Observe that the selected area fills with red color

### 5. Clear Selection
- Navigate to Select → None (or use Ctrl+Shift+A shortcut)
- Observe that "marching ants" disappear, indicating selection is cleared
- Verify that red rectangle remains filled in the image

### 6. Quality Check
- Confirm red rectangle is clearly visible in upper-left area
- Ensure rectangle has clean, defined edges
- Verify original image areas outside rectangle remain unchanged

### 7. Automatic Export
- The post-task hook will automatically export the result as "red_rectangle.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **color detection and geometric analysis** to identify and validate the filled rectangle:

### A. Color Detection Analysis
- **Red Color Identification:** Scans for pixels with high red values and low green/blue values
- **Color Range Definition:** Uses scientifically-defined red ranges (R ≥ 200, G ≤ 100, B ≤ 100)
- **Clustering Detection:** Groups red pixels to identify coherent rectangular regions
- **Background Separation:** Distinguishes added red areas from any existing red in the original image

### B. Geometric Validation
- **Shape Analysis:** Uses connected component analysis to identify rectangular regions
- **Position Verification:** Confirms red area is located in upper-left quadrant of image
- **Size Assessment:** Validates rectangle is appropriately sized (minimum 50x50 pixels)
- **Edge Quality:** Analyzes rectangle edges for clean, straight boundaries

### C. Change Detection and Quality
- **Modification Verification:** Confirms significant pixel changes from original image
- **Regional Analysis:** Ensures changes are localized to expected area
- **Color Purity:** Validates that fill color is properly applied without transparency issues
- **Original Preservation:** Confirms areas outside rectangle remain unchanged

### D. Advanced Rectangle Detection
- **Bounding Box Analysis:** Calculates tight bounding boxes around red regions
- **Aspect Ratio Validation:** Ensures detected shape approximates rectangle proportions
- **Fill Completeness:** Verifies rectangle area is completely filled with red color
- **Mathematical Precision:** Uses computational geometry for accurate shape analysis

### Verification Checklist
- ✅ **Red Rectangle Detected:** Coherent red-colored rectangular region identified
- ✅ **Proper Positioning:** Rectangle located in upper-left quadrant as specified
- ✅ **Adequate Size:** Rectangle meets minimum size requirements (≥50x50 pixels)
- ✅ **Clean Execution:** Rectangle has defined edges and complete fill
- ✅ **Image Modified:** Clear evidence of fill operation addition to original

### Scoring System
- **100%:** Perfect red rectangle with excellent positioning, size, and execution
- **75-99%:** Good rectangle with minor issues in position, size, or edge quality
- **50-74%:** Recognizable rectangle present but with notable quality issues
- **0-49%:** Poor or missing rectangle, incorrect color, or execution problems

**Pass Threshold:** 75% (requires good rectangle with proper positioning and filling)

## Technical Implementation

### Files Structure
```
select_fill/
├── task.json              # Task configuration (8 steps, 90s timeout)
├── setup_select_task.sh   # Downloads landscape image, launches GIMP
├── export_select.sh       # Automates export as "red_rectangle"
├── verifier.py           # Advanced color and geometric analysis
└── README.md            # This documentation
```

### Verification Features
- **Sophisticated Color Detection:** Uses precise RGB range analysis for red identification
- **Geometric Analysis:** Employs connected component analysis for shape detection
- **Position Validation:** Confirms rectangle placement in correct image quadrant
- **Quality Assessment:** Evaluates fill completeness and edge quality
- **Size Verification:** Ensures rectangle meets minimum size requirements for visibility

### Error Handling and Robustness
- **Multiple Detection Methods:** Includes fallback algorithms when advanced libraries unavailable
- **Noise Filtering:** Removes small artifacts that might be misidentified as rectangles
- **Edge Case Handling:** Manages scenarios where multiple red regions exist
- **Quality Thresholds:** Uses multiple criteria to ensure robust rectangle identification

This task introduces essential selection and fill concepts while maintaining simplicity appropriate for intermediate GIMP skill development. It establishes foundation knowledge for more advanced selection-based operations and digital painting workflows.