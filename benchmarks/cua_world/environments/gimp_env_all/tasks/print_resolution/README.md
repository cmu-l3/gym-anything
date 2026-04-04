# GIMP Change Print Resolution Task (`print_resolution@1`)

## Overview

This task tests an agent's ability to modify an image's print resolution (DPI/PPI) without changing its pixel dimensions. The agent must navigate to GIMP's Print Size dialog, understand the distinction between pixel dimensions and print resolution, and set a new DPI value. This represents an essential skill for preparing images for print output and understanding a commonly confused concept in digital imaging.

## Rationale

**Why this task is valuable:**
- **Print Workflow Fundamentals:** Essential for preparing images for physical printing
- **Conceptual Clarity:** Tests understanding of DPI/PPI vs. pixel dimensions—one of the most commonly confused concepts in digital imaging
- **Metadata Management:** Introduces the concept that images carry metadata beyond pixel data
- **Professional Requirement:** Print shops, publishers, and designers regularly adjust DPI for output specifications
- **Non-destructive Operation:** Changes metadata without altering actual image pixels, unlike scaling
- **Real-world Relevance:** Critical for photo printing, publishing, signage, and professional graphics work

**Skill Progression:** This task bridges pixel-level editing with professional output preparation, introducing metadata concepts essential for production workflows while remaining simple to execute.

## Skills Required

### A. Interaction Skills
- **Menu Navigation:** Navigate to `Image → Print Size` through GIMP's menu hierarchy
- **Dialog Interaction:** Work with the Print Size dialog interface effectively
- **Unit Comprehension:** Distinguish between pixels, inches, and resolution units (DPI/PPI)
- **Input Field Manipulation:** Enter specific numeric resolution values accurately
- **Link Icon Understanding:** Recognize and work with constraint linking (chain icon)
- **Confirmation Actions:** Apply changes using OK button

### B. GIMP Knowledge
- **Resolution Concepts:** Understand DPI (dots per inch) and PPI (pixels per inch) terminology
- **Print Size vs. Scale Image:** Know the critical difference between these two operations
- **Dimension Independence:** Understand that pixel dimensions remain constant while DPI changes
- **Print Size Calculation:** Understand the relationship: physical size (inches) = pixels ÷ DPI
- **Metadata vs. Pixels:** Recognize that DPI is stored as metadata, not affecting pixel content
- **Default Values:** Know that digital images often default to 72 DPI (historical screen resolution standard)
- **Menu Location:** Distinguish Print Size from similar operations like Scale Image

### C. Task-Specific Skills
- **Print Preparation:** Understand why DPI matters for physical output quality
- **Standard Values:** Know common print resolutions:
  - 72 DPI = screen/web resolution
  - 150 DPI = draft printing
  - 300 DPI = high-quality print standard
  - 600+ DPI = professional/fine art printing
- **Size Relationships:** Understand inverse relationship (higher DPI = smaller physical print size for same pixel count)
- **Quality Planning:** Recognize appropriate DPI values for different output types

## Task Steps

### 1. Initial Image Examination
- Examine the landscape photograph that opens automatically in GIMP
- Note the pixel dimensions displayed in the title bar (e.g., 1920×1080 pixels)
- Understand that the goal is to change print resolution without altering pixel count

### 2. Access Print Size Dialog
- Navigate to `Image → Print Size` in the menu bar (not Scale Image!)
- Wait for the Print Size dialog to open
- Distinguish this from the Scale Image dialog, which would change pixel dimensions

### 3. Examine Current Settings
- Observe the current X and Y resolution values (likely 72.000 DPI by default)
- Note the width and height displayed in inches or centimeters
- Observe these physical dimensions are calculated from: pixels ÷ DPI
- Notice the chain link icon between X and Y resolution (keeps them synchronized)

### 4. Change Resolution Value
- Click in the X resolution or Y resolution field
- Clear the current value and type `300` (professional print standard)
- Press Tab or click outside the field
- Observe that both X and Y automatically change to 300 if chain-linked
- Note that width/height in inches **decrease** (same pixels ÷ higher DPI = smaller print)

### 5. Verify Settings
- Confirm both X resolution and Y resolution display **300.000**
- Verify units are set to "pixels/in" (DPI) or similar
- Ensure the pixel dimensions shown are unchanged from original
- Double-check you're in Print Size dialog, not Scale Image

### 6. Apply Changes
- Click the **"OK"** button to apply the new resolution metadata
- The dialog closes immediately (no processing delay—it's just metadata)
- The image canvas appears unchanged (because pixels weren't modified)

### 7. Automatic Export
- The post-task hook will automatically export the result as "landscape_300dpi.jpg"
- The DPI metadata will be embedded in the exported file

## Verification Strategy

### Verification Approach
The verifier uses **direct metadata inspection** combined with dimension validation:

### A. DPI Metadata Extraction
- **Format-Specific Reading:** Uses PIL's `image.info` dictionary to extract DPI/PPI metadata
- **Multi-format Support:** Correctly handles DPI storage in JPEG, PNG, TIFF formats
- **Unit Handling:** Interprets various DPI storage methods (pixels/inch, pixels/cm)
- **Precision Checking:** Validates DPI matches target value of 300 (±10 tolerance for format variations)
- **Coordinate Verification:** Confirms both X and Y DPI are set correctly

### B. Pixel Dimension Preservation
- **Exact Size Match:** Verifies pixel dimensions (width × height) remain **exactly** unchanged
- **No Scaling Detection:** Confirms the operation didn't accidentally resize the image
- **Aspect Ratio:** Double-checks aspect ratio preservation as additional safety measure
- **Pixel Integrity:** Ensures no pixel-level modifications occurred

### C. Change Validation
- **Metadata Modification Proof:** Confirms DPI metadata was actually altered from default
- **Reasonable Value Range:** Ensures new DPI falls within sensible bounds (100-600 DPI)
- **Non-default Check:** Verifies DPI is significantly different from typical default (72 DPI)
- **Symmetry Verification:** Confirms X and Y DPI are equal (standard practice)

### D. File Quality Assurance
- **File Validity:** Ensures exported file is properly formatted and openable
- **Metadata Persistence:** Validates DPI metadata was successfully written and is readable
- **No Corruption:** Confirms export process didn't introduce errors
- **Format Compliance:** Checks file adheres to format specifications

### Verification Checklist
- ✅ **Target DPI Achieved:** Resolution metadata is 300 DPI (±10 tolerance)
- ✅ **Dimensions Preserved:** Pixel dimensions exactly match original (0 pixel difference)
- ✅ **Metadata Readable:** DPI information properly embedded and extractable
- ✅ **Reasonable Value:** DPI within expected print range (100-600)
- ✅ **Image Unchanged:** No pixel-level modifications detected

### Scoring System
- **100%:** Perfect 300 DPI (±5) with exact dimension preservation
- **75-99%:** DPI within ±10 of target with exact dimensions, or ±5 of target with ±1% dimensions
- **50-74%:** DPI changed to reasonable print value (150-450) with dimensions mostly preserved
- **0-49%:** DPI unchanged, incorrect value, or dimensions significantly altered

**Pass Threshold:** 75% (requires close-to-target DPI with dimension preservation)

## Technical Implementation

### Files Structure