# GIMP Color Replacement Task (`color_replacement@1`)

## Overview

This task challenges an agent to use GIMP's color selection and adjustment tools to replace a specific color in an image. The agent must identify red areas in a car image and transform them to blue using GIMP's "Select by Color" tool combined with "Hue-Saturation" adjustments. This represents a sophisticated color manipulation workflow commonly used in digital art, product photography, and design.

## Rationale

**Why this task is valuable:**
- **Advanced Color Theory:** Tests understanding of HSV color space and hue relationships
- **Precision Selection:** Requires sophisticated use of selection tools with threshold adjustments
- **Color Workflow Mastery:** Combines multiple tools (selection + adjustment) in a logical sequence
- **Real-world Application:** Common in product photography, automotive design, fashion, and branding
- **Non-destructive Editing:** Teaches proper workflow using selections to limit color changes
- **Visual Problem Solving:** Requires analyzing color relationships and making appropriate adjustments

**Skill Progression:** This task represents advanced color manipulation, requiring both technical tool knowledge and artistic judgment about color relationships.

## Skills Required

### A. Interaction Skills
- **Precise Tool Selection:** Navigate to "Select → By Color Tool" or use Shift+O shortcut
- **Threshold Adjustment:** Fine-tune color selection sensitivity using threshold controls
- **Multiple Clicking:** Click on various red areas to build complete selection
- **Menu Navigation:** Access "Colors → Hue-Saturation" through nested menu system
- **Slider Manipulation:** Adjust hue slider to achieve red-to-blue transformation (~-120°)
- **Channel Selection:** Choose appropriate color channel (Reds) in Hue-Saturation dialog
- **Selection Management:** Use "Select → None" to clear selections after color changes

### B. GIMP Knowledge
- **Color Selection Tools:** Understand "Select by Color" tool behavior and parameters
- **Threshold Concepts:** Know how threshold affects selection sensitivity and edge quality
- **Selection Additive Mode:** Understand how holding Shift adds to existing selections
- **Hue-Saturation Dialog:** Navigate the HSV adjustment interface effectively
- **Color Channel Understanding:** Know why selecting "Reds" channel targets specific colors
- **Hue Wheel Relationships:** Understand that moving ~120° on hue wheel transforms red to blue
- **Selection Visualization:** Interpret "marching ants" to understand what areas are selected

### C. Task-Specific Skills
- **Color Recognition:** Visually identify all red and red-adjacent areas in the image
- **Color Theory Application:** Understand complementary colors and hue relationships
- **Selection Refinement:** Judge when selection is complete vs. needs additional areas
- **Hue Adjustment Precision:** Fine-tune hue slider to achieve true blue without over-shifting
- **Quality Assessment:** Evaluate if color change looks natural and complete
- **Edge Preservation:** Maintain clean edges during color transformation

## Task Steps

### 1. Image Analysis
- Examine the red car image that opens automatically in GIMP
- Identify all red and red-tinted areas that should be transformed
- Note different shades of red (bright red, dark red, metallic red variations)

### 2. Select by Color Tool
- Navigate to `Select → By Color Tool` or press Shift+O
- Observe that cursor changes to indicate color selection mode
- Check that threshold is set appropriately (usually 10-20 for car paint)

### 3. Build Color Selection
- Click on the primary red area of the car
- Hold Shift and click on additional red areas to add them to selection
- Adjust threshold if selection is too narrow (missing red areas) or too broad (including non-red areas)
- Continue until all red areas show "marching ants" selection

### 4. Open Hue-Saturation Dialog
- Navigate to `Colors → Hue-Saturation`
- Wait for the Hue-Saturation adjustment dialog to open

### 5. Configure Color Channel
- In the Hue-Saturation dialog, ensure "Reds" channel is selected
- This ensures adjustments only affect red colors, preserving other colors in the image

### 6. Adjust Hue for Red-to-Blue Transformation
- Move the Hue slider to the left (negative direction) approximately -120°
- Monitor the preview to see red areas transform to blue
- Fine-tune the adjustment until the color change looks natural and complete

### 7. Apply Color Change
- Click "OK" to apply the hue adjustment
- Observe that red areas have changed to blue while maintaining other colors

### 8. Clear Selection
- Navigate to `Select → None` or press Ctrl+Shift+A
- This removes the selection and shows the final result clearly

### 9. Automatic Export
- The post-task hook will automatically export the result as "red_to_blue_car.jpg"

## Verification Strategy

### Verification Approach
The verifier uses **sophisticated color analysis** to detect and quantify the color transformation:

### A. Color Distribution Analysis
- **RGB Color Space Analysis:** Precisely measures red and blue pixel percentages before and after
- **Color Range Definition:** Uses scientifically-defined ranges for red (high R, low G/B) and blue (low R/G, high B)
- **Multi-tone Detection:** Analyzes both bright and dark variations of red and blue
- **Percentage Tracking:** Calculates exact percentages of color distribution changes

### B. Transformation Metrics
- **Red Reduction Analysis:** Measures how much red color was eliminated from the image
- **Blue Increase Analysis:** Quantifies the increase in blue color areas
- **Color Shift Ratio:** Validates that blue increase correlates appropriately with red decrease
- **Threshold Validation:** Ensures color changes are significant enough to represent successful replacement

### C. Quality Preservation
- **Pixel Change Analysis:** Measures overall image modification using pixel-wise differences
- **Edge Preservation:** Verifies that color changes maintained clean boundaries
- **Non-target Color Protection:** Ensures other colors (whites, blacks, grays) remained unchanged
- **Natural Appearance:** Checks that color transformation looks realistic

### D. Mathematical Color Analysis
- **HSV Color Space Validation:** Confirms the hue shift approximates the expected 120° transformation
- **Saturation Preservation:** Verifies that color intensity was maintained during hue change
- **Brightness Consistency:** Ensures overall image brightness wasn't dramatically altered

### Verification Checklist
- ✅ **Red Reduction:** Significant decrease in red color percentage (≥2% absolute or ≥50% relative)
- ✅ **Blue Increase:** Meaningful increase in blue color percentage (≥1%)
- ✅ **Color Shift Ratio:** Blue increase appropriately correlates with red reduction (0.3-3.0 ratio)
- ✅ **Image Modified:** At least 5% of pixels significantly changed (>30 intensity units)

### Scoring System
- **100%:** All 4 criteria met (excellent color replacement)
- **75-99%:** 3/4 criteria met (good color transformation with minor issues)
- **50-74%:** 2/4 criteria met (partial success but incomplete transformation)
- **0-49%:** <2 criteria met (color replacement failed or minimal)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

### Color Analysis Details
```python
# Red Color Ranges (RGB values)
Red: R(120-255), G(0-100), B(0-100)
Dark Red: R(80-160), G(0-60), B(0-60)

# Blue Color Ranges (RGB values)  
Blue: R(0-100), G(0-120), B(120-255)
Dark Blue: R(0-60), G(0-80), B(80-200)
```

## Technical Implementation

### Files Structure
```
color_replacement/
├── task.json           # Task configuration (10 steps, 120s timeout)
├── setup_color_task.sh # Downloads red car image, launches GIMP
├── export_color.sh     # Automates export as "red_to_blue_car"
├── verifier.py         # Advanced color analysis verification
└── README.md          # This documentation
```

### Verification Utilities
- Uses shared `verification_utils.py` for robust file handling and fallback search
- Implements advanced RGB color space analysis with NumPy
- Includes sophisticated color distribution algorithms and mathematical validation
- Provides detailed feedback on color transformation quality and completeness
