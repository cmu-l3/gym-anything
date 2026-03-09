# GIMP Rectangle Stroke Task (`rectangle_stroke@1`)

## Overview

This task tests an agent's ability to use GIMP's selection tools combined with stroke operations to draw a rectangular outline on an image. The agent must create a rectangular selection in the center of the image, set an appropriate foreground color, and apply a stroke to create a visible border. This represents a fundamental technique for highlighting regions, creating frames, and adding graphic elements to images.

## Rationale

**Why this task is valuable:**
- **Selection Tool Fundamentals:** Introduces GIMP's Rectangle Select tool, one of the most commonly used selection tools
- **Stroke vs. Fill Understanding:** Tests the agent's comprehension of outline operations (stroke) versus fill operations
- **Color Management:** Requires setting foreground color through GIMP's color selection system
- **Multi-step Workflow:** Combines selection creation with stroke application in a logical sequence
- **Real-world Relevance:** Common in highlighting image regions, creating frames, mockups, annotations, and graphic design
- **Foundation Operation:** Establishes concepts needed for more advanced selection and stroking operations

**Skill Progression:** This task bridges basic operations (like transforms) with intermediate selection-based editing, introducing stroke operations not covered by fill-based tasks.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Activate Rectangle Select tool from toolbox or use keyboard shortcut (R)
- **Click and Drag:** Create rectangular selection by dragging from corner to corner
- **Selection Sizing:** Control selection dimensions through drag operation
- **Color Setting:** Access and modify foreground color through toolbox color indicator
- **Menu Navigation:** Navigate to `Edit → Stroke Selection` through menu system
- **Dialog Interaction:** Work with Stroke Selection dialog and its parameters
- **Parameter Input:** Set or confirm stroke width value in pixels

### B. GIMP Knowledge
- **Selection Tools:** Understand the Rectangle Select tool's behavior and selection creation
- **Selection Visibility:** Recognize "marching ants" indicating active selection
- **Foreground/Background Colors:** Understand GIMP's dual color system in the toolbox
- **Stroke Operation:** Know the difference between "Stroke Selection" and "Fill Selection"
- **Stroke Width Concept:** Understand how line width affects the visual result
- **Selection Persistence:** Know that selections remain active until explicitly removed
- **Stroke Dialog Options:** Navigate basic stroke settings (solid color, width)

### C. Task-Specific Skills
- **Centered Positioning:** Judge appropriate placement to create a centered rectangle
- **Size Estimation:** Create a rectangle of reasonable size (not too small, not too large)
- **Color Selection:** Choose a contrasting color that will be visible against the background
- **Visual Balance:** Assess the aesthetic quality of the rectangle placement
- **Stroke Width Judgment:** Understand appropriate line thickness for visibility
- **Result Assessment:** Verify that the stroke creates a clear, visible outline

## Task Steps

### 1. Initial Image Examination
- Examine the landscape/nature image that opens automatically in GIMP
- Assess the image colors to determine a good contrasting color for the stroke
- Plan the rectangular selection size and position (centered, prominent but not overwhelming)

### 2. Activate Rectangle Select Tool
- Click on Rectangle Select tool in the toolbox (or press R key)
- Observe that the cursor changes to indicate selection mode
- Ensure the tool options show Rectangle Select is active

### 3. Create Rectangle Selection
- Click and drag to create a rectangular selection in the center of the image
- Aim for a rectangle that's roughly 50-70% of the image dimensions
- Release mouse to complete the selection
- Observe "marching ants" indicating the active selection

### 4. Set Foreground Color
- Click on the foreground color square in the toolbox (usually upper-left color indicator)
- In the color chooser dialog, select a bright, contrasting color (e.g., yellow, cyan, or red)
- Confirm the color selection
- Observe the foreground color indicator updates to show the new color

### 5. Access Stroke Selection
- Navigate to `Edit → Stroke Selection` in the menu bar
- Wait for the Stroke Selection dialog to open
- Observe the various stroke options available

### 6. Configure Stroke Parameters
- In the Stroke Selection dialog, verify stroke width (default 6-10 pixels is appropriate)
- Ensure "Stroke line" is selected (not "Stroke with a paint tool")
- Confirm solid color stroke is selected (the default)
- Adjust stroke width if needed (8-10 pixels recommended for visibility)

### 7. Apply Stroke
- Click "Stroke" button to apply the stroke operation
- Observe that a colored outline appears along the selection boundary
- The rectangle outline should now be clearly visible in the chosen color

### 8. Remove Selection (Optional)
- Navigate to `Select → None` or press Ctrl+Shift+A to remove the selection
- This clears the "marching ants" and shows the final result clearly

### 9. Automatic Export
- The post-task hook will automatically export the result as "rectangle_stroke.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **edge detection and pattern analysis** to identify and validate the rectangular stroke:

### A. Edge Detection and Analysis
- **Canny Edge Detection:** Uses OpenCV's Canny algorithm to detect strong edges in the image
- **Edge Filtering:** Identifies edges that represent significant color/intensity changes
- **Change Detection:** Compares edges in result vs. original to isolate newly added strokes
- **Rectangular Pattern Recognition:** Analyzes edge patterns to identify rectangular shapes

### B. Rectangle Identification
- **Hough Line Transform:** Uses probabilistic Hough transform to detect line segments
- **Horizontal/Vertical Line Detection:** Identifies strong horizontal and vertical lines
- **Rectangle Reconstruction:** Clusters lines into potential rectangular patterns
- **Geometric Validation:** Checks that detected lines form approximately closed rectangles

### C. Stroke Quality Assessment
- **Line Continuity:** Verifies that the rectangle edges are continuous (not fragmented)
- **Position Validation:** Confirms rectangle is roughly centered (not at image edges)
- **Size Validation:** Ensures rectangle is substantial (at least 30% of image dimensions)
- **Color Analysis:** Verifies the stroke uses a distinct color different from the background
- **Width Consistency:** Checks that stroke has consistent width along all edges

### D. Modification Verification
- **Significant Change Detection:** Confirms meaningful additions to the original image
- **Stroke vs. Fill Distinction:** Ensures the rectangle is an outline, not a filled region
- **Edge Strength:** Validates that new edges are strong enough to represent intentional strokes
- **Pattern Confidence:** Assesses overall confidence that a rectangular stroke was added

### Verification Checklist
- ✅ **Rectangular Edges Detected:** Strong horizontal and vertical lines identified in result
- ✅ **Centered Position:** Rectangle is positioned in the central region (not at borders)
- ✅ **Appropriate Size:** Rectangle dimensions are 30-80% of image dimensions
- ✅ **Clear Modification:** Significant edge additions detected compared to original
- ✅ **Stroke Pattern:** Edge pattern consistent with outline rather than filled shape

### Scoring System
- **100%:** Clear rectangular stroke detected with all criteria met (excellent execution)
- **75-99%:** Good rectangular stroke with minor issues in positioning or quality
- **50-74%:** Recognizable rectangle but with notable problems (incomplete, poor positioning)
- **0-49%:** No clear rectangular stroke detected or task failed

**Pass Threshold:** 75% (requires clear rectangular stroke with good positioning)

## Technical Implementation

### Files Structure