# GIMP Flood Fill Task (`flood_fill@1`)

## Overview

This task tests an agent's ability to use GIMP's Bucket Fill tool (flood fill) to change the color of a distinct region in an image. The agent must select the tool, choose an appropriate fill color, and apply it to a target area by clicking. This represents one of the most fundamental painting operations in digital image editing, testing both tool selection and color application skills.

## Rationale

**Why this task is valuable:**
- **Core Painting Operation**: Flood fill is one of the most basic and essential painting tools in digital art
- **Color Application Skills**: Tests ability to select and apply colors effectively in GIMP's interface  
- **Region Recognition**: Requires understanding of how flood fill operates on similar-colored areas
- **Precision Interaction**: Tests accurate clicking and visual target identification
- **Real-world Relevance**: Used extensively in digital art, coloring, photo editing, and graphic design
- **Tool Foundation**: Establishes understanding of GIMP's painting tools beyond brush-based operations

**Skill Progression**: This task introduces basic painting concepts that serve as foundation for more advanced artistic and photo editing workflows.

## Skills Required

### A. Interaction Skills
- **Tool Selection**: Navigate toolbox to locate and select Bucket Fill tool
- **Color Interface**: Use GIMP's color picker/chooser to select fill colors
- **Precision Clicking**: Click accurately on target regions to trigger flood fill operation
- **Visual Confirmation**: Recognize successful completion of fill operation
- **Tool Options**: Understand basic flood fill settings and behavior

### B. GIMP Knowledge  
- **Bucket Fill Tool**: Know location and function of flood fill tool in GIMP toolbox
- **Color System**: Navigate foreground color selection and color chooser dialogs
- **Fill Behavior**: Understand how flood fill works with color similarity and boundaries
- **Tool Cursor**: Recognize bucket fill cursor and its active state
- **Painting Tool Category**: Distinguish flood fill from other painting and selection tools

### C. Task-Specific Skills
- **Target Identification**: Visually identify distinct color regions suitable for filling
- **Color Selection**: Choose colors that provide good contrast and visual appeal
- **Boundary Recognition**: Understand how flood fill respects existing color boundaries
- **Fill Assessment**: Evaluate whether fill operation completed successfully and completely
- **Result Validation**: Confirm the intended region was filled without unwanted spillover

## Task Steps

### 1. Image Analysis
- Examine the geometric shapes image that opens automatically (contains distinct colored regions)
- Identify the target region for filling (e.g., a white circle among colored shapes)
- Note the current color and surrounding elements

### 2. Select Bucket Fill Tool
- Locate the Bucket Fill (flood fill) tool in GIMP's toolbox
- Click to select the tool (or use Shift+B shortcut)
- Observe cursor change to bucket icon indicating tool is active

### 3. Choose Fill Color
- Click on the foreground color square to open color chooser
- Select a bright, contrasting color (e.g., bright red or blue)
- Apply color selection and close color chooser dialog

### 4. Apply Flood Fill Operation
- Position cursor over the center of the target region (white shape)
- Click once to trigger the flood fill operation  
- Observe the region fill with the selected color instantly

### 5. Verify Fill Results
- Confirm the target region changed to the new color completely
- Check that the fill respected boundaries and didn't spill into adjacent regions
- Ensure the fill appears uniform and complete throughout the target area

### 6. Automatic Export
- The post-task hook will automatically export the result as "flood_filled_shape.png"

## Verification Strategy

### Verification Approach
The verifier uses **color distribution analysis and geometric validation** to confirm successful flood fill:

### A. Color Distribution Analysis
- **New Color Detection**: Identify significant presence of target fill color not present in original
- **Regional Color Mapping**: Analyze color changes in specific geometric regions of the image
- **Pixel Count Comparison**: Compare before/after pixel counts for target colors
- **Color Purity Assessment**: Verify filled regions have consistent, pure color application

### B. Geometric Fill Validation  
- **Shape Detection**: Identify filled geometric shapes using connected component analysis
- **Boundary Preservation**: Confirm original shape boundaries were respected during fill
- **Coverage Completeness**: Ensure target shapes are fully filled with minimal gaps (>85% coverage)
- **Isolation Verification**: Confirm fills are properly contained within intended shapes

### C. Fill Quality Assessment
- **Uniformity Check**: Verify filled areas have consistent color without patches or gaps
- **Edge Integrity**: Ensure clean edges were maintained at shape boundaries
- **No Spillover**: Confirm fill didn't leak into unintended adjacent regions
- **Appropriate Scale**: Validate that filled areas meet minimum size requirements for visibility

### D. Change Magnitude Verification
- **Significant Modification**: Ensure substantial color change occurred (>5% of image pixels)
- **Intentional Change**: Verify changes align with expected flood fill behavior patterns
- **Visual Impact**: Confirm the modification creates clearly visible results
- **Tool-Specific Results**: Validate changes are consistent with bucket fill tool operation

### Verification Checklist
- ✅ **Target Color Present**: Significant amount (>2% of pixels) of new fill color detected
- ✅ **Proper Fill Location**: Color change concentrated in expected geometric regions  
- ✅ **Complete Coverage**: Target areas show >85% coverage with fill color
- ✅ **Clean Boundaries**: Fill respects original shape boundaries without spillover

### Scoring System
- **100%**: Perfect flood fill with complete, clean coverage and precise boundaries
- **75-99%**: Excellent flood fill with minor gaps or edge imperfections
- **50-74%**: Good flood fill but with notable coverage issues or minor spillover
- **0-49%**: Poor or failed flood fill with inadequate coverage or major problems

**Pass Threshold**: 75% (requires successful flood fill with good coverage and boundary respect)

## Technical Implementation

### Files Structure
```
flood_fill/
├── task.json              # Task configuration (6 steps, 90s timeout)
├── setup_flood_task.sh    # Downloads geometric shapes image, launches GIMP
├── export_flood.sh        # Automates export as "flood_filled_shape"  
├── verifier.py           # Color distribution and geometric verification
└── README.md            # This documentation
```

### Verification Features
- **Multi-Criteria Analysis**: Combines color detection, geometric validation, and coverage assessment
- **Robust Color Detection**: Uses scientific color space analysis for accurate fill detection  
- **Shape-Aware Validation**: Employs connected component analysis for geometric fill verification
- **Boundary Respect Testing**: Validates that fills remain within intended shape boundaries
- **Quality Metrics**: Provides detailed scoring based on coverage completeness and edge quality

This task provides essential foundation skills for GIMP's painting tools, establishing concepts needed for more advanced artistic and photo editing workflows while remaining appropriately simple for learning progression.