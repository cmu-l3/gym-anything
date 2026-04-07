# Import Legacy Application Logs from CSV (`import_csv_app_logs@1`)

## Overview
This task evaluates the ability to ingest data from non-standard sources by importing a CSV log file. The agent must map CSV columns to the appropriate SIEM fields (Timestamp, Severity, Source, Message) to ensure the data is correctly indexed and searchable.

## Rationale
**Why this task is valuable:**
- **Interoperability**: Tests the ability to integrate legacy or custom application logs that don't use standard syslog protocols.
- **Schema Mapping**: Requires understanding of log data structures and mapping them to SIEM schema fields.
- **Data Ingestion**: Validates "batch" ingestion capabilities distinct from live monitoring.

**Real-world Context:** A legacy Payroll application exported its activity logs to a CSV file. The Security Manager needs these logs inside EventLog Analyzer to investigate a "batch processing error" and correlate it with other system events.

## Task Description

**Goal:** Import the CSV log file located at `~/Documents/payroll_logs.csv` into EventLog Analyzer, ensuring correct field mapping.

**Starting State:**
- EventLog Analyzer is running.
- A CSV file exists at `~/Documents/payroll_logs.csv`.
- Firefox is open.

**Expected Actions:**
1. Navigate to the **Settings** > **Import Log Data** (or equivalent import section).
2. Upload `~/Documents/payroll_logs.csv`.
3. Configure the import format (CSV).
4. **Map the columns:**
   - `Date` -> Timestamp (Format: `yyyy-MM-dd HH:mm:ss`)
   - `Host` -> Source
   - `Severity` -> Severity
   - `Message` -> Message
5. Execute the import.
6. Verify the logs appear in search results (e.g., search for "PAYROLL").

**Final State:**
- The events from the CSV are stored in the database.
- Fields (Severity, Source, Time) are correctly parsed, not just dumped as raw text.

## Verification Strategy

### Primary Verification: Database Content Check
The verifier queries the internal database for events containing unique strings from the CSV (e.g., "Database connection lost during batch").

### Secondary Verification: Field Accuracy
- Checks if the event with "ERROR" in the CSV is stored with severity "Error" (or equivalent ID) in the SIEM.
- Checks if the event source is "PAYROLL-DB".

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Events Ingested | 40 | Target events found in database |
| Severity Mapped | 20 | Severity field matches CSV input (Error vs Info) |
| Source Mapped | 20 | Source/Host field matches "PAYROLL-DB" |
| Message Content | 20 | Full message content preserved |
| **Total** | **100** | |