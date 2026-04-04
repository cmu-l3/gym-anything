# GIMP Ellipse Selection and Fill Task (`ellipse_fill@1`)

## Overview

This task tests an agent's ability to use GIMP's Ellipse Select Tool to create a circular or oval selection and fill it with a solid color. The agent must activate the ellipse selection tool, create an appropriately sized selection, choose a fill color, and apply the fill operation. This represents fundamental shape creation and color application skills essential for graphic design and image editing workflows.

## Rationale

**Why this task is valuable:**
- **Selection Tool Diversity:** Introduces curved selection boundaries as progression from rectangular selections
- **Shape Creation Skills:** Tests understanding of elliptical geometry and proportional shape creation  
- **Color Fill Mastery:** Reinforces solid color fill operations in a new context
- **Design Fundamentals:** Circular and oval shapes are core elements in graphic design and logos
- **Tool Progression:** Natural step from rectangle selection toward more advanced selection techniques
- **Real-world Application:** Common in creating buttons, badges, decorative elements, and design accents

**Skill Progression:** This task bridges basic rectangular selections with advanced selection tools, preparing agents for complex shape-based editing workflows.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Access Ellipse Select Tool from toolbox or use E keyboard shortcut
- **Proportional Dragging:** Create elliptical selections by dragging from one corner to opposite corner
- **Selection Management:** Understand and work with elliptical selection boundaries
- **Color Selection:** Choose appropriate fill color using foreground color picker
- **Fill Application:** Apply color using bucket fill tool or Edit→Fill with Foreground Color

### B. GIMP Knowledge  
- **Ellipse Selection Behavior:** Understand how ellipse tool creates oval and circular selections
- **Selection Concepts:** Know how "marching ants" work with curved boundaries
- **Fill Methods:** Choose between bucket fill tool and menu-based fill operations
- **Color System:** Work effectively with GIMP's foreground/background color system
- **Tool Options:** Understand basic ellipse selection parameters and behavior

### C. Task-Specific Skills
- **Circular Geometry:** Create visually pleasing, well-proportioned elliptical shapes
- **Spatial Planning:** Position and size selections appropriately within the image
- **Color Harmony:** Choose fill colors that complement the existing image content
- **Quality Assessment:** Create smooth, regular elliptical selections

## Task Steps

### 1. Image Analysis and Planning
- Examine the landscape image that opens automatically in GIMP
- Identify an appropriate location for placing a colored ellipse (center or off-center area)
- Consider what color would provide good contrast with the background

### 2. Ellipse Selection Tool Activation
- Click on the Ellipse Select Tool in the toolbox or press E key
- Observe that the cursor changes to indicate ellipse selection mode
- Verify that the tool is active by checking the toolbox highlighting

### 3. Create Elliptical Selection
- Position cursor at the desired starting point for the ellipse
- Click and drag diagonally to create an elliptical selection
- Aim for a moderately-sized ellipse that's visually prominent but balanced
- Release mouse button when satisfied with the selection size and shape

### 4. Selection Verification
- Observe the "marching ants" selection boundary forming an elliptical shape
- Ensure the ellipse is properly positioned and appropriately sized
- Recreate selection if needed to achieve desired shape

### 5. Choose Fill Color
- Set foreground color to a vibrant, contrasting color (e.g., bright red, blue, or yellow)
- Use the foreground color square in toolbox or color picker dialog
- Choose a color that will be clearly visible against the background image

### 6. Apply Fill Operation
- Use Edit→Fill with Foreground Color, or
- Select Bucket Fill tool (Shift+B) and click inside the selection
- Observe that the selected elliptical area fills with the chosen color

### 7. Clear Selection
- Use Select→None or Ctrl+Shift+A to remove the selection boundary
- View the final result with the colored ellipse integrated into the image

### 8. Automatic Export
- The post-task hook will automatically export the result as "ellipse_filled.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **delta-based region analysis** similar to the text overlay task to detect newly added colored areas:

### A. Change Detection
- **Pixel Difference Analysis:** Calculates pixel-wise differences between original and result images
- **Threshold-based Detection:** Identifies regions with substantial color changes (>30 intensity units)
- **Connected Component Analysis:** Groups changed pixels into coherent regions using clustering

### B. Shape and Fill Validation
- **Color Consistency:** Ensures detected regions have uniform color indicating solid fill
- **Size Requirements:** Validates that colored regions meet minimum area thresholds (≥800 pixels)
- **Compactness Assessment:** Checks that detected regions are reasonably compact and rounded
- **Color Contrast:** Confirms new colors provide adequate contrast against background

### C. Quality Assessment
- **Region Count:** Expects 1-3 distinct filled regions (allowing for multiple ellipses or complex shapes)
- **Color Uniformity:** Validates solid color fill rather than gradients or patterns
- **Clean Boundaries:** Ensures fill regions have clean edges without excessive fragmentation
- **Appropriate Integration:** Verifies additions enhance rather than detract from the image

### Verification Checklist
- ✅ **Substantial Changes:** Significant colored regions detected through delta analysis
- ✅ **Solid Fill:** Detected regions show consistent, uniform coloring
- ✅ **Appropriate Size:** New colored areas meet minimum size requirements (≥800 pixels total)
- ✅ **Good Contrast:** Fill colors provide clear visual distinction from background
- ✅ **Reasonable Shape:** Detected regions show compact, rounded characteristics suitable for ellipses

### Scoring System
- **100%:** Clear filled regions with excellent color uniformity and appropriate sizing
- **75-99%:** Good filled regions with solid colors, minor issues in size or contrast  
- **50-74%:** Recognizable filled areas but with notable quality or uniformity issues
- **0-49%:** No clear filled regions detected or poor execution

**Pass Threshold:** 75% (requires clear filled regions with solid colors and appropriate size)

## Technical Implementation

### Files Structure
```
ellipse_fill/
├── task.json              # Task configuration (8 steps, 90s timeout)
├── setup_ellipse_task.sh  # Downloads landscape image, launches GIMP
├── export_ellipse.sh      # Automates export as "ellipse_filled"
├── verifier.py           # Delta-based region detection verification
└── README.md            # This documentation
```

### Verification Features
- **Robust Region Detection:** Uses proven delta-based analysis similar to text overlay task
- **Color Uniformity Analysis:** Ensures proper solid color fills rather than gradients or noise
- **Size Validation:** Confirms filled regions are substantial enough to represent intentional shapes
- **Multi-region Support:** Handles cases where users create multiple filled ellipses
- **Quality Standards:** Maintains professional appearance with clean, solid fills

This task provides essential training in curved selection tools and shape creation, representing a natural progression from rectangle selection while maintaining appropriate difficulty for intermediate GIMP skill development.