# microservices_dependency_audit — Audit and Complete Broken Microservices Diagram

## Domain Context

**Occupation**: Computer Systems Analyst ($2.5B top GDP occupation for diagramming tools)

Systems Analysts at software companies regularly audit and maintain architecture diagrams as services are added, renamed, or redeployed. A partial or incorrect architecture diagram is more dangerous than none at all — it misleads developers about dependencies, causes incorrect capacity planning, and can result in missing circuit breakers or security boundaries.

This task reflects a realistic "inherited diagram" scenario: a junior engineer started a microservices architecture diagram, got it wrong, and left it incomplete. A senior analyst must audit the diagram against the authoritative service catalog, fix the errors, add missing services, and produce a complete dependency map.

## Task Description

A Systems Analyst at a fintech company receives a partial microservices architecture diagram (`~/Diagrams/microservices_partial.drawio`) that shows only 3 of 9 services and contains deliberate errors. The authoritative service catalog is at `~/Desktop/service_catalog.yaml`.

**End state**: A corrected, complete diagram (`~/Desktop/microservices_architecture.drawio`) and SVG export (`~/Desktop/microservices_architecture.svg`) that contain:
- All 9 services: api-gateway, customer-service, notification-service, payment-service, fraud-detection-service, ledger-service, checkout-service, order-service, reporting-service
- All service-to-service dependencies as directed arrows labeled with protocols (REST, gRPC, AMQP)
- Error corrections: wrong connections removed/relabeled, tech stacks fixed
- 3 domain groups: Customer Domain, Payment Domain, Operations Domain
- Technology stack label on each service box
- A second page "Dependency Matrix" showing a 9×9 table with 'X' marks for dependencies

## Why This Is Hard

- The agent must actively compare the partial diagram against the YAML catalog to identify discrepancies (discovery, not just execution)
- The partial diagram has red "WRONG" labels on incorrect connections — these must be identified and removed
- Wrong tech stacks on 2 services must be detected and corrected by reading the service_catalog.yaml
- 6 missing services must be added with correct names, tech stacks, and connection topology
- Services must be grouped into the 3 correct domains (requires reading the catalog's domain field)
- The Dependency Matrix page requires reasoning about the full dependency graph and expressing it as a table
- An anti-copy-paste check verifies the output is NOT a copy of the partial file (MD5 comparison)

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| File saved & differs from partial | 10 | Mandatory: copy of partial = score 0 |
| ≥7 of 9 service names in diagram | 25 | Partial: 5+ = 12 pts, 3+ = 4 pts |
| ≥10 edges with protocol labels | 20 | Partial: 4+ edges = 8 pts, 2+ = 3 pts |
| ≥3 domain groups present | 15 | Partial: 1+ domain = 5 pts |
| Errors fixed (WRONG labels removed) | 15 | Partial: some removed = 12 pts, etc. |
| ≥2 diagram pages | 10 | — |
| SVG exported | 5 | — |
| **Total** | **100** | **Pass: ≥60** |

## Verification Strategy

The verifier (`verify_microservices_dependency_audit`):
1. Reads `/tmp/task_result.json` from `export_result.sh`
2. **Mandatory check**: Output file MD5 must NOT match the partial starter file MD5 (stored at `/tmp/partial_md5`)
3. Checks file existence and modification timestamp
4. Counts service names detected via case-insensitive matching of service names and their aliases (e.g., "api-gateway" / "api_gateway" / "gateway")
5. Counts edges with protocol labels (REST, gRPC, AMQP, HTTP, Queue, etc.)
6. Counts domain group containers (swimlane/group shapes with domain name labels)
7. Checks whether "WRONG" labels are absent from the output (error correction)
8. Checks page count and SVG file existence

## Data Source

Service topology adapted from Google's Online Boutique (hipster-shop) microservices demo application (Apache 2.0 license, github.com/GoogleCloudPlatform/microservices-demo), adapted for a fintech context.

**9 services and their domains**:

| Service | Domain | Tech Stack | Key Dependencies |
|---------|--------|------------|-----------------|
| api-gateway | Operations | Node.js/Express | → customer-service, checkout-service |
| customer-service | Customer | Python/FastAPI | → notification-service |
| notification-service | Customer | Python/FastAPI | (outbound email/SMS) |
| payment-service | Payment | Go/gRPC | → fraud-detection-service, ledger-service |
| fraud-detection-service | Payment | Python/TensorFlow | → ledger-service |
| ledger-service | Payment | Java/Spring Boot | (persistence) |
| checkout-service | Operations | Go/gRPC | → payment-service, order-service |
| order-service | Operations | Node.js/Express | → notification-service, reporting-service |
| reporting-service | Operations | Python/Pandas | → ledger-service |

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, scoring hook |
| `setup_task.sh` | Copies `microservices_partial.drawio` to `~/Diagrams/`, creates `~/Desktop/service_catalog.yaml`, records MD5 of partial and start timestamp, launches draw.io with partial file |
| `export_result.sh` | Parses output draw.io XML, counts services/edges/domains, checks for WRONG labels, compares MD5 |
| `verifier.py` | Multi-criterion scoring function `verify_microservices_dependency_audit` |
| `../../assets/diagrams/microservices_partial.drawio` | Starter diagram (3/9 services, 2 wrong connections) |

## Edge Cases

- An agent might copy the partial file as the output without editing — the MD5 anti-copy check catches this and returns score=0 regardless of other criteria
- The "WRONG" labels are explicitly placed on incorrect edges in the partial diagram — verifier checks for presence/absence of the string "WRONG" in edge labels
- Domain groups may be implemented as swimlane containers OR as rectangle outlines with text labels — verifier accepts both
- Service names may appear with hyphens, underscores, or spaces — verifier uses flexible alias matching
- Tech stacks may be placed in shape tooltips, inside the shape, or as a separate label — verifier does keyword matching across all text content
