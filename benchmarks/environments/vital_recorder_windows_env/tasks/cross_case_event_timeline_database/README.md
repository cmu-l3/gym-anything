# Task: cross_case_event_timeline_database

## Domain Context

Perioperative workflow research studies how time is structured across surgical cases. By analyzing when key events occur (case start, incision, procedure end, emergence) across multiple cases, researchers can identify patterns in surgical timing, bottlenecks in OR workflow, and variation in phase durations.

Vital Recorder automatically captures event markers from the anesthesia workstation clock. Each recording contains 4 standard events: Case started (patient enters OR), Surgery started (first incision), Surgery finished (wound closed), and Case finished (patient leaves OR). These events partition the recording into pre-operative, intraoperative, and post-operative phases.

## Occupation Context

**Primary users**: Perioperative Medicine Researchers, Surgical Quality Coordinators, OR Efficiency Analysts
**Task type**: Cross-case data extraction — building a structured event timeline database from multiple recordings

## Task Goal

The agent must:
1. Open all three .vital files sequentially
2. Navigate to and read all event markers in each file
3. Export all three cases to separate CSV files
4. Construct a structured multi-case event database with computed timestamps and phase labels

## Why This Is Hard

- Agent must work with ALL THREE files (not just one)
- Agent must navigate the event panel in each recording and read timestamps
- Agent must compute "time from case start" offsets (requires arithmetic from the displayed timestamps)
- Agent must correctly categorize events by perioperative phase
- Three separate CSV exports are required
- The database document requires structured multi-column tabular content
- Hardest subtask: reading and transcribing event timestamps from the Vital Recorder UI accurately

## Ground Truth

- All three cases share the same 4 standard events:
  - `Case started` → pre-operative phase (time = 0:00)
  - `Surgery started` → start of intraoperative phase
  - `Surgery finished` → end of intraoperative phase
  - `Case finished` → end of post-operative phase
- Total expected events: 12 (4 per case × 3 cases)
- Expected CSVs: `case_0001_events.csv`, `case_0002_events.csv`, `case_0003_events.csv`
- Expected database: `event_timeline_db.txt` with Case_ID, Event_Name, Time_from_Start_min, Phase columns

## Success Criteria

| Criterion | Points | What Is Checked |
|-----------|--------|-----------------|
| All three CSV exports exist (one per case) | 20 | All 3 files ≥100 bytes each |
| Event database exists with substantial content | 20 | File ≥400 bytes |
| Database mentions all three case identifiers | 20 | "0001", "0002", "0003" all present |
| Database contains recognized event names | 20 | "Surgery started/finished", "Case started/finished" |
| Database has numeric time data (timestamps) | 20 | Numbers with time/min context present |

**Pass threshold**: 60/100
**Output gate**: Score=0 if no CSV files AND no database exist

## Verification Strategy

- All three CSV files are independently retrieved and checked for size
- Database document is retrieved and parsed for case identifiers, event names, and numeric content
- Flexible keyword matching allows for minor variations in event name spelling
- The core requirement is multi-case coverage — the agent must have opened all three recordings
