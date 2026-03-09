# patient_index_deduplication

**Difficulty**: Very Hard
**Occupation**: Health Information Management Specialist / Medical and Health Services Manager (SOC 11-9111.00)
**Domain**: Patient Identity Management, Healthcare Master Data

---

## Domain Context

Health Information Management (HIM) specialists are responsible for maintaining accurate, deduplicated patient records across multi-facility health systems. A Patient Master Index (PMI) is the authoritative registry of patient identities — when a patient's name, address, or insurance changes, multiple EHR systems send ADT (Admit/Discharge/Transfer) demographic update messages. Without proper deduplication, each update creates a new row instead of updating the existing record, leading to fragmented patient histories, incorrect billing, and clinical errors.

ADT^A31 (Update Patient Information), ADT^A28 (Add Patient Information), and ADT^A08 (Update Patient Information) message types all carry demographic updates via the PID (Patient Identification) segment. The PID segment contains the patient's MRN (Medical Record Number), legal name, date of birth, gender, and SSN.

PostgreSQL's `ON CONFLICT DO UPDATE` (UPSERT) syntax enables atomic insert-or-update operations — if a patient with the same MRN already exists, update their record and increment an update counter. This is the standard pattern for maintaining a deduplicated master patient index in HL7 integration workflows.

---

## Goal

Build a NextGen Connect channel that maintains a deduplicated Patient Master Index in PostgreSQL:

- Accepts HL7 ADT demographic update messages and extracts key patient identity fields from the PID segment
- Upserts each patient record using the MRN as the unique key — new patients are inserted, returning patients are updated, and an update counter is incremented on each update
- Generates and returns a proper HL7 ACK (acknowledgment) message to the sending system for every received message
- The channel must be actively deployed

---

## Success Criteria

The task is complete when:

1. A channel named **Patient Master Index Sync** is deployed in NextGen Connect
2. The channel listens on **TCP port 6665** using MLLP framing
3. The channel contains a **JavaScript transformer** that extracts patient identity fields from PID (MRN, name, DOB, gender, SSN) and makes them available for the database destination
4. The channel has a **Database Writer destination** containing SQL that performs PostgreSQL upsert semantics using `ON CONFLICT (mrn) DO UPDATE SET ...` — including incrementing `update_count`
5. The channel has a **Response Transformer** that constructs a valid HL7 ACK message referencing the incoming MSH-10 (Message Control ID)
6. A **patient_master_index** table exists in PostgreSQL with `mrn` as a `PRIMARY KEY` or `UNIQUE` constraint (required for `ON CONFLICT` to work)
7. The channel is in **STARTED** status

---

## Verification Strategy

The verifier checks the following independent criteria (100 points total, threshold 70):

| Criterion | Points | Check Method |
|-----------|--------|--------------|
| Channel exists with appropriate name | 15 | PostgreSQL `channel` table query |
| Listening on port 6665 | 10 | XML `<port>` element extraction |
| JavaScript transformer with PID extraction | 20 | Channel XML keyword scan (`PID`, `channelMap`, `mrn`, `last_name`) |
| Database Writer destination for patient_master_index | 10 | Channel XML keyword scan (`DatabaseDispatcher`, `patient_master_index`) |
| PostgreSQL UPSERT (ON CONFLICT DO UPDATE) in SQL | 20 | Channel XML keyword scan (`ON CONFLICT`, `DO UPDATE`) |
| Response Transformer present | 10 | Channel XML `<responseTransformer>` check |
| patient_master_index table with unique mrn constraint | 10 | `information_schema.table_constraints` + `key_column_usage` query |
| Channel deployed and active | 5 | `d_channels` table + REST API status |

**Do-nothing score**: 0 (no channels or tables pre-created; setup only copies sample files)

---

## Schema Reference

### PostgreSQL Table (must be created by agent)

```sql
CREATE TABLE IF NOT EXISTS patient_master_index (
    mrn          VARCHAR(50) PRIMARY KEY,
    last_name    VARCHAR(100),
    first_name   VARCHAR(100),
    dob          VARCHAR(20),
    gender       VARCHAR(5),
    ssn          VARCHAR(20),
    last_updated TIMESTAMP DEFAULT NOW(),
    update_count INTEGER DEFAULT 1
);
```

### HL7 ADT^A31 / A28 / A08 Relevant Segments

- **MSH-10**: Message Control ID (used in ACK MSA-2)
- **MSH-12**: Version ID
- **PID-3**: Patient Identifier List — first repetition, first component (CX.1) is the MRN
- **PID-5**: Patient Name — PID-5.1 = Family Name, PID-5.2 = Given Name
- **PID-7**: Date/Time of Birth (YYYYMMDD or YYYYMMDDHHMMSS)
- **PID-8**: Administrative Sex (M/F/U/O)
- **PID-19**: SSN (may be empty; handle gracefully)

### HL7 ACK Structure

```
MSH|^~\&|<RecvApp>|<RecvFac>|<SendApp>|<SendFac>|<DateTime>||ACK|<NewMsgId>|P|2.5
MSA|AA|<OriginalMSH-10>|Message accepted
```

---

## Environment Reference

- **REST API**: `https://localhost:8443/api` (credentials: `admin` / `admin`)
- **Required header**: `X-Requested-With: OpenAPI`
- **PostgreSQL** (direct): `docker exec nextgen-postgres psql -U postgres -d mirthdb`
- **PostgreSQL** (JDBC from container): `jdbc:postgresql://nextgen-postgres:5432/mirthdb`
- **responseTransformer**: Must be present in every destination connector XML element
- **Sample message**: `/home/ga/sample_adt_a31.hl7` (ADT^A31 demographic update)

---

## Edge Cases and Potential Issues

1. **PID-3 field indexing in JavaScript**: `msg['PID']['PID.3']['PID.3.1'].toString()` extracts the MRN from the first repetition. If multiple identifiers exist (MRN + SSN), only the first repetition typically holds the MRN.

2. **SSN may be empty**: PID-19 is often omitted. Use null-safe access: `var ssn = msg['PID']['PID.19'] ? msg['PID']['PID.19']['PID.19.1'].toString() : ''`

3. **DOB format variability**: PID-7 may be `YYYYMMDD`, `YYYYMMDDHHMMSS`, or empty. Store as-is (VARCHAR) rather than parsing to avoid format errors.

4. **ON CONFLICT requires UNIQUE constraint**: PostgreSQL's `ON CONFLICT (mrn)` syntax requires either `PRIMARY KEY` or a named `UNIQUE` constraint on the `mrn` column. A regular index is not sufficient.

5. **update_count increment**: The SQL must reference the existing value: `update_count = patient_master_index.update_count + 1`. Using `EXCLUDED.update_count` would overwrite with 1 on every update.

6. **Response Transformer ACK**: The response transformer runs after all destinations complete. Access the original MSH-10 via `$('INBOUND_MESSAGE_ID')` or by re-parsing the original message in the response transformer context.

7. **Channel name length**: `channel.name` is `varchar(40)` in PostgreSQL. "Patient Master Index Sync" = 25 characters — within limit.
