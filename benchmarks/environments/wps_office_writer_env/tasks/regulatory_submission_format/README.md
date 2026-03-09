# Regulatory Submission Format

## Task Description
Format a raw Periodic Benefit-Risk Evaluation Report (PBRER) for FDA submission per ICH E2C(R2) standards.

## Occupation Context
Regulatory affairs specialist at a pharmaceutical company preparing regulatory submissions.

## Difficulty: Very Hard

## Challenges
- Transform entirely unformatted plain text into structured regulatory document
- Apply ICH E2C(R2) mandated section heading hierarchy (7+ sections)
- Convert adverse event frequency data from prose into formatted tables
- Change all body text to Times New Roman 12pt with double spacing
- Add document control information (report number, dates)
- Preserve all safety-critical content during reformatting
- Multiple interdependent formatting requirements (font, spacing, headings, tables)

## Data Source
ICH E2C(R2) PBRER guideline structure from https://database.ich.org/sites/default/files/E2C_R2_Guideline.pdf

## Verification
- ICH section heading presence and styling (python-docx)
- Heading hierarchy depth (multi-level)
- Table creation from prose data
- Font name and size verification
- Line spacing verification
- Document control header
- Content completeness check
- VLM visual verification
