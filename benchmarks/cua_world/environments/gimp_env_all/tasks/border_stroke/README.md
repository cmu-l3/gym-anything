# GIMP Add Border via Stroke Selection Task (`border_stroke@1`)

## Overview

This task tests an agent's ability to use GIMP's selection and stroke tools to add a decorative border around an image. The agent must select the entire canvas, navigate to the stroke selection feature, configure border properties (width and color), and apply the stroke to create a clean border frame. This represents a common image finishing technique used in design, photography, and document preparation.

## Rationale

**Why this task is valuable:**
- **Selection Tool Introduction:** Introduces the fundamental "Select All" operation used across many workflows
- **Stroke Technique:** Teaches the distinction between filling and stroking selections—a key concept in digital art
- **Border Creation Skill:** Demonstrates a practical method for adding professional borders without canvas extension
- **Multi-Tool Workflow:** Combines selection with styling operations in a logical sequence
- **Real-world Application:** Common in photo finishing, presentation graphics, certificate design, and print preparation
- **Foundation Operation:** Establishes concepts needed for more complex selection-based operations

**Skill Progression:** This task bridges basic selections with styling operations, introducing intermediate-level GIMP techniques in a simple, approachable format.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Access selection menu (`Select → All`)
- **Keyboard Shortcuts:** Optionally use Ctrl+A for selecting all
- **Nested Menu Access:** Navigate through `Edit → Stroke Selection`
- **Dialog Management:** Work with the Stroke Selection dialog interface
- **Parameter Input:** Set numeric values for stroke width
- **Color Selection:** Choose appropriate border colors
- **Dialog Confirmation:** Apply changes using OK/Stroke buttons

### B. GIMP Knowledge
- **Selection Concepts:** Understand how selections define areas for operations
- **Stroke vs. Fill:** Know the difference between stroking (outline) and filling (solid)
- **Selection Boundaries:** Understand that strokes follow selection edges
- **Stroke Positioning:** Know that strokes are drawn on the selection boundary
- **Color System:** Work with foreground/background colors or direct color selection
- **Selection Visibility:** Recognize "marching ants" indicating active selections

### C. Task-Specific Skills
- **Border Planning:** Understand appropriate border widths for image size
- **Color Choice:** Select border colors that complement or contrast with the image
- **Width Judgment:** Choose stroke widths that are visible but not overwhelming
- **Visual Balance:** Assess whether the border enhances the overall composition
- **Edge Awareness:** Understand how borders affect the visible image area

## Task Steps

### 1. Initial Image Examination
- Examine the photograph that opens automatically in GIMP
- Note the image content, colors, and overall composition
- Consider what border style would enhance the image

### 2. Select Entire Canvas
- Navigate to `Select → All` in the menu bar (or press Ctrl+A)
- Observe "marching ants" appear around the entire image border
- Confirm that the entire canvas is now selected

### 3. Access Stroke Selection Dialog
- Navigate to `Edit → Stroke Selection` in the menu bar
- Wait for the Stroke Selection dialog to open
- Observe the various stroke options available

### 4. Configure Stroke Width
- In the Stroke Selection dialog, locate the line width setting
- Set the stroke width to 15-20 pixels (appropriate for typical image sizes)
- Ensure the value is entered correctly

### 5. Configure Stroke Color
- Verify that the stroke color is set to black or a dark color
- If needed, set the foreground color before stroking
- Alternatively, choose color within the dialog if available

### 6. Apply Stroke
- Click "Stroke" button to apply the border
- Observe that a border appears around the image edges
- Wait for the operation to complete

### 7. Clear Selection (Optional)
- Navigate to `Select → None` or press Ctrl+Shift+A
- This removes the "marching ants" to view the final result clearly

### 8. Automatic Export
- The post-task hook will automatically export the result as "bordered_image.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **edge region analysis and border detection** to validate the stroke operation:

### A. Edge Region Comparison
- **Border Zone Definition:** Analyzes pixels in the outermost 30-pixel margin of the image
- **Darkness Analysis:** Compares edge region darkness before and after stroking
- **Mean Intensity Calculation:** Measures average brightness in border zones
- **Relative Change Detection:** Calculates percentage decrease in edge brightness

### B. Border Uniformity Assessment
- **Four-Edge Analysis:** Separately examines top, bottom, left, and right edges
- **Consistency Validation:** Ensures all four edges show similar darkening
- **Stroke Width Detection:** Estimates actual border width from darkened regions
- **Symmetry Verification:** Confirms border appears uniform around the entire image

### C. Center Preservation Check
- **Core Region Analysis:** Examines the central area (excluding outer 50px)
- **Minimal Change Requirement:** Verifies that the image center remains largely unaffected
- **Detail Preservation:** Ensures stroke operation didn't alter main image content
- **Change Localization:** Confirms darkening is concentrated at edges, not center

### D. Visual Border Detection
- **Edge Gradient Analysis:** Uses image derivatives to detect rectangular border structure
- **Corner Detection:** Verifies that borders form proper rectangles at corners
- **Color Consistency:** Checks that border color is relatively uniform
- **Width Validation:** Ensures border width is within expected range (10-40 pixels)

### Verification Checklist
- ✅ **Edge Darkening:** Border regions show significant darkening (≥15% reduction in brightness)
- ✅ **Uniform Application:** All four edges show similar darkening levels
- ✅ **Center Preserved:** Central image region remains >95% unchanged
- ✅ **Border Detected:** Clear rectangular border structure identified at edges

### Scoring System
- **100%:** All 4 criteria met with excellent border application
- **75-99%:** 3/4 criteria met (good border with minor uniformity issues)
- **50-74%:** 2/4 criteria met (border present but with significant problems)
- **0-49%:** <2 criteria met (border missing or improperly applied)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure