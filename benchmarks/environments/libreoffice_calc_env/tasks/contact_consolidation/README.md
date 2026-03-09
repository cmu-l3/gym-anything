# Contact Database Consolidation Task (`contact_consolidation@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, deduplication, text functions, conditional formatting  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~15

## Objective

Consolidate fragmented contact information from multiple sources into a clean, unified contact database. A community volunteer coordinator has collected attendee/volunteer contact data from different event platforms, manual sign-up sheets, and various sources over time. The data is messy with duplicates, inconsistent formatting, and incomplete records. Transform this chaotic data into a usable contact database.

## Starting State

LibreOffice Calc opens with a workbook containing three sheets:
- **EventPlatform1_Export**: CSV export from first event platform (40 entries)
- **EventPlatform2_Export**: CSV export from second event platform (35 entries)  
- **ManualEntry_SignUp**: Manually typed sign-up sheets (25 entries)

**Data Issues Present**:
- Duplicate people across sheets with name/email variations
- Mixed capitalization ("JOHN SMITH" vs "john smith" vs "John Smith")
- Inconsistent phone formatting ("(555) 123-4567" vs "555-123-4567" vs "5551234567")
- Email display names ("John Smith <john@email.com>" vs "john@email.com")
- Missing email or phone in some records
- Extra whitespace and formatting errors

## Required Actions

1. **Create MasterContactList sheet** with clean column structure
2. **Standardize email addresses** (lowercase, trim, remove display names)
3. **Identify duplicates** using COUNTIF or conditional formatting
4. **Merge duplicate records** (combine information from multiple sources)
5. **Standardize name formatting** (title case, consistent structure)
6. **Standardize phone numbers** (consistent format)
7. **Flag incomplete records** (missing both email AND phone)
8. **Remove duplicate rows** (keep only consolidated entries)
9. **Add summary statistics** (total contacts, complete vs incomplete)

## Expected Results

**MasterContactList Sheet Structure**: