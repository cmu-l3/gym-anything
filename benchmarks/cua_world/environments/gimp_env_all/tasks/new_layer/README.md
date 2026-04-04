# GIMP New Layer Creation Task (`new_layer@1`)

## Overview

This task tests an agent's ability to use GIMP's layer system to create a new layer with specific properties. The agent must navigate to the layer creation dialog, configure the new layer's properties (fill type and name), and apply the changes. This represents fundamental layer management skills that are essential for non-destructive editing and complex composition workflows in digital image editing.

## Rationale

**Why this task is valuable:**
- **Layer System Foundation:** Introduces GIMP's powerful layer-based editing architecture
- **Non-destructive Workflow:** Teaches the concept of adding content without modifying original image
- **Dialog Management:** Tests ability to navigate and configure multi-parameter dialogs
- **Professional Practice:** Layers are fundamental to all professional image editing workflows
- **Composition Building:** Establishes concepts needed for complex multi-layer compositions
- **Real-world Essential:** Creating new layers is one of the most common operations in digital design

**Skill Progression:** This task bridges basic single-layer operations with advanced multi-layer composition techniques, making it ideal for intermediate-level agent training.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Access `Layer → New Layer` through multi-level menu system
- **Dialog Interaction:** Work with the New Layer dialog and its various options
- **Text Input:** Enter a custom layer name in the text field
- **Dropdown Selection:** Choose fill type from dropdown menu options
- **Confirmation Actions:** Apply changes using OK button
- **Layer Panel Awareness:** Understand how new layers appear in the layers panel

### B. GIMP Knowledge
- **Layer Concepts:** Understand what layers are and how they stack in GIMP
- **Layer Panel System:** Know where to find layer-related operations in menus
- **Fill Type Options:** Understand different fill types (White, Foreground, Background, Transparent, Pattern)
- **Layer Naming:** Know that layers can be named for organization
- **Layer Stacking:** Understand that new layers typically appear above the current layer
- **Layer Visibility:** Know that new layers are visible by default and can obscure content below

### C. Task-Specific Skills
- **Property Configuration:** Ability to set multiple parameters in a dialog simultaneously
- **Layer Organization:** Understanding the importance of naming layers for workflow management
- **Fill Type Selection:** Choosing appropriate fill type based on intended use
- **Layer Structure Planning:** Recognizing how adding layers affects the image composition
- **Workflow Efficiency:** Using layers as the foundation for complex editing operations

## Task Steps

### 1. Initial Image Examination
- Examine the landscape image that opens automatically in GIMP
- Note the current appearance and single-layer structure
- Prepare to add a new layer that will affect the composition

### 2. Access New Layer Dialog
- Navigate to `Layer → New Layer` in the menu bar
- Wait for the New Layer dialog to open
- Observe the various configuration options available

### 3. Configure Layer Name
- In the "Layer name" field, enter "Overlay Layer"
- This provides semantic meaning and aids organization in complex projects

### 4. Select Fill Type
- In the "Fill with" dropdown menu, select "White"
- This will create a layer with solid white fill
- Understand that this will obscure the original image when placed on top

### 5. Configure Additional Properties (Optional)
- Leave other settings (width, height, layer mode) at default values
- These default to match the image size and Normal blend mode

### 6. Apply Layer Creation
- Click "OK" button to create the new layer
- Observe that the new layer appears in the Layers panel
- Note that the canvas now shows white (the new layer obscuring the original)

### 7. Verify Layer Creation
- Check the Layers panel to confirm "Overlay Layer" exists
- Observe the layer stack showing two layers now
- Confirm the new layer is active (highlighted in the panel)

### 8. Automatic Export
- The post-task hook will automatically export the result
- The verification system will analyze the layer structure

## Verification Strategy

### Verification Approach
The verifier uses **multi-method layer detection** combining visual analysis and file structure examination:

### A. Visual Verification (Primary Method)
- **Predominant Color Analysis:** Since a white-filled layer is created on top, the result should be predominantly white
- **Color Distribution:** Measures what percentage of the output image is white or near-white
- **Threshold Analysis:** Checks if ≥85% of pixels are white (RGB values all ≥240)
- **Comparison with Original:** Confirms the output differs dramatically from the original landscape

### B. File Structure Verification (Secondary Method)
- **File Size Analysis:** New layer increases file size; checks if exported file is larger
- **XCF Format Check:** If XCF export is available, directly verifies layer count
- **Layer Count Validation:** Confirms at least 2 layers exist (original + new)
- **Layer Name Detection:** Attempts to verify "Overlay Layer" name exists

### C. Change Detection
- **Significant Modification:** Ensures the image changed substantially from original
- **Pixel Difference Analysis:** Calculates pixel-wise differences between original and result
- **Coverage Assessment:** Verifies that changes affect majority of the image area

### D. Quality Validation
- **Clean Fill:** Ensures white fill is uniform without artifacts or inconsistencies
- **Complete Coverage:** Verifies the new layer covers the entire canvas area
- **Proper Export:** Confirms the file was successfully saved and is readable

### Verification Checklist
- ✅ **Predominantly White:** ≥85% of output image pixels are white (RGB ≥240)
- ✅ **Significant Change:** Output differs substantially from original landscape
- ✅ **Clean Fill:** White fill is uniform without major artifacts
- ✅ **File Modified:** Clear evidence of layer addition and successful export

### Scoring System
- **100%:** Perfect layer creation with clean white fill covering the image
- **75-99%:** Good layer creation with minor inconsistencies in fill or coverage
- **50-74%:** Layer appears to be created but with significant quality issues
- **0-49%:** Failed to create layer or incorrect configuration

**Pass Threshold:** 75% (requires successful white layer creation with good coverage)

### Verification Logic Details