# Spreadsheet Cleanup Task

**Difficulty**: 🟡 Medium
**Estimated Steps**: 15
**Timeout**: 120 seconds (2 minutes)

## Objective

Transform a poorly formatted, imported spreadsheet into a clean, professional, usable document. Remove junk rows, properly position headers, apply appropriate formatting, optimize column widths for readability, and configure frozen panes for easier navigation. This represents one of the most common real-world spreadsheet operations: cleaning up messy data imports before actual analysis can begin.

## Scenario

You asked your volunteer coordinator to send you the registration list for a community event. They exported it from an online form tool, and the resulting file is a disaster. You need to clean this up ASAP because you're printing name tags in 30 minutes and need the list usable on your phone during the event.

## Starting State

- A messy ODS file (`event_registrations_messy.ods`) opens automatically
- **Problems with the file:**
  - Blank row at top (row 1)
  - Export metadata in row 2: "Exported from FormSubmit Pro..."
  - Another blank row (row 3)
  - Summary metadata in row 4: "Total Registrations: 47"
  - Headers buried in row 5: Name, Email, Registration Date, Ticket Type, Dietary Restrictions
  - Data starts in row 6
  - All columns are narrow (default width ~64px), causing text truncation
  - Headers are plain text (not bold)
  - No freeze panes configured

## Data Structure (Before Cleanup)
