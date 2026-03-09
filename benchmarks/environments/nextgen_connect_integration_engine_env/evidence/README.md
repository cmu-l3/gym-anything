# NextGen Connect Integration Engine Environment - Evidence

**Date**: 2026-03-03
**Status**: Complete (10 tasks, REST API approach)

---

## Overview

NextGen Connect (formerly Mirth Connect) is an open-source healthcare integration engine that enables bi-directional HL7 message routing, filtering, and transformation between healthcare information systems.

**Version**: 4.5.0 (last fully open-source version before licensing changes in 4.6+)

## Architecture

### Components

1. **NextGen Connect Container** (`nextgenhealthcare/connect:4.5.0`)
   - HTTP Landing Page: http://localhost:8080
   - HTTPS Web Dashboard: https://localhost:8443 (monitoring only)
   - REST API: https://localhost:8443/api (channel management)
   - Admin credentials: `admin` / `admin`
   - HL7 Listener Ports: 6661-6668 (configurable per channel)

2. **PostgreSQL Database** (`postgres:15`)
   - Database: `mirthdb`
   - User: `postgres` / `postgres`
   - Port: 5432
   - 14 tables: `channel`, `person`, `d_channels`, `configuration`, etc.

3. **Firefox Browser**
   - Pre-configured with Snap Firefox detection
   - Homepage set to `http://localhost:8080` (HTTP landing)
   - Sidebar disabled, first-run suppressed

### Critical Technical Notes

- **X-Requested-With header**: NextGen Connect 4.x API requires `X-Requested-With: OpenAPI` header on ALL REST API calls. Without it, returns HTTP 400.
- **responseTransformer**: Channel XML MUST include `<responseTransformer>` element in destination connectors. Without it, deployment fails with `NullPointerException: Cannot invoke getResponseTransformer()`.
- **Web dashboard is MONITORING ONLY**: Cannot create or manage channels via the web UI. Use REST API with curl.
- **SSL self-signed cert**: Web dashboard at https://localhost:8443 uses self-signed cert. Firefox shows security warning.
- **Channel name limit**: `channel.name` is varchar(40) in PostgreSQL schema.
- **Deployment tracking**: Deployed channels tracked in `d_channels` table, not in `channel` table itself.
- **Message tables**: NextGen creates `d_m1`, `d_m2`, etc. (sequential, NOT `d_m<channelId>`).
- **Output files**: File Writer destinations write inside the Docker container, not the host VM filesystem.
- **Docker networking**: Containers communicate via `nextgen-network` Docker bridge network.

## Installation Process

### Phase 1: pre_start Hook (`install_nextgen_connect.sh`)

- Installs Docker and Docker Compose
- Pulls `nextgenhealthcare/connect:4.5.0` image
- Pulls `postgres:15` image
- Installs Firefox, automation tools (wmctrl, xdotool, imagemagick, netcat-openbsd)
- Installs Java runtime (`default-jre`)
- Installs Python deps (lxml, requests, beautifulsoup4)

### Phase 2: post_start Hook (`setup_nextgen_connect.sh`)

- Creates Docker bridge network (`nextgen-network`)
- Starts PostgreSQL container with `mirthdb` database on the network
- Starts NextGen Connect container on the network (ports 8080, 8443, 6661-6663)
- Waits for PostgreSQL readiness (pg_isready, 60s timeout)
- Waits for NextGen Connect API readiness (180s timeout, checks X-Requested-With header)
- Configures Firefox profile (Snap or native detection)
- Launches Firefox at `http://localhost:8080`

**No `set -e`** - wait functions may return non-zero on timeout.

## Real Data Sources

