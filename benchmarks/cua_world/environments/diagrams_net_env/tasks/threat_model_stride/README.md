# Task: threat_model_stride

**ID**: threat_model_stride@1
**Difficulty**: very_hard
**Occupation**: Information Security Engineers ($484M GDP impact)
**Timeout**: 900 seconds | **Max Steps**: 100

## Domain Context

Information security engineers use STRIDE (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege) threat modeling as a systematic methodology to identify security threats in software systems. Formal threat models include trust boundary zones on data flow diagrams and a structured threat enumeration table. This is standard practice in secure software development lifecycles (Microsoft SDL, OWASP, NIST SP 800-30).

## Task Goal

Perform a complete STRIDE threat model analysis on a pre-drawn OAuth 2.0 Data Flow Diagram (`~/Diagrams/oauth_threat_model.drawio`). Using the methodology reference in `~/Desktop/stride_reference.txt`, the agent must: add trust boundary zones (External/DMZ/Internal), annotate components with STRIDE threat categories, apply risk-level color coding, create a second threat enumeration page, and export as SVG + PDF.

## What Makes This Hard

1. **Security domain knowledge**: Must know which OAuth components belong in which trust zones
2. **STRIDE methodology**: Must correctly apply all 6 threat categories to appropriate elements
3. **Multi-page creation**: Must create threat table as a second diagram page
4. **Judgment required**: Must assess risk levels (high/medium/low) for each threat
5. **Multiple output formats**: SVG (DFD page) + PDF (all pages)
6. **Risk classification**: Color coding requires understanding relative threat severity

## Success Criteria

| Criterion | Points |
|-----------|--------|
| File modified after task start | 10 |
| Second page (Threat Enumeration) created | 15 |
| Trust boundary zones ≥ 2 | 20 |
| STRIDE annotations on ≥ 3 components | 15 |
| Risk level color coding (red/orange/green) | 15 |
| Threat table with structured content | 15 |
| SVG exported | 5 |
| PDF exported | 5 |

**Pass threshold**: 60 points

## Starting State

- `~/Diagrams/oauth_threat_model.drawio`: OAuth 2.0 DFD with 5 processes, 3 data stores, and 10 data flows — NO trust boundaries, NO threat annotations
- `~/Desktop/stride_reference.txt`: STRIDE methodology guide, trust zone definitions, threat table format

## Components in Starting DFD

- Mobile App Client (external)
- Authorization Server (Node.js / JWT)
- Resource Server (Python / Flask)
- User Database (PostgreSQL)
- Token Store (Redis)
- Audit Log (Elasticsearch)
- 10 labeled data flows between components
