# Genealogy Data Consolidation Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, duplicate detection, date standardization, logical validation, conditional formatting  
**Duration**: 300 seconds  
**Steps**: ~20

## Objective

Clean and consolidate messy genealogy research data collected from multiple sources. Handle real-world data quality issues including duplicate entries with name variations, inconsistent date formats, logical impossibilities, and missing information. Create a standardized genealogy database suitable for building a family tree.

## Task Description

A genealogy enthusiast has collected data from family interviews, online databases, and old documents. The spreadsheet contains ~45 entries representing approximately 30 unique people, but it's too messy to use. The agent must:

1. **Standardize date formats**: Convert "circa 1850", "3/15/1850", "March 1850" to consistent YYYY-MM-DD format
2. **Identify and consolidate duplicates**: Recognize same person with name variations ("Mary Smith", "Mary E. Smith", "Mary Elizabeth Smith")
3. **Create validation columns**: Add "Age at Death" and "Data Issues" columns with formulas
4. **Flag logical errors**: Identify death before birth, impossible ages (>120 years, <0), parent age issues
5. **Apply conditional formatting**: Highlight problematic entries for human review
6. **Organize data**: Sort by family groups (surname, birth year)
7. **Preserve information**: Don't delete valuable data, flag for review instead

## Starting State

- LibreOffice Calc opens with `family_data_raw.ods` containing ~45 messy entries
- Columns: ID, Given Name, Surname, Birth Date, Birth Place, Death Date, Death Place, Parents, Notes, Source
- Multiple data quality issues present

## Data Quality Issues Present

1. **Duplicate entries**: Same person listed 2-3 times with slightly different names
2. **Date format chaos**:
   - "circa 1850"
   - "3/15/1850"
   - "March 1850"
   - "1850"
   - "ca. 1875"
   - "about 1920"
3. **Logical impossibilities**:
   - Death date before birth date (2 cases)
   - Age at death > 120 years (1 case)
   - Parent's age at child's birth < 15 years (1 case)
   - Birth year > death year (date entry error)
4. **Missing data**: ~30% death dates missing, 20% birth places missing
5. **Name variations**: "John", "John M.", "John Michael" representing same person

## Expected Results

- **Entry count**: Reduced from ~45 to 28-32 unique people
- **Date formats**: >90% standardized to YYYY-MM-DD or ~YYYY-MM-DD (uncertain)
- **Validation columns**: "Age at Death" and "Data Issues" columns present with formulas
- **Error flagging**: At least 5 logical errors identified
- **Conditional formatting**: Visual highlighting applied to problematic rows
- **Organization**: Sorted by surname, then birth year
- **Data integrity**: No loss of critical information during consolidation

## Verification Criteria

1. ✅ **Date Standardization**: >90% dates in YYYY-MM-DD format
2. ✅ **Duplicate Reduction**: Entry count reduced from ~45 to 28-32
3. ✅ **Validation Columns**: "Age at Death" and "Data Issues" columns with formulas
4. ✅ **Issue Flagging**: At least 5 logical errors identified in Data Issues column
5. ✅ **Conditional Formatting**: Visual highlighting applied to problematic rows
6. ✅ **Data Integrity**: No loss of critical information
7. ✅ **Proper Sorting**: Organized by surname and birth year

**Pass Threshold**: 75% (5/7 criteria must pass)

## Skills Tested

- Multi-column data manipulation
- Date format standardization and parsing
- Duplicate detection with fuzzy matching
- Formula creation (IF, AND, OR, YEAR, DATE functions)
- Conditional formatting rules
- Data sorting and organization
- Logical validation and quality assessment
- Data consolidation without information loss

## Tips

- Use Find & Replace for batch date format changes
- YEAR(), MONTH(), DAY() functions help extract date components
- Create helper columns for duplicate detection (e.g., "Full Name + Birth Year")
- IF() formulas can flag multiple issues: `=IF(AND(D2<>"", F2<>"", F2<D2), "Death before birth", "")`
- Conditional formatting: Format → Conditional Formatting → Condition
- Sort: Data → Sort → Multiple levels (Surname, then Birth Year)
- Don't delete duplicates immediately - mark them first, then consolidate information

## Real-World Context

This mirrors challenges faced by:
- Genealogy researchers consolidating data from ancestry sites, interviews, documents
- Data analysts cleaning customer databases with duplicate records
- Medical records specialists standardizing patient data from multiple systems
- Anyone inheriting a messy spreadsheet needing to make it usable