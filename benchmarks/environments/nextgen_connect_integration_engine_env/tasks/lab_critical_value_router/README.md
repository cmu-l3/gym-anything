# lab_critical_value_router

**Difficulty**: Very Hard
**Occupation**: Health Informatics Specialist (SOC 15-1211.01)
**Domain**: Clinical Laboratory Informatics, HL7 Integration

---

## Domain Context

Health Informatics Specialists at hospital systems are responsible for ensuring that laboratory results reach the right clinical destination in a timely manner. Critical lab values (e.g., dangerously high potassium indicating cardiac risk) require immediate clinical intervention. When all lab results—routine and critical—flow to the same destination, clinicians cannot reliably distinguish urgent results from routine ones, creating patient safety risks.

NextGen Connect (formerly Mirth Connect) is the industry-standard open-source HL7 integration engine used by hospital IT departments to route, filter, and transform healthcare messages between systems. Real workflows involve multi-destination channels with conditional routing logic.

The HL7 ORU^R01 (Observation Result) message type carries lab results. Within each ORU message, one or more OBX (Observation Result) segments carry individual test values. OBX-8 (Abnormal Flags) indicates clinical severity: `HH` = high critical, `LL` = low critical, `H` = high, `L` = low, `N` = normal.

---

## Goal

Build a NextGen Connect channel that correctly separates incoming HL7 lab result messages by clinical severity:

- Messages containing any **critical** OBX values (`HH` or `LL` in OBX-8) must be stored in a dedicated critical results database table and available for urgent clinical alerting.
- Messages where all OBX values are **non-critical** must be stored in a separate normal results table for routine review.
- **All** incoming messages, regardless of severity, must be written to an audit log for compliance purposes.
- The channel must be actively deployed and receiving connections.

Sample HL7 ORU messages demonstrating both critical and normal values are provided for reference and testing.

---

## Success Criteria

The task is complete when:

1. A channel named **Lab Critical Value Router** is deployed in NextGen Connect
2. The channel listens on **TCP port 6664** using MLLP framing
3. The channel contains a **JavaScript transformer** that evaluates OBX-8 across all OBX segments and sets a routing variable based on whether any critical flag is present
4. The channel has **three destinations**:
   - A Database Writer that routes to **critical_lab_results** when a critical flag is detected
   - A Database Writer that routes to **normal_lab_results** when no critical flag is detected
   - A File Writer that logs all messages to `/tmp/lab_audit/` unconditionally
5. Both **critical_lab_results** and **normal_lab_results** tables exist in PostgreSQL (`mirthdb`)
6. The channel is in **STARTED** status

---

## Verification Strategy

The verifier checks the following independent criteria (100 points total, threshold 70):

| Criterion | Points | Check Method |
|-----------|--------|--------------|
| Channel exists in DB with appropriate name | 15 | PostgreSQL `channel` table query |
| Listening on port 6664 | 10 | XML `<port>` element extraction |
| JavaScript transformer with OBX analysis | 20 | Channel XML keyword scan (`OBX`, `isCritical`, `HH`/`LL`) |
| Three destinations configured | 15 | Count `<connector>` elements in `<destinationConnectors>` |
| Conditional routing filter scripts | 10 | Channel XML scan for filter conditions |
| Correct destination types (2× DB, 1× File) | 15 | XML class name detection |
| Both DB tables exist in PostgreSQL | 10 | `information_schema.tables` query |
| Channel deployed and active | 5 | `d_channels` table + REST API status |

**Do-nothing score**: 0 (no channels are pre-created; setup only copies sample files)

---

## Schema Reference

### PostgreSQL Tables (must be created by agent or channel)

```sql
CREATE TABLE critical_lab_results (
    message_id    VARCHAR(100),
    patient_mrn   VARCHAR(50),
    test_code     VARCHAR(100),
    test_value    VARCHAR(100),
    abnormal_flag VARCHAR(10),
    observation_time VARCHAR(30),
    received_at   TIMESTAMP DEFAULT NOW()
);

CREATE TABLE normal_lab_results (
    message_id    VARCHAR(100),
    patient_mrn   VARCHAR(50),
    test_code     VARCHAR(100),
    test_value    VARCHAR(100),
    abnormal_flag VARCHAR(10),
    observation_time VARCHAR(30),
    received_at   TIMESTAMP DEFAULT NOW()
);
```

### HL7 ORU^R01 Relevant Segments

- **MSH-10**: Message Control ID (unique message identifier)
- **PID-3**: Patient Identifier (MRN in first repetition, CX.1 component)
- **OBR-4**: Observation Identifier (test code)
- **OBX-3**: Observation Identifier (individual test code)
- **OBX-5**: Observation Value (the numeric result)
- **OBX-8**: Abnormal Flags (`HH`=high critical, `LL`=low critical, `H`=high, `L`=low, `N`=normal, empty=unspecified)
- **OBX-14**: Date/Time of Observation

---

## Environment Reference

- **REST API**: `https://localhost:8443/api` (credentials: `admin` / `admin`)
- **Required header on all API calls**: `X-Requested-With: OpenAPI`
- **Web dashboard** (`https://localhost:8443`): monitoring only — cannot create channels
- **PostgreSQL** (direct): `docker exec nextgen-postgres psql -U postgres -d mirthdb`
- **PostgreSQL** (JDBC from container): `jdbc:postgresql://nextgen-postgres:5432/mirthdb` (user: `postgres`, password: `postgres`)
- **Channel XML requirement**: Every destination connector must include a `<responseTransformer>` element or deployment silently fails
- **File Writer output**: Written inside the NextGen Connect Docker container filesystem — use `docker exec nextgen-connect ls /tmp/lab_audit/` to verify

---

## Edge Cases and Potential Issues

1. **OBX iteration in JavaScript**: The `msg['OBX']` object in NextGen Connect's Rhino JavaScript engine is zero-indexed. Use a `for` loop over `msg['OBX'].length()` to check all OBX-8 fields — do not assume only one OBX segment exists.

2. **Channel name length limit**: PostgreSQL column `channel.name` is `varchar(40)`. Names exceeding 40 characters will be silently truncated.

3. **Destination filter vs. transformer variable**: The filter script on each destination runs AFTER the transformer. A channel map variable set in the transformer (e.g., `channelMap.put('isCritical', 'true')`) is accessible in destination filters via `$('isCritical')`.

4. **responseTransformer requirement**: Channel XML MUST include `<responseTransformer><elements/></responseTransformer>` inside each `<connector>` element. Missing it causes `NullPointerException` on deploy — the API returns HTTP 204 (success) even when internal deployment fails.

5. **Table creation timing**: Tables can be pre-created via `docker exec nextgen-postgres psql` OR created within the Database Writer's destination init script. Either approach is valid.

6. **Critical vs. normal filter exclusivity**: If both filters use the same condition (or one has no filter), messages will appear in both tables. The filters must be mutually exclusive: one checks `isCritical == 'true'`, the other checks `isCritical != 'true'`.
