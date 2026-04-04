# Legal Timeline Assembly Task (`legal_timeline_assembly@1`)

## Overview

This task challenges an agent to complete and format a partially-finished legal discovery timeline by integrating additional events from a notes file, correcting formatting inconsistencies, completing incomplete entries, and ensuring chronological accuracy - skills essential for legal document preparation.

## Scenario

Sarah is defending herself against a property damage claim from her former landlord. Her attorney requested a detailed timeline of all interactions and incidents for the discovery phase. She started the document three weeks ago but left it incomplete with formatting issues.

**The Crisis:** Discovery documents are due in 48 hours. The attorney's paralegal reviewed it and sent feedback: "This timeline is incomplete, has formatting issues, and still contains draft instructions. Please integrate all events from your notes, complete the incomplete entries, ensure chronological order, and make it submission-ready."

## Task Requirements

The agent must:

1. **Remove Draft Instructions**: Delete the red instruction section at the top (unprofessional for court submission)

2. **Integrate Additional Events**: Add 5 events from `additional_events.txt` (on Desktop) into the timeline table in proper chronological order

3. **Complete Incomplete Entries**: Fill in missing information:
   - August 10, 2024: Complete the inspection description
   - September 20, 2024: Add the correct exhibit reference (E-2)
   - Any other [TBD] or [INCOMPLETE] entries

4. **Fix Formatting Inconsistencies**: Ensure all dates are bolded (some are currently not)

5. **Verify Chronological Order**: Ensure all events are sequenced from earliest to latest date

6. **Save Document**: Final save before submission

## Files Provided

- **`timeline_draft.docx`** (in Documents/TextDocuments/): Partially-completed timeline with issues
- **`additional_events.txt`** (on Desktop): Notes containing 5 events to integrate, plus completion instructions

## Verification Criteria

✅ **Pass Threshold: 70/100 points**

- **Instructions Removed** (15 pts): No draft instruction text remains
- **Table Structure** (10 pts): Timeline table intact with sufficient rows
- **Events Integrated** (30 pts): All 5 events from notes file added chronologically
- **No Placeholders** (15 pts): All [TBD], [INCOMPLETE] entries filled
- **Completed Entries** (15 pts): August 10 and September 20 entries completed
- **Exhibit References** (10 pts): Proper exhibit citations throughout
- **Chronological Order** (10 pts): Events sequenced correctly by date

## Skills Tested

- **Document Navigation**: Scrolling through multi-page documents
- **Table Editing**: Inserting rows, modifying cell content
- **Multi-file Workflow**: Referencing separate notes file
- **Chronological Reasoning**: Determining correct temporal sequence
- **Information Integration**: Merging content from multiple sources
- **Formatting Consistency**: Applying uniform professional styling
- **Completeness Verification**: Ensuring no placeholders remain
- **Professional Document Standards**: Legal submission-ready formatting

## Expected Workflow

1. Review timeline draft and identify issues
2. Open additional_events.txt from Desktop
3. Delete instruction section from document
4. Insert new table rows at appropriate chronological positions
5. Enter dates, descriptions, and exhibit references for 5 new events
6. Complete the August 10 description (landlord inspection details)
7. Add Exhibit E-2 reference to September 20 entry
8. Fix formatting for dates that aren't bolded (July 12, September 20)
9. Verify chronological order top to bottom
10. Save document (Ctrl+S)

## Difficulty: Medium

**Why Medium?**
- Requires multiple distinct operations (delete, insert rows, edit cells, format)
- Information integration from two sources
- Chronological reasoning with 12+ dates
- Table manipulation skills
- Professional formatting standards
- Realistic legal context with deadline pressure

**Not Too Easy:** Must integrate information, make ordering decisions, and perform precision editing.

**Not Too Hard:** All information provided, no research needed, uses standard OnlyOffice operations.

## Real-World Relevance

This task simulates actual pre-litigation document preparation that pro se litigants, paralegals, and attorneys perform regularly. Discovery timelines are critical for:
- Establishing facts chronologically
- Supporting legal arguments
- Complying with court discovery requirements
- Preparing for depositions and trial

Errors in timeline completeness or chronology can weaken a legal case significantly.