# GIMP Export Format Conversion Task (`export_jpeg@1`)

## Overview

This task tests an agent's ability to use GIMP's export system to convert an image from PNG format to JPEG format with appropriate quality settings. The agent must navigate the export dialog, select JPEG format, configure compression quality, and ensure the resulting file is properly formatted and optimized. This represents essential file management skills required for preparing images for different use cases (web, print, storage).

## Rationale

**Why this task is valuable:**
- **Export System Mastery:** Introduces GIMP's export workflow, which differs from the legacy "Save" system
- **Format Understanding:** Tests comprehension of image format differences (PNG vs JPEG, lossless vs lossy)
- **Quality Tradeoffs:** Requires understanding balance between file size and image quality
- **Real-world Workflow:** Format conversion is extremely common in web design, photography, and content creation
- **File Management Skills:** Teaches proper file handling and format selection for different purposes
- **Practical Application:** Represents daily tasks in professional image editing environments

**Skill Progression:** This task bridges tool-based editing operations with file management and format understanding, preparing agents for complete image processing workflows.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate to `File → Export As` (or `File → Export`)
- **File Dialog Interaction:** Work with file save dialogs and path selection
- **Format Selection:** Choose file format from dropdown or by filename extension
- **Parameter Configuration:** Adjust JPEG quality slider in export options dialog
- **Dialog Confirmation:** Apply export settings using "Export" button
- **Multi-stage Workflow:** Handle initial export dialog followed by format-specific options dialog

### B. GIMP Knowledge
- **Export vs Save Distinction:** Understand GIMP's separation of native (.xcf) saves from exports
- **Format Capabilities:** Know differences between PNG (lossless, transparency) and JPEG (lossy, no transparency)
- **Export Dialog System:** Navigate GIMP's two-stage export process (file selection + format options)
- **Quality Settings:** Understand JPEG quality scale (0-100) and its impact on file size/quality
- **Format Detection:** Know that GIMP detects format from file extension (.jpg, .jpeg)
- **Option Defaults:** Recognize when to accept defaults vs when to adjust parameters

### C. Task-Specific Skills
- **Format Appropriateness:** Understand when JPEG is preferable to PNG (photographs, no transparency needed)
- **Quality Assessment:** Choose appropriate quality levels for different use cases (web: 80-90, archive: 90-100)
- **File Size Awareness:** Recognize that JPEG compression significantly reduces file size
- **Quality vs Size Balance:** Make informed decisions about compression tradeoffs
- **Extension Management:** Correctly specify file extensions to trigger format selection

## Task Steps

### 1. Initial Image Examination
- Examine the PNG photograph that opens automatically in GIMP
- Note that it's currently in PNG format (check title bar or file info)
- Understand that the goal is to create a JPEG version suitable for web use

### 2. Initiate Export Process
- Navigate to `File → Export As` (or `File → Export` in some GIMP versions)
- Wait for the export file selection dialog to open
- Observe the current filename and default export location

### 3. Specify JPEG Filename
- In the filename field, type a new name ending with `.jpg` or `.jpeg` (e.g., "exported_photo.jpg")
- Ensure the file extension is clearly `.jpg` to trigger JPEG format selection
- Verify that GIMP recognizes the format (may show "JPEG image" in format field)

### 4. Confirm File Selection
- Click "Export" button in the file selection dialog
- Wait for the JPEG export options dialog to appear
- Prepare to configure JPEG-specific parameters

### 5. Configure JPEG Quality
- In the JPEG export options dialog, locate the Quality slider
- Set quality to 85 (good balance for web use - high quality, reasonable file size)
- Optionally review other settings (subsampling, progressive, etc.) but defaults are usually appropriate
- Observe the estimated file size if shown

### 6. Complete Export
- Click "Export" button in the JPEG options dialog
- Wait for export to complete (usually instantaneous for typical images)
- Confirm that no error messages appear

### 7. Verification
- The verifier will check that the exported JPEG file exists and meets requirements

## Verification Strategy

### Verification Approach
The verifier uses **multi-faceted format and quality analysis** to validate proper export:

### A. File Format Validation
- **Format Detection:** Uses PIL/Pillow to definitively determine file format
- **JPEG Confirmation:** Verifies the file is genuinely JPEG, not mislabeled
- **File Extension Check:** Ensures filename ends with .jpg or .jpeg
- **Format Integrity:** Confirms the file is valid and can be opened/read

### B. Quality Assessment
- **Quality Estimation:** Analyzes JPEG compression quality level through multiple methods:
  - **File Size Ratio:** Compares exported JPEG size to original PNG size
  - **Compression Artifacts:** Measures presence of JPEG block artifacts
  - **Quality Metadata:** Attempts to extract quality setting from JPEG metadata if available
- **Appropriate Range:** Validates quality appears to be in reasonable range (70-95)
- **Not Over-compressed:** Ensures image isn't excessively degraded (quality too low)
- **Not Under-compressed:** Verifies meaningful compression occurred (not quality 100)

### C. Content Preservation
- **Visual Similarity:** Uses SSIM (Structural Similarity Index) to compare original PNG with exported JPEG
- **High Fidelity Threshold:** Requires SSIM ≥ 0.90 to ensure content preservation
- **Dimension Preservation:** Confirms image dimensions remain unchanged
- **Color Preservation:** Verifies colors weren't significantly altered during export

### D. Compression Effectiveness
- **File Size Reduction:** Validates that JPEG is significantly smaller than PNG (typically 40-80% reduction)
- **Efficiency Check:** Ensures compression achieved meaningful space savings
- **Reasonable Ratio:** File size should be 20-60% of original PNG (depends on image content)

### Verification Checklist
- ✅ **Correct Format:** File is genuinely JPEG format (not PNG or other)
- ✅ **Quality Appropriate:** JPEG quality estimated between 70-95 range
- ✅ **Content Preserved:** SSIM ≥ 0.90 with original PNG (excellent similarity)
- ✅ **Compressed Effectively:** File size is 20-60% of original PNG

### Scoring System
- **100%:** All 4 criteria met (perfect JPEG export with appropriate settings)
- **75-99%:** 3/4 criteria met (good export with minor issues in quality or compression)
- **50-74%:** 2/4 criteria met (format correct but quality or compression suboptimal)
- **0-49%:** <2 criteria met (wrong format or serious quality issues)

**Pass Threshold:** 75% (requires at least 3 out of 4 criteria)

## Technical Implementation

### Files Structure