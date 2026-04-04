# GIMP Layer Blend Mode Task (`blend_mode_multiply@1`)

## Overview

This task tests an agent's ability to work with GIMP's layer system and apply blend modes to create composite effects. The agent must locate the Layers panel, identify the active layer, and change its blend mode from "Normal" to "Multiply" to darken the underlying image. This represents a fundamental compositing operation essential for non-destructive photo editing and digital art workflows.

## Rationale

**Why this task is valuable:**
- **Compositing Foundation:** Blend modes are fundamental to layer-based image editing workflows
- **Non-destructive Editing:** Teaches how to combine layers without permanently altering originals
- **Layer System Understanding:** Tests comprehension of GIMP's core layer architecture
- **Professional Workflow:** Blend modes are used extensively in photography, design, and digital art
- **Visual Effect Control:** Demonstrates how layer interactions create complex visual results from simple operations
- **UI Navigation:** Requires finding and using the Layers panel, a central GIMP interface element

**Skill Progression:** This task bridges basic single-layer operations with advanced multi-layer compositing, introducing agents to sophisticated image manipulation through simple UI interactions.

## Skills Required

### A. Interaction Skills
- **Panel Location:** Find and access the Layers panel (may be docked or floating)
- **Dropdown Navigation:** Locate and click the blend mode dropdown menu
- **Option Selection:** Choose "Multiply" from a list of 20+ blend mode options
- **Visual Feedback:** Observe real-time preview as blend mode changes
- **Layer Identification:** Understand which layer is currently active/selected

### B. GIMP Knowledge
- **Layer System:** Understand that GIMP images can contain multiple stacked layers
- **Blend Mode Concept:** Know that blend modes control how layers interact mathematically
- **Layers Panel:** Navigate GIMP's Layers panel interface and controls
- **Mode Dropdown Location:** Know that blend mode selector is at top of Layers panel
- **Default State:** Understand that layers start in "Normal" mode by default
- **Visual Preview:** Recognize that changes apply immediately and non-destructively

### C. Task-Specific Skills
- **Multiply Effect Understanding:** Know that Multiply mode darkens by multiplying color values
- **Appropriate Use Cases:** Understand when Multiply mode is useful (darkening, shadows, overlays)
- **Visual Assessment:** Judge whether the blend mode has been successfully applied
- **Layer State Awareness:** Distinguish between layer properties (opacity, blend mode, visibility)

## Task Steps

### 1. Examine Initial State
- Observe the image that opens automatically in GIMP with two layers pre-loaded
- Note that there's a base photograph layer and a color overlay layer on top
- Identify that the overlay currently appears solid/opaque (Normal blend mode)

### 2. Locate Layers Panel
- Find the Layers panel (typically docked on the right side of GIMP interface)
- If not visible, navigate to `Windows → Dockable Dialogs → Layers`
- Confirm you can see both layers listed in the panel

### 3. Verify Active Layer
- Ensure the top layer (color overlay) is selected/active
- The active layer should be highlighted in the Layers panel
- If not active, click on it to select it

### 4. Locate Blend Mode Dropdown
- At the top of the Layers panel, find the dropdown menu labeled "Mode"
- This dropdown currently shows "Normal" as the active blend mode
- Position cursor over the dropdown to prepare for interaction

### 5. Open Blend Mode Menu
- Click on the Mode dropdown to reveal the list of available blend modes
- Observe the extensive list of options (Dissolve, Multiply, Divide, Screen, Overlay, etc.)
- Scroll if necessary to see all available modes

### 6. Select Multiply Mode
- Locate "Multiply" in the blend mode list (typically in the "Darken" group)
- Click on "Multiply" to apply it to the active layer
- The dropdown should now display "Multiply" instead of "Normal"

### 7. Observe the Effect
- Watch the image update to show the darkened, blended result
- The color overlay should now darken the underlying photograph
- Colors should appear richer and more saturated where layers overlap

### 8. Automatic Export
- The post-task hook will automatically export the result as "blended_multiply.png"
- The XCF file will also be saved to preserve layer information

## Verification Strategy

### Verification Approach
The verifier uses **dual-method validation** combining XCF layer analysis and visual comparison:

### A. XCF File Analysis (Primary Method)
- **Layer Structure Parsing:** Opens and parses the exported XCF file using Python XCF libraries
- **Blend Mode Reading:** Directly reads the blend mode property of each layer
- **Layer Count Verification:** Confirms that both layers still exist (not merged/flattened)
- **Mode String Matching:** Checks that top layer's mode is explicitly set to "MULTIPLY"
- **Technical Validation:** Most reliable method as it reads actual GIMP internal state

### B. Visual Reference Comparison (Secondary Method)
- **Reference Generation:** Creates a mathematically perfect reference using PIL/NumPy
- **Multiply Algorithm:** Applies pixel-wise multiplication: `result = (base * overlay) / 255`
- **SSIM Comparison:** Uses Structural Similarity Index to compare visual result with reference
- **High Threshold:** Requires SSIM ≥ 0.90 for visual match confirmation
- **Fallback Validation:** Used when XCF parsing fails or for additional confirmation

### C. Visual Darkening Analysis
- **Brightness Comparison:** Measures average brightness before/after blend mode application
- **Expected Darkening:** Multiply mode should reduce overall brightness significantly
- **Statistical Validation:** Checks that result is 15-40% darker than overlay-only image
- **Sanity Check:** Ensures the visual effect is consistent with Multiply behavior

### D. Layer Integrity Check
- **Layer Preservation:** Confirms that layers weren't merged or flattened
- **Non-destructive Workflow:** Validates that original layers remain intact
- **Proper Export:** Ensures XCF format was used to preserve layer information

### Verification Checklist
- ✅ **XCF Blend Mode Correct:** Top layer explicitly set to "MULTIPLY" mode in XCF file
- ✅ **Visual Match:** Result closely matches mathematical Multiply reference (SSIM ≥ 0.90)
- ✅ **Appropriate Darkening:** Image shows expected darkening effect (15-40% reduction)
- ✅ **Layers Preserved:** Both layers still exist as separate entities

### Scoring System
- **100%:** XCF confirms Multiply mode + visual match + proper darkening (all criteria met)
- **85-99%:** XCF confirms Multiply but minor visual discrepancies
- **75-84%:** Visual appearance correct but XCF validation unclear
- **50-74%:** Some darkening evident but incorrect blend mode or poor visual match
- **0-49%:** No blend mode change detected or incorrect mode applied

**Pass Threshold:** 75% (requires clear evidence of Multiply blend mode application)

## Technical Implementation

### Files Structure