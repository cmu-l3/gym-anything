# GIMP Feather Selection Task (`feather_selection@1`)

## Overview

This task tests an agent's ability to use GIMP's selection modification tools to create soft, feathered edges on a filled area. The agent must create a rectangular selection, apply a feather effect to soften the edges, and fill the selection with a solid color. The result will be a filled area with smooth, gradually fading edges rather than hard boundaries. This represents an essential selection technique used extensively in photo compositing, blending, and professional image editing.

## Rationale

**Why this task is valuable:**
- **Selection System Mastery:** Introduces GIMP's selection modification capabilities beyond basic selection creation
- **Edge Control:** Teaches the critical concept of soft vs. hard edges in digital imaging
- **Professional Technique:** Feathering is fundamental to natural-looking composites and seamless blending
- **Common Workflow:** Used in virtually every advanced editing task—masking, vignettes, focus effects, compositing
- **Foundation for Advanced Operations:** Establishes concepts needed for layer masks, gradient masks, and complex selections
- **Visual Quality Understanding:** Teaches how edge characteristics affect the professional appearance of edits

**Skill Progression:** This task bridges basic selection operations with advanced compositing techniques, making it ideal for intermediate-level training while remaining simple to execute.

## Skills Required

### A. Interaction Skills
- **Selection Tool Usage:** Create a rectangular selection using the Rectangle Select Tool
- **Menu Navigation:** Access `Select → Feather` through the menu system
- **Dialog Interaction:** Enter numeric values in the Feather Selection dialog
- **Color Management:** Set foreground color for filling operations
- **Fill Operations:** Apply fill to the feathered selection
- **Confirmation Actions:** Apply changes using appropriate buttons/keys

### B. GIMP Knowledge
- **Selection Concepts:** Understand what selections are and how they define editing boundaries
- **Selection Modification:** Know that selections can be modified after creation
- **Feather Concept:** Understand that feathering creates gradual transitions at selection edges
- **Fill Behavior:** Know how fill operations respect selection boundaries
- **Edge Softness:** Recognize the difference between hard and soft selection edges
- **Workflow Sequence:** Understand the order: select, modify (feather), then fill

### C. Task-Specific Skills
- **Edge Quality Assessment:** Visually evaluate whether edges are appropriately soft and gradual
- **Feather Radius Understanding:** Understand how the feather value (in pixels) affects transition zone width
- **Blending Awareness:** Recognize how feathered edges create natural-looking transitions
- **Appropriate Value Selection:** Choose reasonable feather values for the image size
- **Visual Quality Control:** Assess whether the feathered fill looks natural and professional

## Task Steps

### 1. Initial Image Examination
- Examine the landscape image that opens automatically in GIMP
- Identify a suitable area for creating a centered rectangular selection
- Plan approximate selection size and position

### 2. Create Rectangular Selection
- Select the Rectangle Select Tool from the toolbox (or press R)
- Click and drag to create a rectangular selection in the center of the image
- Aim for a selection approximately 40% of the image dimensions
- Observe the "marching ants" indicating the active selection

### 3. Access Feather Dialog
- Navigate to `Select → Feather` in the menu bar
- Wait for the Feather Selection dialog to open

### 4. Apply Feather Effect
- Enter a feather radius of **20 pixels** in the dialog
- Click "OK" to apply the feather to the selection
- Note that the selection appearance doesn't change visibly, but its edge behavior has been modified

### 5. Set Foreground Color
- Click the foreground color swatch in the toolbox
- Set the color to white (RGB: 255, 255, 255) or another bright, contrasting color
- Confirm the color selection

### 6. Fill Feathered Selection
- Navigate to `Edit → Fill with FG Color` or press Ctrl+; (semicolon)
- Alternatively, use the bucket fill tool
- Observe that the selection fills with white, but edges fade gradually into the background

### 7. Deselect to View Result
- Navigate to `Select → None` or press Ctrl+Shift+A
- Remove the selection to clearly see the feathered edges
- Verify that edges show smooth, gradual transitions

### 8. Automatic Export
- The post-task hook will automatically export the result as "feathered_fill.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **advanced edge gradient analysis** to detect and quantify the feather effect:

### A. Filled Region Detection
- **Change Detection:** Identifies areas that differ significantly from the original image
- **Region Identification:** Locates the primary filled rectangle using clustering analysis
- **Boundary Extraction:** Determines the approximate edges of the filled region
- **Position Validation:** Confirms the fill is centrally located as expected

### B. Edge Gradient Analysis
- **Edge Profile Extraction:** Samples pixel intensities perpendicular to edges at multiple points
- **Gradient Measurement:** Calculates the rate of intensity change across edge boundaries
- **Transition Zone Width:** Measures the distance over which the edge transitions occur
- **Smoothness Assessment:** Evaluates whether transitions are gradual rather than abrupt

### C. Feather Quality Metrics
- **Expected vs. Actual:** Compares measured transition width with expected ~20px feather radius
- **Edge Softness Score:** Quantifies how gradual the edge transitions are using derivative analysis
- **Consistency Check:** Verifies that all four edges show similar feather characteristics
- **Sharp Edge Rejection:** Ensures edges are NOT hard/sharp (which would indicate feather wasn't applied)

### Verification Checklist
- ✅ **Filled Region Detected:** Clear white or bright-colored fill identified in center area
- ✅ **Soft Edges Present:** Edge transitions are gradual, not sharp (transition zone ≥ 15px)
- ✅ **Appropriate Feather Width:** Measured transition width approximately matches 2× feather radius (30-50px range)
- ✅ **Consistent Feathering:** All edges show similar soft characteristics
- ✅ **Image Modified:** Substantial changes detected from original image (≥5% pixels altered)

### Scoring System
- **100%:** All 5 criteria met (excellent feathered fill with proper soft edges)
- **75-99%:** 4/5 criteria met (good feathering with minor issues)
- **50-74%:** 3/5 criteria met (feather applied but quality issues present)
- **0-49%:** <3 criteria met (feather not properly applied or fill missing)

**Pass Threshold:** 75% (requires at least 4 out of 5 criteria)

## Technical Implementation

### Files Structure