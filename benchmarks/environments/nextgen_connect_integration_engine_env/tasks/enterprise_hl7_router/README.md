# enterprise_hl7_router

**Difficulty**: Very Hard
**Occupation**: Integration Architect / IT Project Manager (SOC 15-1299.09)
**Domain**: Enterprise Healthcare Integration, HL7 Message Routing Architecture

---

## Domain Context

Integration Architects at large regional health systems design the HL7 message routing infrastructure that connects dozens of external systems (labs, pharmacies, imaging centers, specialty clinics) to the core EHR. A key architectural pattern is the **routing facade**: a single "front door" endpoint that all external systems connect to, with intelligent routing to the correct downstream processing channel based on message characteristics.

This pattern provides:
- **Operational simplicity**: External systems only need to know one endpoint
- **Flexibility**: Routing logic can be updated without changing external system configurations
- **Auditability**: All messages flow through one point, enabling centralized logging
- **Resilience**: Unroutable messages land in a Dead Letter Queue (DLQ) for manual review rather than being silently dropped

The routing rules are maintained in a database table (`routing_rules`) so they can be updated by operations staff without redeploying channels. NextGen Connect's Channel Writer destination enables inter-channel routing, and JavaScript filter scripts on each destination provide the conditional logic.

---

## Goal

Build a three-channel enterprise HL7 routing solution:

**Channel 1 — Enterprise HL7 Router** (the facade): Receives all incoming HL7 messages on a single port. Examines MSH-3 (Sending Application) and MSH-9 (Message Type) to determine routing. Routes ORU/Lab messages to Channel 2, ADT messages to Channel 3, and all unmatched messages to a Dead Letter Queue database table.

**Channel 2 — Lab Results Processor**: Receives lab result messages from Channel 1 via Channel Writer. Stores incoming messages in the `lab_results_inbox` table.

**Channel 3 — ADT Event Handler**: Receives ADT messages from Channel 1 via Channel Writer. Stores incoming messages in the `adt_events_inbox` table.

A `routing_rules` table is pre-seeded in PostgreSQL during setup with routing rules for the system.

---

## Success Criteria

The task is complete when:

1. A channel named **Enterprise HL7 Router** is deployed, listening on **TCP port 6668** via MLLP
2. The facade channel contains a **JavaScript transformer** that extracts MSH-3 (Sending Application) and MSH-9 (Message Type) and sets channel map routing variables
3. The facade channel has **two Channel Writer destinations** with JavaScript filter scripts — one routing ORU/Lab messages to Channel 2, one routing ADT messages to Channel 3
4. The facade channel has a **Database Writer destination** (no filter) that writes unmatched messages to **dead_letter_queue**
5. A channel named **Lab Results Processor** is deployed with a Database Writer to **lab_results_inbox**
6. A channel named **ADT Event Handler** is deployed with a Database Writer to **adt_events_inbox**
7. The **routing_rules** table exists with at least 2 seeded rules
8. All three destination tables exist: `dead_letter_queue`, `lab_results_inbox`, `adt_events_inbox`
9. All three channels are in **STARTED** status

**Important**: Channels 2 and 3 must be deployed before Channel 1 is created, so their channel IDs are available for the Channel Writer destinations.

---

## Verification Strategy

The verifier checks the following independent criteria (100 points total, threshold 70):

| Criterion | Points | Check Method |
|-----------|--------|--------------|
| Facade channel exists with appropriate name + port 6668 | 15 | PostgreSQL `channel` table query + XML `<port>` |
| JS transformer with MSH-3/MSH-9 extraction | 15 | Channel XML keyword scan (`MSH`, `sendingApp`, `messageType`, `channelMap`) |
| Two Channel Writer destinations in facade | 20 | XML count of `ChannelDispatcherProperties` occurrences |
| DLQ Database Writer in facade (dead_letter_queue) | 10 | Channel XML scan (`DatabaseDispatcher`, `dead_letter_queue`) |
| Lab Results Processor channel exists + DB writer | 10 | Channel table query + XML scan (`lab_results_inbox`) |
| ADT Event Handler channel exists + DB writer | 10 | Channel table query + XML scan (`adt_events_inbox`) |
| routing_rules table exists with ≥2 rules | 10 | `information_schema.tables` + `SELECT COUNT(*)` |
| All three channels deployed | 10 | `d_channels` table + REST API status for each |

**Do-nothing score**: 0 — although routing_rules table and DLQ/inbox tables are pre-created by setup, no channels are created; channel existence is gated before any points are awarded.

---

## Schema Reference

### Pre-seeded routing_rules Table (created by setup_task.sh)

```sql
CREATE TABLE routing_rules (
    rule_id      SERIAL PRIMARY KEY,
    rule_name    VARCHAR(100) NOT NULL,
    sending_app_pattern   VARCHAR(100),
    message_type_pattern  VARCHAR(50),
    destination_channel   VARCHAR(200) NOT NULL,
    priority     INTEGER DEFAULT 1,
    is_active    BOOLEAN DEFAULT TRUE,
    created_at   TIMESTAMP DEFAULT NOW()
);
-- Seeded with 4 rules: LabSystem→Lab Results Processor, ADT→ADT Event Handler, etc.
```

### Pre-created Destination Tables (created by setup_task.sh)

```sql
CREATE TABLE dead_letter_queue (
    message_id    VARCHAR(100),
    sending_app   VARCHAR(200),
    message_type  VARCHAR(50),
    raw_message   TEXT,
    received_at   TIMESTAMP DEFAULT NOW()
);

CREATE TABLE lab_results_inbox (
    message_id    VARCHAR(100),
    patient_mrn   VARCHAR(50),
    test_code     VARCHAR(100),
    received_at   TIMESTAMP DEFAULT NOW()
);

CREATE TABLE adt_events_inbox (
    message_id    VARCHAR(100),
    patient_mrn   VARCHAR(50),
    event_type    VARCHAR(50),
    received_at   TIMESTAMP DEFAULT NOW()
);
```

### HL7 MSH Routing Fields

- **MSH-3**: Sending Application (identifies the source system, e.g., `LabSystem`, `RegistrationSystem`)
- **MSH-9**: Message Type (e.g., `ORU^R01`, `ADT^A01`) — MSH-9.1 is the event type prefix (`ORU`, `ADT`)

To access in NextGen Connect JavaScript:
```javascript
var sendingApp = msg['MSH']['MSH.3']['MSH.3.1'].toString();
var messageType = msg['MSH']['MSH.9']['MSH.9.1'].toString();
channelMap.put('sendingApp', sendingApp);
channelMap.put('messageType', messageType);
```

---

## Environment Reference

- **REST API**: `https://localhost:8443/api` (credentials: `admin` / `admin`)
- **Required header**: `X-Requested-With: OpenAPI`
- **PostgreSQL** (direct): `docker exec nextgen-postgres psql -U postgres -d mirthdb`
- **PostgreSQL** (JDBC): `jdbc:postgresql://nextgen-postgres:5432/mirthdb`
- **routing_rules already seeded**: `SELECT * FROM routing_rules;` in mirthdb
- **Sample messages**: `/home/ga/sample_adt_a01.hl7`, `/home/ga/sample_oru_lab.hl7`, `/home/ga/sample_oru_normal.hl7`
- **Get channel IDs after creating**: `curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" https://localhost:8443/api/channels`
- **responseTransformer**: Must be present in every destination connector

---

## Edge Cases and Potential Issues

1. **Build order is critical**: Channels 2 and 3 must be deployed first. The Channel Writer destinations in Channel 1 reference Channels 2 and 3 by their UUIDs. Create and deploy Channel 2 (Lab Results Processor) → get its ID. Create and deploy Channel 3 (ADT Event Handler) → get its ID. Then create Channel 1 using both IDs.

2. **Channel Writer filter logic**: Each Channel Writer destination needs a JavaScript filter script that evaluates the channel map variables set by the transformer. Example for lab routing:
   ```javascript
   // Filter for Lab Results Processor destination
   var msgType = $('messageType');
   var sendApp = $('sendingApp');
   return msgType.startsWith('ORU') || sendApp.toLowerCase().indexOf('lab') >= 0;
   ```

3. **DLQ destination has no filter**: The Database Writer for `dead_letter_queue` must have NO filter script (or filter returns `true` always). It acts as the default catch-all. However, if both Channel Writer filters match, all three destinations fire. To make DLQ truly "unmatched only", use a filter that returns `!(matchesLab || matchesADT)`.

4. **Three-channel coordination overhead**: This is the most architecturally complex task. Debugging requires checking each channel's message statistics independently via the REST API or web dashboard.

5. **Channel Reader in Channels 2 and 3**: Channels 2 and 3 use Channel Reader sources (not TCP Listeners). They receive messages via NextGen Connect's internal routing bus, not external TCP connections.

6. **routing_rules table is pre-seeded**: The `routing_rules` table already has 4 rules from setup. The agent does not need to re-seed it, but can add additional rules. The verifier checks for ≥2 rules existing.

7. **Message count validation**: To test routing, send MLLP messages of different types to port 6668 after all three channels are deployed. Use `curl` or `nc` with proper MLLP framing (`0x0B` start, `0x1C 0x0D` end).
