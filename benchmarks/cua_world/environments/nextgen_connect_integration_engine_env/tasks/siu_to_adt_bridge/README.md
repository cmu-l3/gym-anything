# siu_to_adt_bridge

**Difficulty**: Very Hard
**Occupation**: IT Project Manager / Clinical Systems Integration Engineer (SOC 15-1299.09)
**Domain**: Healthcare Scheduling Integration, Multi-System HL7 Workflow

---

## Domain Context

Clinical systems integration engineers at health systems are responsible for ensuring that scheduling systems (Practice Management Systems / PMS) and clinical systems (EHR) share real-time patient state. When a patient books an appointment, the PMS sends an SIU^S12 (Schedule Information Unsolicited — New Appointment Booking) message. The downstream EHR must pre-register the patient as an ADT^A04 (Pre-Admit/Register) encounter before the appointment date so that registration staff can pull up the patient on arrival.

This requires a message format translation: SIU messages carry appointment data in the SCH (Scheduling Activity Information) segment and reference the patient via PID. ADT messages carry encounter data with a different MSH message type and interpret patient demographics from the same PID segment.

NextGen Connect's Channel Writer destination enables inter-channel routing: one channel can pass messages to another channel's internal message queue, enabling clean architectural separation of scheduling intake from EHR registration processing. This pattern is standard in enterprise healthcare integration architectures.

---

## Goal

Build a two-channel HL7 bridge in NextGen Connect:

**Channel 1 (SIU Intake)**: Receives SIU^S12 appointment booking messages from the Practice Management System, translates the scheduling data into an ADT^A04 pre-registration message format using a JavaScript transformer, and forwards the transformed message to Channel 2 via a Channel Writer destination.

**Channel 2 (ADT Pre-Registration Processor)**: Receives the translated ADT messages from Channel 1 via Channel Reader, and writes pre-registration records to a PostgreSQL table for downstream processing.

Both channels must be deployed and actively processing messages.

---

## Success Criteria

The task is complete when:

1. A channel named **SIU Intake Channel** is deployed, listening on **TCP port 6666** via MLLP
2. The SIU channel contains a **JavaScript transformer** that maps SIU/SCH/PID fields to ADT message components and sets channel map variables
3. The SIU channel has a **Channel Writer destination** that routes messages to Channel 2 by channel ID reference
4. A channel named **ADT Pre-Registration Processor** is deployed with a **Channel Reader** source (receives from Channel 1)
5. The ADT channel has a **Database Writer destination** that INSERTs into the **scheduling_preregistrations** table
6. The **scheduling_preregistrations** table exists in PostgreSQL
7. Both channels are in **STARTED** status

**Important**: Channel 2 must be deployed before Channel 1 is created, so that Channel 2's channel ID is available for the Channel Writer destination in Channel 1.

---

## Verification Strategy

The verifier checks the following independent criteria (100 points total, threshold 70):

| Criterion | Points | Check Method |
|-----------|--------|--------------|
| SIU Intake channel exists with appropriate name | 15 | PostgreSQL `channel` table query |
| SIU channel listens on port 6666 | 5 | XML `<port>` element extraction |
| JS transformer with SIU/SCH field mapping | 20 | Channel XML keyword scan (`SIU`, `SCH`, `ADT`, `channelMap`, `transformedADT`) |
| Channel Writer destination in SIU channel | 20 | XML scan for `ChannelDispatcherProperties` |
| ADT Pre-Registration Processor channel exists | 15 | PostgreSQL `channel` table query |
| ADT channel DB writer for scheduling_preregistrations | 10 | Channel XML scan (`DatabaseDispatcher`, `scheduling_preregistrations`) |
| scheduling_preregistrations table exists | 10 | `information_schema.tables` query |
| Both channels deployed | 5 | `d_channels` table + REST API status for each |

**Do-nothing score**: 0 (no channels or tables pre-created; setup only copies sample messages)

---

## Schema Reference

### PostgreSQL Table (must be created by agent or channel)

```sql
CREATE TABLE IF NOT EXISTS scheduling_preregistrations (
    appt_id        VARCHAR(50),
    patient_mrn    VARCHAR(50),
    patient_name   VARCHAR(200),
    appt_datetime  VARCHAR(50),
    registered_at  TIMESTAMP DEFAULT NOW()
);
```

### HL7 SIU^S12 Relevant Segments

- **MSH-9**: Message Type (`SIU^S12`)
- **SCH-1**: Placer Appointment ID (appointment identifier)
- **SCH-2**: Filler Appointment ID
- **SCH-11**: Appointment Timing Quantity — contains appointment start/end datetime
- **PID-3**: Patient MRN (first repetition, CX.1 component)
- **PID-5**: Patient Name (PID-5.1 = Family, PID-5.2 = Given)
- **PID-7**: Date of Birth
- **PID-8**: Administrative Sex

### Channel Writer Configuration

The Channel Writer destination in NextGen Connect uses class `ChannelDispatcherProperties` and references the target channel by its UUID (`channelId` property). The target channel's ID is obtained after deploying Channel 2:

```bash
curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" \
  https://localhost:8443/api/channels | \
  python3 -c "import sys,json; [print(c['id'], c['name']) for c in json.load(sys.stdin)]"
```

---

## Environment Reference

- **REST API**: `https://localhost:8443/api` (credentials: `admin` / `admin`)
- **Required header**: `X-Requested-With: OpenAPI`
- **PostgreSQL** (direct): `docker exec nextgen-postgres psql -U postgres -d mirthdb`
- **PostgreSQL** (JDBC): `jdbc:postgresql://nextgen-postgres:5432/mirthdb`
- **Sample SIU S12**: `/home/ga/sample_siu_s12.hl7`
- **ADT reference**: `/home/ga/sample_adt_reference.hl7`
- **responseTransformer**: Must be present in every destination connector

---

## Edge Cases and Potential Issues

1. **Build order matters**: Channel 2 (ADT Pre-Registration Processor) must be deployed BEFORE Channel 1 is created. The Channel Writer in Channel 1 references Channel 2's UUID, which only exists after Channel 2 is saved and deployed.

2. **Channel Reader vs. Channel Writer**: Channel 2 uses a **Channel Reader** source connector (not a TCP Listener). This listens on NextGen Connect's internal message bus, not a TCP port. The XML uses `SourceConnector` with `ChannelReaderProperties`.

3. **SCH-11 datetime parsing**: `SCH-11` is a Timing Quantity (TQ) data type. The appointment start datetime is in `SCH-11.4` (Start Date/Time). Access via `msg['SCH']['SCH.11']['SCH.11.4'].toString()`.

4. **ADT^A04 message construction**: When building the ADT message in JavaScript, ensure MSH-9 is set to `ADT^A04` and a PV1 segment with patient class `P` (Pre-Admit) is included.

5. **Channel Writer response**: The Channel Writer destination does not produce an HL7 ACK — it internally routes to Channel 2's queue. If the target channel is not deployed, the Channel Writer will error silently.

6. **Multi-channel architecture complexity**: If Channel 1 is created before Channel 2 is deployed, the Channel Writer will have an invalid or missing channel ID reference, and messages will not route correctly.
