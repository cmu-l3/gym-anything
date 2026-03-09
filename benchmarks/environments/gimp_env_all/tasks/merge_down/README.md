# GIMP Merge Down Layers Task (`merge_down@1`)

## Overview

This task tests an agent's ability to use GIMP's layer merging functionality to combine specific layers in a multi-layer composition. The agent must identify the correct layer, navigate to the merge operation, and execute a "merge down" command that combines a layer with the one immediately below it. This represents a fundamental layer management operation distinct from flattening an entire image.

## Rationale

**Why this task is valuable:**
- **Layer Management Fundamentals:** Introduces selective layer merging as opposed to global flattening
- **Composition Control:** Tests understanding of layer hierarchy and how layers combine
- **Workflow Efficiency:** Common operation when consolidating parts of a composition while maintaining other layers
- **Non-destructive to Destructive Transition:** Teaches when and how to commit layer edits
- **Real-world Relevance:** Essential in photo editing, graphic design, and digital art workflows
- **Hierarchy Understanding:** Reinforces concepts of layer stacking and order

**Skill Progression:** This task bridges basic layer awareness with advanced layer management, sitting between creating layers and full image flattening.

## Skills Required

### A. Interaction Skills
- **Layer Panel Navigation:** Identify and interact with the Layers panel/dockable dialog
- **Layer Selection:** Click on the correct layer to make it active
- **Context Menu Usage:** Right-click on layer to access layer-specific commands
- **Menu Navigation:** Navigate to `Layer → Merge Down` or use context menu equivalent
- **Visual Confirmation:** Observe layer panel changes after merge operation

### B. GIMP Knowledge
- **Layer Panel Understanding:** Know where to find and interact with the Layers dockable
- **Layer Hierarchy:** Understand that layers have a stacking order (top to bottom)
- **Merge vs. Flatten:** Distinguish between merging specific layers and flattening all layers
- **Merge Down Behavior:** Know that "merge down" combines the active layer with the one directly below it
- **Layer Naming:** Understand that the merged layer typically takes the name of the lower layer
- **Active Layer Concept:** Know that operations apply to the currently selected/active layer

### C. Task-Specific Skills
- **Layer Identification:** Visually identify which layer to select for merging
- **Stack Position Awareness:** Understand which layer is "below" the current one
- **Result Prediction:** Anticipate what the merged result will look like
- **Layer Count Tracking:** Recognize that merge reduces total layer count by one
- **Composition Preservation:** Understand that visual appearance should remain the same after merge

## Task Steps

### 1. Image and Layer Examination
- Examine the multi-layer composition that opens automatically in GIMP
- Open the Layers panel if not already visible (Windows → Dockable Dialogs → Layers)
- Observe that there are multiple layers (typically 2-3 layers)
- Note the stacking order and names of layers

### 2. Identify Target Layer
- Identify the top or middle layer that should be merged down
- Note which layer is directly below it (the merge target)
- Understand that both layers will combine into one

### 3. Select the Source Layer
- Click on the layer that will be merged down (typically the upper layer)
- Ensure this layer becomes the active/selected layer (highlighted in the layers panel)
- Verify selection by observing the layer highlight in the layers panel

### 4. Access Merge Down Command
- Navigate to `Layer → Merge Down` in the menu bar, OR
- Right-click on the active layer and select "Merge Down" from context menu
- Note that this option is only available when there is a layer below the current one

### 5. Execute Merge
- Click on "Merge Down" to execute the operation
- Observe that the two layers immediately combine
- Note that the layer panel now shows one fewer layer

### 6. Verify Merge Result
- Check that the layer count has decreased by one
- Verify that the visual appearance of the image remains the same
- Confirm that the merged layer contains the combined content

### 7. Automatic Export
- The post-task hook will automatically export the result and save the XCF file for verification

## Verification Strategy

### Verification Approach
The verifier uses **multi-method layer analysis** combining visual comparison with structural layer counting:

### A. Layer Count Verification
- **XCF File Analysis:** Opens the resulting XCF file and counts layers using PIL/Python
- **Count Reduction:** Verifies that layer count decreased by exactly 1 from original
- **Structural Validation:** Confirms the XCF file structure is valid and properly saved
- **Expected Count:** Validates final layer count matches expected number (original - 1)

### B. Visual Preservation Analysis
- **Flattened Comparison:** Compares flattened version of original with flattened version of result
- **SSIM Similarity:** Uses Structural Similarity Index (SSIM ≥ 0.98) to verify visual equivalence
- **Pixel-wise Validation:** Ensures the merge operation didn't alter the visible composition
- **High Precision Threshold:** Requires very high similarity since merge shouldn't change appearance

### C. Merge Behavior Validation
- **Layer Structure:** Confirms that layers were properly combined, not just hidden
- **Proper Export:** Verifies XCF file was saved (not just PNG/JPEG export)
- **Merge Method:** Ensures merge operation was used rather than deletion or other operations
- **Stack Integrity:** Validates that remaining layers maintain their original order

### D. Composition Quality Check
- **No Artifacts:** Ensures merge didn't introduce visual artifacts or degradation
- **Color Preservation:** Verifies color values remained accurate through the merge
- **Transparency Handling:** Confirms alpha channels were properly combined
- **Detail Retention:** Validates that all image details were preserved

### Verification Checklist
- ✅ **Layer Count Reduced:** XCF file has exactly 1 fewer layer than original
- ✅ **Visual Equivalence:** Flattened result SSIM ≥ 0.98 compared to flattened original
- ✅ **XCF Saved:** Valid XCF file exists with proper layer structure
- ✅ **Composition Preserved:** No visual changes to the final rendered image

### Scoring System
- **100%:** Perfect merge - layer count reduced by 1, visual appearance identical (SSIM ≥ 0.98)
- **75-99%:** Good merge - correct layer count but minor visual discrepancies (SSIM 0.95-0.98)
- **50-74%:** Partial success - layer reduction occurred but visual differences detected
- **0-49%:** Failed merge - incorrect layer count or significant visual changes

**Pass Threshold:** 75% (requires both correct layer count reduction and high visual fidelity)

## Technical Implementation

### Files Structure