**Source**: [Work-In-Progress-For-Health/hl7-v2-examples](https://github.com/Work-In-Progress-For-Health/hl7-v2-examples)

### Sample Messages

1. **hl7-v2.3-adt-a01-1.hl7** (717 bytes, 8 CR-delimited segments)
   - Patient: KLEINSAMPLE, BARRY Q JR
   - Event: A01 (Patient Admission)

2. **hl7-v2.3-oru-r01-1.hl7** - ORU^R01 (Observation Result)
   - Immunization records

3. **hl7-v2.4-oru-r01-1.hl7** - HL7 v2.4 ORU^R01
   - Patient: MASSIE, JAMES A

## Tasks (5 total)

### 1. create_hl7_channel
- Create and deploy "Patient Admission Channel" via REST API
- TCP Listener on port 6661, File Writer to /tmp/hl7_output/
- Scoring: 20 (new channel) + 15 (exists) + 10 (name) + 15 (source type) + 10 (port) + 10 (dest type) + 20 (deployed) = 100
- Pass threshold: 70

### 2. process_hl7_message
- Send ADT^A01 message through a pre-created channel via MLLP
- Channel is pre-created by setup_task.sh (self-contained task)
- Scoring: 10 (channel exists) + 50 (new messages delta) + 20 (received count) + 20 (evidence max) = 100
- Pass threshold: 60

### 3. transform_hl7_format
- Create "HL7 Transformer Channel" with transformation logic
- Convert HL7 to XML format, write output files
- Scoring: 15 (new channel) + 15 (exists) + 10 (name) + 25 (transformer) + 15 (format) + 20 (output) = 100
- Pass threshold: 70

### 4. configure_channel_filter
- Create "ADT Filter Channel" with filter logic
- TCP Listener on port 6662, filter MSH-9 for ADT messages only
- Scoring: 15 (new channel) + 15 (exists) + 10 (name) + 30 (filter logic) + 10 (port) + 20 (deployed) = 100
- Pass threshold: 70

### 5. setup_database_writer
- Create "Patient DB Writer" with Database Writer destination
- TCP Listener on port 6663, JDBC to PostgreSQL, INSERT into patient_records table
- Scoring: 10 (new channel) + 15 (exists) + 5 (name) + 25 (db writer) + 20 (table) + 10 (records) + 15 (deployed) = 100
- Pass threshold: 70

## Verification Strategy

All tasks use the two-part verification pattern:

1. **export_result.sh** (runs in VM)
   - Sources `task_utils.sh` for shared utilities
   - Queries PostgreSQL for channel/message data
   - Extracts channel config details (source type, port, destination type) from XML
   - Checks REST API for statistics and deployment status
   - Checks Docker container for output files
   - Writes JSON to `/tmp/<task>_result.json`

2. **verifier.py** (runs on host)
   - Uses `copy_from_env()` to retrieve JSON from VM
   - Multi-criteria scoring with channel config validation
   - Rebalanced scoring: channel existence alone is not enough to pass
   - Returns pass/fail with detailed feedback

## Task Start State

All tasks open a gnome-terminal window with:
- API connection info and credentials
- Available ports and tools
- Task-specific context (sample messages, database info)

The process_hl7_message task is self-contained: setup_task.sh pre-creates and deploys a channel, so the agent only needs to send a message.

### 6. lab_critical_value_router (very_hard)
- Occupation: Health Informatics Specialist (SOC 15-1211.01)
- Create "Lab Critical Value Router" with 3 destinations: critical DB writer (filter OBX-8=HH/LL), normal DB writer, audit file writer
- TCP Listener on port 6664, JavaScript transformer checks all OBX segments
- Tables: critical_lab_results, normal_lab_results
- Scoring: channel+name (15) + port (10) + JS transformer (20) + multi-dest (15) + filter logic (10) + dest types (15) + tables (10) + deployed (5) = 100
- Pass threshold: 70

### 7. patient_index_deduplication (very_hard)
- Occupation: Health Information Management Specialist (SOC 11-9111.00)
- Create "Patient Master Index Sync" channel with PostgreSQL ON CONFLICT upsert and ACK response transformer
- TCP Listener on port 6665, JS transformer extracts PID-3/5/7/8/19 fields
- Table: patient_master_index (mrn PRIMARY KEY, update_count increment on conflict)
- Scoring: channel+name (15) + port (10) + JS transformer (20) + DB dest (10) + upsert SQL (20) + response transformer (10) + table+constraint (10) + deployed (5) = 100
- Pass threshold: 70

### 8. siu_to_adt_bridge (very_hard)
- Occupation: Clinical Systems Integration Engineer (SOC 15-1299.09)
- Create 2-channel bridge: "SIU Intake Channel" (port 6666) → Channel Writer → "ADT Pre-Registration Processor" → DB Writer
- JS transformer maps SCH/PID fields from SIU to ADT; Channel Writer inter-channel routing
- Table: scheduling_preregistrations
- Scoring: SIU channel+port (20) + JS transformer (20) + Channel Writer (20) + ADT channel (15) + DB writer (10) + table (10) + both deployed (5) = 100
- Pass threshold: 70

### 9. hl7_batch_file_processor (very_hard)
- Occupation: Healthcare IT Integration Specialist (SOC 15-1211.01)
- Create "Nightly HL7 Batch Processor" with File Reader (NOT TCP) polling /home/ga/hl7_batch_inbox/*.hl7
- Preprocessor splits BHS/BTS-wrapped batch files; moves processed files to /home/ga/hl7_batch_archive/
- Table: batch_processing_log
- Scoring: channel+name (15) + File Reader source (25) + batch processing (20) + DB writer (15) + archive config (10) + table (10) + deployed (5) = 100
- Pass threshold: 70

### 10. enterprise_hl7_router (very_hard)
- Occupation: Integration Architect (SOC 15-1299.09)
- Create 3-channel enterprise facade: "Enterprise HL7 Router" (port 6668) + "Lab Results Processor" + "ADT Event Handler"
- Facade: JS transformer (MSH-3/9 extraction) + 2 Channel Writer dests (ORU→Lab, ADT→ADT) + DLQ DB fallback
- Pre-seeded routing_rules table; Tables: dead_letter_queue, lab_results_inbox, adt_events_inbox
- Scoring: facade+port (15) + JS transformer (15) + channel writers (20) + DLQ writer (10) + Lab channel (10) + ADT channel (10) + tables (10) + all deployed (10) = 100
- Pass threshold: 70

## Evidence Screenshots

1. **01_landing_page.png** - Firefox showing http://localhost:8080 NextGen Connect landing page
2. **02_web_dashboard_logged_in.png** - Web dashboard after login at https://localhost:8443
3. **03_environment_running.png** - Full desktop screenshot with environment running
