# GIMP Fuzzy Select and Fill Task (`fuzzy_select_fill@1`)

## Overview

This task tests an agent's ability to use GIMP's Fuzzy Select tool (magic wand) to intelligently select a contiguous region of similar colors, then fill that selection with a new color. The agent must identify an appropriate target area (typically a uniform background), use threshold-based selection to capture it completely, and apply a color fill to transform the selected region. This represents a fundamental image editing workflow used extensively in product photography, graphic design, and image composition.

## Rationale

**Why this task is valuable:**
- **Essential Selection Tool:** The Fuzzy Select tool (magic wand) is one of the most frequently used selection methods in image editing
- **Intelligent Selection:** Tests the agent's ability to use threshold-based, contiguous selection rather than simple geometric shapes
- **Common Workflow:** Represents a standard technique for background replacement, color correction, and image composition
- **Real-world Application:** Used extensively in e-commerce (product photos), graphic design (background changes), and photo editing (sky replacement)
- **Tool Coordination:** Combines selection creation with fill operations in a logical two-step workflow
- **Threshold Understanding:** Introduces the concept of tolerance/threshold in selection tools

**Skill Progression:** This task bridges basic geometric selections (rectangles, circles) with more intelligent, content-aware selection methods, making it ideal for intermediate skill development.

## Skills Required

### A. Interaction Skills
- **Tool Selection:** Access and activate the Fuzzy Select tool from toolbox or via keyboard shortcut (U)
- **Strategic Clicking:** Identify and click on the appropriate target area for selection
- **Threshold Adjustment:** Understand and potentially adjust selection threshold/tolerance for complete coverage
- **Selection Validation:** Visually confirm that the entire target area is selected (marching ants)
- **Fill Operation:** Execute fill command via Edit menu, bucket fill tool, or keyboard shortcut
- **Color Selection:** Choose and apply the specified fill color
- **Selection Management:** Clear selection after filling if needed

### B. GIMP Knowledge
- **Fuzzy Select Behavior:** Understand that fuzzy select chooses contiguous pixels of similar color
- **Threshold Concept:** Know how threshold affects selection sensitivity and coverage
- **Selection Modes:** Understand replace/add/subtract/intersect selection modes (though replace is sufficient here)
- **Fill Methods:** Know multiple ways to fill a selection (Edit → Fill, bucket fill tool, etc.)
- **Foreground/Background Colors:** Understand GIMP's color selection system
- **Selection Visualization:** Interpret "marching ants" to confirm selection boundaries
- **Tool Options:** Access tool options to adjust threshold if default selection is incomplete

### C. Task-Specific Skills
- **Background Identification:** Visually identify the uniform background area to be selected
- **Click Point Selection:** Choose an optimal point within the target area for consistent selection
- **Completeness Assessment:** Evaluate whether the selection captured the entire intended area
- **Threshold Judgment:** Determine if threshold adjustment is needed for better coverage
- **Color Contrast:** Choose a fill color that provides clear visual distinction from the original
- **Subject Preservation:** Ensure the selection doesn't include parts of the main subject

## Task Steps

### 1. Image Analysis
- Examine the product/object image that opens automatically in GIMP
- Identify the uniform background area (typically white or solid color)
- Note the boundary between subject and background
- Plan where to click for optimal fuzzy selection

### 2. Fuzzy Select Tool Activation
- Select the Fuzzy Select tool from the toolbox (or press U key)
- Observe that cursor changes to a magic wand icon
- Check the tool options panel for threshold setting (default usually works)

### 3. Select Background Area
- Click once on the center of the uniform background area
- Observe "marching ants" selection appear around the background
- Verify that the entire background is selected
- If selection is incomplete, adjust threshold in tool options and try again
- If threshold adjustment needed: increase threshold to capture more similar colors

### 4. Verify Selection Coverage
- Visually inspect the selection boundaries
- Ensure the entire background is included
- Confirm the main subject is NOT selected
- Look for gaps or overselection that might need correction

### 5. Prepare Fill Color
- Ensure the foreground color is set to light blue (or the specified target color)
- Use the foreground color selector or color picker if needed
- Common target: RGB(173, 216, 230) - light blue, or RGB(200, 200, 200) - light gray

### 6. Fill Selection
- Navigate to `Edit → Fill with FG Color` (or use bucket fill tool)
- Alternatively, use keyboard shortcut (Ctrl+; or Ctrl+,)
- Observe that the selected background area fills with the new color

### 7. Clear Selection
- Navigate to `Select → None` or press Ctrl+Shift+A
- Remove the marching ants to view the final result clearly

### 8. Automatic Export
- The post-task hook will automatically export the result as "background_filled.png"

## Verification Strategy

### Verification Approach
The verifier uses **multi-criteria color distribution analysis** to detect and validate the background color transformation:

### A. Original Background Color Analysis
- **Color Identification:** Automatically detects the dominant background color in the original image
- **Distribution Calculation:** Measures the percentage of pixels matching the original background color
- **Region Analysis:** Identifies which areas of the image contain the background color
- **Threshold-based Detection:** Uses color tolerance to account for slight variations (JPEG compression, lighting)

### B. Background Replacement Verification
- **Original Color Reduction:** Measures significant decrease in original background color pixels
- **New Color Introduction:** Verifies substantial increase in the target fill color (light blue/gray)
- **Pixel Count Analysis:** Calculates exact percentages of color distribution changes
- **Replacement Ratio:** Validates that the color shift is proportional and complete

### C. Subject Preservation Analysis
- **Center Region Protection:** Verifies that the central area (likely containing the subject) wasn't significantly altered
- **Selective Modification:** Confirms that color changes are localized to background regions
- **Edge Quality:** Checks that the boundary between subject and new background is clean
- **Detail Preservation:** Ensures fine details of the main subject remain intact

### D. Quality Assessment
- **Complete Coverage:** Verifies no significant patches of original background remain
- **Clean Boundaries:** Ensures selection quality was adequate (no jagged edges from poor threshold)
- **Color Accuracy:** Confirms the fill color approximately matches the target specification
- **Meaningful Change:** Validates that the transformation is substantial and correct

### Verification Checklist
- ✅ **Background Color Reduced:** Original background color decreased by ≥50% of total pixels
- ✅ **New Color Introduced:** Target fill color present in ≥10% of total pixels
- ✅ **Subject Preserved:** Center region (main subject) changed by <20% on average
- ✅ **Complete Transformation:** Replacement ratio appropriate (0.3-2.0 range)

### Scoring System
- **100%:** All 4 criteria met (excellent fuzzy select and fill)
- **75-99%:** 3/4 criteria met (good background replacement with minor issues)
- **50-74%:** 2/4 criteria met (partial success but incomplete transformation)
- **0-49%:** <2 criteria met (task not successfully completed)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure