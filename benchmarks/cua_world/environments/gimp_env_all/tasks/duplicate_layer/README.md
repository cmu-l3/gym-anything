# GIMP Duplicate Layer Task (`duplicate_layer@1`)

## Overview

This task tests an agent's ability to use GIMP's layer management system to duplicate the current layer. The agent must access the layer operations menu, create a copy of the active layer, and ensure the layer stack now contains two identical layers. This represents a fundamental layer workflow operation essential for non-destructive editing and compositing workflows.

## Rationale

**Why this task is valuable:**
- **Layer System Introduction:** Introduces GIMP's core layer management capabilities
- **Non-destructive Workflow:** Teaches foundation for safe editing practices (always keep an original)
- **Compositing Foundation:** Essential skill for advanced techniques like layer masking and blending
- **Real-world Essential:** Used in virtually every professional GIMP workflow
- **Simple but Fundamental:** Basic operation that's prerequisite for advanced layer techniques
- **Common Use Case:** Layer duplication is one of the most frequently used operations in image editing

**Skill Progression:** This task introduces layer concepts, preparing agents for more complex multi-layer workflows, layer modes, and compositing operations.

## Skills Required

### A. Interaction Skills
- **Layer Menu Navigation:** Navigate to layer operations through menu (`Layer → Duplicate Layer`)
- **Alternative Access:** Or use right-click context menu on the layer in Layers panel
- **Keyboard Shortcut:** Optionally use Shift+Ctrl+D shortcut
- **Layer Panel Awareness:** Understand and locate the Layers panel (dockable dialog)
- **Visual Confirmation:** Verify operation success by observing the Layers panel

### B. GIMP Knowledge
- **Layer Concept:** Understand that images in GIMP can have multiple stacked layers
- **Layer Stack:** Know that layers are arranged in a vertical stack (top to bottom rendering)
- **Active Layer:** Understand the concept of the currently selected/active layer
- **Layer Naming:** Recognize that duplicated layers get " copy" appended to their names
- **Layer Independence:** Know that duplicated layers are independent copies, not references
- **Layers Panel:** Understand how to read and interpret the Layers dockable dialog

### C. Task-Specific Skills
- **Layer Identification:** Recognize the original layer in the Layers panel
- **Stack Verification:** Confirm that the layer count increased by one
- **Name Recognition:** Identify the duplicated layer by its name (usually "Background copy" or similar)
- **Visual Inspection:** Verify that canvas appearance hasn't changed (duplicate is identical)

## Task Steps

### 1. Initial Image Examination
- Examine the image that opens automatically in GIMP (simple landscape or object photo)
- Open or locate the Layers panel (usually docked on the right side)
- Note that there is currently one layer (typically named "Background")

### 2. Access Layer Duplication
- Navigate to `Layer → Duplicate Layer` in the menu bar, OR
- Right-click on the layer in the Layers panel and select "Duplicate Layer", OR
- Use keyboard shortcut Shift+Ctrl+D

### 3. Observe Layer Creation
- Look at the Layers panel to see a new layer appear
- Note that the new layer has the same name as the original plus " copy" suffix
- Confirm that two layers are now visible in the layer stack

### 4. Verify Layer Properties
- Confirm the duplicated layer is positioned directly above the original
- Verify that the canvas/image appearance hasn't changed (layers are identical)
- Ensure the duplicated layer is now the active layer (highlighted in Layers panel)

### 5. Optional Visibility Toggle (for verification)
- Toggle the visibility of the top layer (eye icon) to confirm it's a complete duplicate
- The image should look identical whether top layer is visible or hidden

### 6. Automatic Export and Verification
- The post-task hook will automatically save the XCF file preserving layers
- The verifier will analyze the XCF file to confirm layer duplication

## Verification Strategy

### Verification Approach
The verifier uses **XCF file structure analysis** to detect and validate layer duplication:

### A. XCF File Analysis
- **Format Validation:** Confirms the result is saved in XCF format (GIMP's native format that preserves layers)
- **Structure Parsing:** Analyzes XCF file headers and layer offset information
- **Layer Count Detection:** Attempts to count the number of layers in the file structure
- **File Integrity:** Validates the XCF file is properly formatted and readable

### B. Layer Stack Validation
- **Multiple Layer Evidence:** Confirms presence of multiple layers through file analysis
- **Size Consistency:** Verifies file size is appropriate for containing duplicated layer data
- **Format Preservation:** Ensures layers were saved in proper XCF format rather than flattened

### C. Heuristic Analysis
- **File Size Assessment:** Uses file size patterns to detect layer multiplication
- **Structure Validation:** Confirms XCF file contains valid layer structure data
- **Format Verification:** Ensures proper use of XCF format for layer preservation

### D. Multi-Criteria Evaluation
- **Combined Analysis:** Uses multiple verification methods for robust detection
- **Fallback Methods:** Includes backup verification when direct parsing isn't possible
- **Quality Assurance:** Comprehensive evaluation of layer duplication success

### Verification Checklist
- ✅ **Valid XCF Format:** Result saved in proper XCF format preserving layers
- ✅ **Multiple Layers Detected:** Evidence of 2+ layers in file structure
- ✅ **Appropriate File Size:** File size consistent with layer duplication
- ✅ **Structure Integrity:** XCF file properly formatted and contains layer data

### Scoring System
- **100%:** Perfect layer duplication with clear evidence of 2 identical layers
- **75-99%:** Good layer duplication with minor structural issues
- **50-74%:** Partial success with some evidence of layer operations
- **0-49%:** Failed to properly duplicate layer or preserve layer structure

**Pass Threshold:** 75% (requires clear evidence of successful layer duplication)

## Technical Implementation

### Files Structure