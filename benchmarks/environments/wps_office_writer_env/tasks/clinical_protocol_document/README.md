# Clinical Protocol Document

## Task Description
Restructure a poorly formatted Vancomycin IV administration protocol into a properly formatted clinical protocol document.

## Occupation Context
Clinical nurse specialist at a teaching hospital preparing clinical protocols.

## Difficulty: Very Hard

## Challenges
- Apply heading hierarchy to all protocol sections (currently all Normal style)
- Extract dosage adjustment data from prose into a renal dosing table
- Create adverse reactions classification table from prose (organize by frequency)
- Create monitoring schedule table (labs, frequency, timing)
- Add 4 missing required sections: Purpose, Scope, Equipment Required, Revision History
- Preserve critical clinical dosing values exactly (patient safety data)
- Format all tables professionally
- Multiple interdependent sections with cross-referenced clinical data

## Data Source
Based on IDSA/ASHP/SIDP Vancomycin Therapeutic Monitoring Guidelines (2020)
https://doi.org/10.1093/ajhp/zxaa036

## Verification
- Section heading styles (python-docx)
- Heading hierarchy depth
- Dosing table with renal adjustment data
- Adverse reactions table
- Monitoring schedule table
- Missing sections added
- Table header formatting
- Critical clinical data preservation
- VLM visual verification
