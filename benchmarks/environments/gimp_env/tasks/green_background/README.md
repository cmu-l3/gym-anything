# GIMP Green Background Fill Task (`green_background@1`)

## Overview

This advanced task challenges an agent to work with GIMP's native XCF file format and layer system to fill a background layer with green color while preserving foreground objects. The agent must understand layer isolation, color filling techniques, and complex file format handling, representing sophisticated layer-based editing workflows used in professional digital art and photo compositing.

## Rationale

**Why this task is valuable:**
- **Advanced File Format Handling:** Introduces GIMP's native XCF format with preserved layer information
- **Layer System Mastery:** Tests understanding of layer isolation and selective editing
- **Precision Filling:** Requires careful application of fill tools without affecting other elements
- **Non-destructive Workflow:** Teaches proper layer-based editing that preserves original elements
- **Professional Technique:** Represents real-world compositing and background replacement workflows
- **Complex Decision Making:** Requires understanding which areas to fill and which to preserve

**Skill Progression:** This task represents the most advanced level in the suite, combining multiple complex concepts and requiring mastery of previous skills.

## Skills Required

### A. Interaction Skills
- **XCF File Recognition:** Understand and work with GIMP's native project format
- **Layer Panel Navigation:** Use the Layers panel to identify and select specific layers
- **Fill Tool Operation:** Apply fill tools precisely to selected areas or layers
- **Color Selection:** Choose appropriate green color for background filling
- **Precision Clicking:** Target specific areas while avoiding unintended regions
- **Layer Isolation:** Work on background layer without affecting foreground objects

### B. GIMP Knowledge
- **XCF Format Understanding:** Know how XCF preserves layers, transparency, and project structure
- **Layer System Concepts:** Understand layer hierarchy, selection, and isolation
- **Fill Tool Varieties:** Know different fill tools (Bucket Fill, Foreground Fill, etc.)
- **Layer Blending:** Understand how layers interact and preserve transparency
- **Background vs. Foreground:** Distinguish between different layer types and purposes
- **Non-destructive Editing:** Apply changes that don't permanently alter original elements

### C. Task-Specific Skills
- **Layer Identification:** Visually identify which layer contains the background to be filled
- **Object Preservation:** Ensure foreground objects remain unchanged during background modification
- **Color Theory Application:** Choose appropriate green color that complements the composition
- **Edge Awareness:** Maintain clean edges between background and foreground elements
- **Quality Assessment:** Evaluate whether the fill looks natural and professionally applied

## Task Steps

### 1. XCF Project Analysis
- Examine the XCF project that opens automatically in GIMP
- Identify the layer structure in the Layers panel
- Locate the background layer that needs to be filled with green
- Note the foreground object that must be preserved

### 2. Layer Selection
- Navigate to the Layers panel (usually on the right side of the interface)
- Click on the background layer to select it
- Ensure the correct layer is active (highlighted in the layers panel)

### 3. Background Area Identification
- Examine the white background areas that need to be changed to green
- Identify areas that should NOT be filled (foreground object)
- Plan the filling approach to avoid affecting the preserved elements

### 4. Fill Tool Selection
- Select the Bucket Fill tool from the toolbox or press Shift+B
- Alternatively, use other appropriate fill tools based on the layer structure

### 5. Color Configuration
- Set the foreground color to green (using color picker or direct RGB input)
- Choose an appropriate shade of green that complements the image
- Ensure the color will provide good contrast with the foreground object

### 6. Background Filling
- Click on the white background areas to fill them with green
- Apply the fill carefully to avoid affecting the foreground object
- Continue filling until all intended background areas are green

### 7. Quality Verification
- Review the result to ensure clean edges around the preserved object
- Verify that the green background looks natural and well-integrated
- Check that no unintended areas were filled

### 8. Automatic Export
- The post-task hook will automatically export the result as "green_background_with_object.png"

## Verification Strategy

### Verification Approach
The verifier uses **advanced color analysis** and **object preservation verification**:

### A. Green Background Detection
- **Color Space Analysis:** Analyzes RGB values to detect presence of green color in background areas
- **Green Threshold Validation:** Uses scientifically-defined green color ranges for accurate detection
- **Coverage Assessment:** Measures percentage of background area that has been successfully filled
- **Color Consistency:** Ensures green color is applied uniformly across background regions

### B. Object Preservation Analysis
- **Foreground Protection:** Compares foreground object areas between original and result
- **Pixel-level Comparison:** Uses mathematical comparison to detect unintended changes
- **Edge Integrity:** Verifies that object boundaries remain clean and unaltered
- **Detail Preservation:** Ensures fine details of the foreground object are maintained

### C. Professional Quality Assessment
- **Clean Edges:** Analyzes edge quality between green background and preserved objects
- **Color Harmony:** Evaluates whether the green color choice complements the overall composition
- **Fill Completeness:** Ensures all intended background areas have been filled
- **Artifact Detection:** Checks for filling artifacts or incomplete coverage

### D. Layer-based Verification
- **Selective Modification:** Confirms that only the intended layer/areas were modified
- **Structure Preservation:** Ensures the overall composition structure is maintained
- **Transparency Handling:** Verifies proper handling of transparency and layer blending
- **Format Integrity:** Confirms proper export from XCF to final format

### Verification Checklist
- ✅ **Green Background Present:** Significant green color detected in background areas (≥60% coverage)
- ✅ **Object Preserved:** Foreground object remains unchanged (≥95% pixel similarity)
- ✅ **Clean Edges:** Sharp, clean boundaries between green background and preserved elements
- ✅ **Image Modified:** Clear evidence of intentional background color change

### Scoring System
- **100%:** Perfect green background fill with complete object preservation and clean edges
- **75-99%:** Good background fill with minor imperfections in coverage or edges
- **50-74%:** Adequate green background but with notable quality issues or incomplete coverage
- **0-49%:** Inadequate background change or significant damage to foreground object

**Pass Threshold:** 75% (requires good green background with preserved object)

### Color Analysis Details
```python
# Green Detection Algorithm
def detect_green_in_background(image, threshold=0.6):
    rgb_array = np.array(image.convert('RGB'))
    
    # Define green color range (G > R and G > B, with sufficient intensity)
    green_mask = (rgb_array[:,:,1] > rgb_array[:,:,0]) & \
                 (rgb_array[:,:,1] > rgb_array[:,:,2]) & \
                 (rgb_array[:,:,1] > 100)  # Minimum green intensity
    
    green_percentage = np.sum(green_mask) / (rgb_array.shape[0] * rgb_array.shape[1])
    return green_percentage >= threshold

# Object Preservation Check
def check_object_preservation(original_img, result_img, threshold=0.95):
    # Compare foreground object areas for changes
    orig_array = np.array(original_img)
    result_array = np.array(result_img.convert(original_img.mode))
    
    # Calculate pixel-wise similarity in object regions
    similarity = 1 - np.mean(np.abs(orig_array - result_array) / 255.0)
    return similarity >= threshold
```

## Technical Implementation

### Files Structure
```
green_background/
├── task.json               # Task configuration (10 steps, 120s timeout)
├── setup_green_task.sh     # Downloads XCF project and reference PNG
├── export_green.sh         # Automates export as "green_background_with_object"
├── verifier.py            # Advanced color analysis and object preservation verification
└── README.md             # This documentation
```

### Advanced Features
- **XCF Format Support:** Handles GIMP's native project format with layer preservation
- **Dual Asset Management:** Downloads both XCF project and reference PNG for comparison
- **Sophisticated Color Analysis:** Uses advanced algorithms for green detection and object preservation
- **Professional Quality Metrics:** Evaluates results against industry-standard quality criteria
- **Layer-aware Verification:** Understands and validates layer-based editing workflows

### Verification Innovations
- **Object Region Detection:** Automatically identifies and protects foreground object areas
- **Color Space Validation:** Uses HSV and RGB analysis for robust green detection
- **Edge Quality Assessment:** Analyzes boundary sharpness and fill quality
- **Workflow Validation:** Ensures proper layer-based editing approach was used

This task represents the pinnacle of the GIMP training suite, requiring mastery of advanced layer concepts, file format handling, and precision editing techniques essential for professional digital art workflows.
