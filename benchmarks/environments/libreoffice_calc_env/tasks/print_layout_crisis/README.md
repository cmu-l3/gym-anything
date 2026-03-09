# Print Layout Crisis Manager Task

**Difficulty**: 🟡 Medium  
**Skills**: Page setup, print configuration, layout optimization, spatial reasoning  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Fix a spreadsheet that looks fine on screen but is a printing disaster. The inventory spreadsheet has columns spanning 3-4 pages horizontally, with no scaling or optimization applied. Configure page layout settings to produce a clean, readable printed document that fits on a reasonable number of pages.

## Task Description

**Scenario**: You're a small business owner who needs to print an inventory report for an accountant meeting tomorrow morning. When you check print preview, you discover the spreadsheet will print across multiple pages horizontally with critical information cut off. You must fix the print layout urgently.

The agent must:
1. Assess the current print layout crisis (via Print Preview)
2. Change page orientation to landscape for wider data
3. Optimize column widths (narrow non-critical columns)
4. Configure scaling to fit content appropriately (70-95% or fit-to-pages)
5. Adjust margins to maximize usable space
6. Verify the layout in Print Preview
7. Save the file with optimized print configuration

## Starting State

- LibreOffice Calc opens with `inventory_to_print.ods`
- Spreadsheet contains business inventory data (50+ rows)
- Multiple wide columns (SKU, Product Name, Category, Description, Price, Stock, Supplier, Notes, etc.)
- Default settings: Portrait orientation, no scaling, 1" margins
- **Problem**: Print preview shows content spanning 3-4 pages horizontally

## Expected Results

- **Orientation**: Landscape (not portrait)
- **Scaling**: 70-95% or configured to fit 1-2 pages wide
- **Column widths**: No excessively wide columns (>5 inches)
- **Margins**: Reasonable margins between 0.5-1.0 inches
- **Horizontal pages**: Content fits on ≤2 pages wide

## Verification Criteria

1. ✅ **Landscape Orientation**: Page configured for landscape printing (20 pts)
2. ✅ **Appropriate Scaling**: Scaling factor 70-95% or fit-to-pages configured (25 pts)
3. ✅ **Optimized Columns**: No excessively wide columns remaining (20 pts)
4. ✅ **Reasonable Margins**: Margins set between 0.5" - 1.0" (15 pts)
5. ✅ **Horizontal Fit**: Content estimated to fit on ≤2 pages wide (20 pts)

**Pass Threshold**: 75% (requires at least 4 out of 5 criteria with good quality)

## Skills Tested

- Page setup navigation (`Format → Page`)
- Print preview usage (`File → Print Preview`)
- Column width adjustment
- Scaling configuration (fit-to-pages or percentage)
- Margin adjustment
- Spatial reasoning (understanding page dimensions)
- Layout optimization under constraints

## Navigation Paths

### Access Page Setup
- **Primary**: `Format → Page`
- **Alternative**: Right-click sheet tab → Page Setup

### Key Settings Locations
- **Orientation**: `Format → Page → Page tab → Orientation`
- **Scaling**: `Format → Page → Sheet tab → Scale`
- **Margins**: `Format → Page → Page tab → Margins`

### Print Preview
- **Menu**: `File → Print Preview`
- **Shortcut**: `Ctrl+Shift+P`

## Tips

- **Landscape is essential** for wide tabular data
- **Start with scaling around 85%** and adjust from there
- **Narrow "Notes" or "Description"** columns first (often excessively wide)
- **Keep critical columns readable**: SKU, Product Name, Price, Stock should remain clear
- **Use Print Preview iteratively** to check your changes
- **Fit-to-pages width** is powerful: set to "1-2 pages wide" with automatic height
- **Reduce margins slightly** (0.75" instead of 1") for more usable space
- **Double-click column borders** to auto-fit content

## Common Pitfalls

- ❌ Keeping portrait orientation (won't fit wide data)
- ❌ Over-scaling (text becomes microscopic and unreadable)
- ❌ Under-scaling (still spans too many pages)
- ❌ Not adjusting column widths (letting one column waste space)
- ❌ Forgetting to save the configuration
- ❌ Not checking Print Preview before finishing

## Real-World Context

This task simulates the universal frustration of the "screen vs. print" mismatch. Nearly every spreadsheet user has experienced:
- Preparing for a meeting and discovering print layout disaster
- Wasting paper on test prints that look terrible
- Frantically adjusting settings minutes before a presentation
- Losing critical data because columns are cut off across pages

Mastering print layout is essential for:
- Professional reports and documentation
- Financial statements for accountants
- Inventory reports for audits
- Board meeting materials
- Client presentations requiring physical copies