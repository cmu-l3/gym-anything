# hl7_batch_file_processor

**Difficulty**: Very Hard
**Occupation**: Healthcare IT Integration Specialist / Health Informatics Specialist (SOC 15-1211.01)
**Domain**: Laboratory Integration, Batch Processing, Healthcare Data Operations

---

## Domain Context

Healthcare IT Integration Specialists at reference laboratories receive nightly batch transmissions from hospital clients. Rather than individual real-time HL7 messages over TCP/MLLP, these batch files are transferred as files (often via SFTP or secure file share). Each batch file uses an HL7 batch envelope: a BHS (Batch Header Segment) and BTS (Batch Trailer Segment) wrapping multiple individual HL7 messages.

The current manual process of extracting individual messages from batch files and processing them creates a 4-hour backlog each morning, delaying lab result reporting. Automating this with an integration engine channel reduces the backlog to near-zero.

NextGen Connect's File Reader source connector (distinct from the TCP Listener used in most beginner tasks) polls a directory for new files and processes them. The channel can be configured to:
- Use a **preprocessor script** to split batch files into individual messages before processing
- Or use the built-in **batch processing** feature (`processBatch=true`) with a custom batch script
- Move processed files to an archive directory to prevent reprocessing

This is a common real-world integration pattern at reference labs, hospital data warehouses, and health information exchanges (HIEs).

---

## Goal

Build a NextGen Connect channel that automatically processes nightly HL7 batch files:

- Monitors a directory for new batch HL7 files (`.hl7` extension)
- Splits each batch file's BHS/BTS envelope and extracts individual messages for processing
- Writes a processing record for each individual message to a PostgreSQL audit table
- Moves processed files to an archive directory to prevent duplicate processing
- The channel must be actively deployed

A sample batch file (with 4 individual messages wrapped in BHS/BTS) is pre-placed in the inbox directory for testing.

---

## Success Criteria

The task is complete when:

1. A channel named **Nightly HL7 Batch Processor** is deployed in NextGen Connect
2. The channel uses a **File Reader source connector** (NOT a TCP Listener) polling `/home/ga/hl7_batch_inbox/` for `*.hl7` files
3. The channel has **batch processing logic** — either a JavaScript preprocessor that splits BHS/BTS envelopes, or the built-in `processBatch=true` with a batch script
4. The channel has a **Database Writer destination** that INSERTs records into **batch_processing_log**
5. The File Reader is configured to **move processed files** to `/home/ga/hl7_batch_archive/` after successful processing
6. The **batch_processing_log** table exists in PostgreSQL
7. The channel is in **STARTED** status

---

## Verification Strategy

The verifier checks the following independent criteria (100 points total, threshold 70):

| Criterion | Points | Check Method |
|-----------|--------|--------------|
| Channel exists with appropriate batch-related name | 15 | PostgreSQL `channel` table query |
| **File Reader** source detected (not TCP Listener) | 25 | Channel XML class name (`FileReceiverProperties`) |
| Batch processing / preprocessor configured | 20 | XML scan for `processBatch`, `BatchScript`, `BHS`, `split` |
| Database Writer for batch_processing_log | 15 | Channel XML scan (`DatabaseDispatcher`, `batch_processing_log`) |
| Archive/move-after-processing configured | 10 | XML scan for `moveToDirectory`, `hl7_batch_archive`, `afterProcessingAction` |
| batch_processing_log table exists | 10 | `information_schema.tables` query |
| Channel deployed and active | 5 | `d_channels` table + REST API status |

**Do-nothing score**: 0 (no channels or tables pre-created; setup creates directories and places sample batch file only)

---

## Schema Reference

### PostgreSQL Table (must be created by agent)

```sql
CREATE TABLE IF NOT EXISTS batch_processing_log (
    batch_file    VARCHAR(255),
    message_seq   INTEGER,
    patient_mrn   VARCHAR(50),
    message_type  VARCHAR(20),
    processed_at  TIMESTAMP DEFAULT NOW()
);
```

### HL7 Batch File Format (BHS/BTS Envelope)

```
BHS|^~\&|<SendingApp>|<SendingFac>|<ReceivingApp>|<ReceivingFac>|<DateTime>||<BatchName>|<BatchId>|P|2.5
MSH|^~\&|...|ADT^A01|MSG001|P|2.5
PID|1||MRN001|||...
PV1|...
MSH|^~\&|...|ADT^A01|MSG002|P|2.5
PID|1||MRN002|||...
PV1|...
BTS|<MessageCount>
```

- **BHS**: Batch Header — identifies the batch sender, batch ID
- **BTS**: Batch Trailer — includes a count of messages in the batch
- Individual messages between BHS and BTS are standard HL7 messages starting with MSH

### File Reader Source Connector XML

The File Reader uses a different source connector class than TCP Listener:

```xml
<sourceConnector>
  <properties class="com.mirth.connect.connectors.file.FileReceiverProperties">
    <directoryPath>/home/ga/hl7_batch_inbox</directoryPath>
    <fileFilter>*.hl7</fileFilter>
    <moveToDirectory>/home/ga/hl7_batch_archive</moveToDirectory>
    <afterProcessingAction>MOVE</afterProcessingAction>
    <processBatch>true</processBatch>
    <!-- OR use preprocessor script for custom batch splitting -->
  </properties>
</sourceConnector>
```

---

## Environment Reference

- **REST API**: `https://localhost:8443/api` (credentials: `admin` / `admin`)
- **Required header**: `X-Requested-With: OpenAPI`
- **PostgreSQL** (direct): `docker exec nextgen-postgres psql -U postgres -d mirthdb`
- **PostgreSQL** (JDBC): `jdbc:postgresql://nextgen-postgres:5432/mirthdb`
- **Inbox directory**: `/home/ga/hl7_batch_inbox/` (sample file: `nightly_batch_20240115.hl7`)
- **Archive directory**: `/home/ga/hl7_batch_archive/`
- **Reference copy of batch file**: `/home/ga/sample_batch.hl7`
- **responseTransformer**: Must be present in every destination connector

---

## Edge Cases and Potential Issues

1. **File Reader vs. TCP Listener**: Most NextGen Connect documentation and examples use TCP Listener. The File Reader source uses a completely different XML structure (`FileReceiverProperties` vs. `TcpReceiverProperties`). This is the primary difficulty of this task.

2. **Batch splitting approaches**: Two options exist:
   - `processBatch=true` with a batch script that returns individual messages (simpler)
   - A preprocessor JavaScript that manually splits the content string (more flexible but complex)
   The batch script approach is more standard for HL7 batch files.

3. **BHS/BTS stripping**: When splitting, the BHS and BTS lines should be stripped from individual messages. Only lines starting with `MSH`, `PID`, `PV1`, `EVN`, `OBR`, `OBX`, etc. are valid message segments.

4. **File polling interval**: The default polling interval is 5000ms (5 seconds). Set to 30000ms (30 seconds) as specified. The sample file placed in the inbox will be picked up on the next polling cycle after deployment.

5. **Archive directory must exist**: The File Reader will fail to move files if the archive directory doesn't exist. The setup script creates `/home/ga/hl7_batch_archive/` — verify it exists before deploying.

6. **Message count from BTS**: `BTS|4` means 4 individual messages. After batch processing, the `batch_processing_log` table should have 4 rows if the sample file was processed.

7. **Channel restart for polling**: After deploying, the channel may need to be in STARTED state (not just DEPLOYED) for the file reader to begin polling. Use the API to start the channel after deployment.
