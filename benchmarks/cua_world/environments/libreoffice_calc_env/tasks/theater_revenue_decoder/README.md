# LibreOffice Calc Legacy Spreadsheet Documentation Task (`theater_revenue_decoder@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Formula auditing, documentation, reverse engineering, error detection  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~30

## Objective

Reverse-engineer and document an inherited, undocumented theater ticket revenue spreadsheet. The spreadsheet has cryptic abbreviations, broken formulas, and no documentation. Your goal is to decode the logic, fix errors, add clear labels, document formulas, and create a comprehensive Documentation sheet.

## Task Description

You inherit a spreadsheet from a departed theater treasurer that calculates ticket revenue for an annual fundraiser gala. The spreadsheet works (mostly) but is completely undocumented:
- Cryptic abbreviations (SR, GEN, STD, COMP)
- Complex formulas with no explanations
- Broken #REF! errors from deleted cells
- Hardcoded assumptions with no labels
- No comments or documentation

Your mission: Make this spreadsheet understandable for the next person.

## Required Actions

1. **Decode Abbreviations**: Identify what SR, GEN, STD, COMP mean
2. **Add Labels**: Replace or supplement cryptic headers with descriptive text
3. **Audit Formulas**: Inspect major calculation cells to understand logic
4. **Fix Errors**: Repair or document #REF! errors
5. **Add Comments**: Right-click → Insert Comment on 6+ key formula cells
6. **Create Documentation Sheet**: Add new sheet with:
   - Purpose statement
   - Input cells list
   - Formula explanations in plain language
   - Assumptions (hardcoded values)
   - Known issues
   - Usage instructions
7. **Save**: Save as theater_revenue_documented.ods

## Expected Results

### Documentation Sheet Must Include:
- **Purpose**: What this spreadsheet calculates
- **Inputs**: Which cells users should modify
- **Formulas**: Plain-language explanation of key calculations
- **Assumptions**: Hardcoded values identified (e.g., "8% processing fee")
- **Instructions**: How to use this for next year

### In-Cell Documentation:
- At least 6 cell comments added to formula cells
- Comments explain what the formula does (not just repeat it)
- Descriptive labels added near cryptic abbreviations

### Error Resolution:
- #REF! errors reduced or documented

## Verification Criteria

1. ✅ **Documentation Sheet Created**: New sheet with structured explanation (15% weight)
2. ✅ **Comments Added**: At least 6 substantive cell comments on formulas (20% weight)
3. ✅ **Labels Improved**: Cryptic abbreviations explained with full descriptions (15% weight)
4. ✅ **Errors Addressed**: #REF! count reduced or errors documented (15% weight)
5. ✅ **Formula Logic Explained**: At least 4 major formulas have explanations (15% weight)
6. ✅ **Assumptions Documented**: Hardcoded values identified (10% weight)
7. ✅ **Content Quality**: Documentation uses plain language, >500 characters (10% weight)

**Pass Threshold**: 70% (requires at least 5 out of 7 criteria)

## Skills Tested

- Formula inspection (clicking cells to view formulas)
- Cell navigation (tracing precedents/dependents)
- Comment insertion (Right-click → Insert Comment)
- Sheet management (creating new sheets)
- Reverse engineering calculation logic
- Technical documentation writing
- Error diagnosis (#REF!, #VALUE!, etc.)

## Tips

- Click on cells to see formulas in the formula bar
- Use Ctrl+[ to jump to precedent cells
- Right-click cells to Insert Comment
- Create new sheet: Right-click sheet tab → Insert Sheet
- Common abbreviations in theater context:
  - SR = Senior tickets
  - GEN = General admission  
  - STD = Student discount
  - COMP = Complimentary (free) tickets
- Look for hardcoded numbers in formulas (like 0.08 or 0.2)
- #REF! means a referenced cell was deleted

## Scenario Context

A community theater volunteer needs to set ticket prices for the annual gala in 6 weeks. The previous treasurer left unexpectedly (family emergency) and is unreachable. Their revenue projection spreadsheet is the only tool available, but it's completely cryptic. Document it so the theater can use it and pass it on to future treasurers.

This represents a common real-world succession crisis in small organizations where institutional knowledge lives in one person's undocumented spreadsheet.