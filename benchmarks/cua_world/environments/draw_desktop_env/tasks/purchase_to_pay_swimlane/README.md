# purchase_to_pay_swimlane — APQC Purchase-to-Pay Process Swimlane

## Domain Context

**Occupation**: Management Analyst ($1.03B top GDP occupation for diagramming tools)

Management Analysts document business processes as swim lane flowcharts to identify inefficiencies, automate workflows, and prepare for ERP implementations. The Purchase-to-Pay (P2P) process is one of the most commonly analyzed cross-functional workflows in corporate finance and procurement — it spans 5+ departments and involves dozens of handoffs, approvals, and exception paths.

The APQC Process Classification Framework (PCF v7.3) defines the canonical P2P process as Source-to-Pay (process group 4.0). This task reflects a real deliverable produced before a SAP/Oracle ERP implementation or during an ISO 9001 audit.

## Task Description

A Management Analyst at a manufacturing firm must document the company's Purchase-to-Pay business process as a swim lane flowchart for a process audit. The process specification is provided at `~/Desktop/p2p_process_spec.txt`.

**End state**: A multi-page draw.io diagram (`~/Desktop/p2p_process.drawio`) and a PDF export (`~/Desktop/p2p_process.pdf`) that contain:
- 5 horizontal swim lanes: Requester, Procurement, Accounts Payable, Supplier, Finance/Treasury
- ≥12 process steps (rounded rectangles) in correct lanes
- ≥3 decision diamonds: budget approval, 3-way matching, payment approval
- ≥2 parallel flow branches (split/join)
- ≥1 exception/rejection path looping back
- Data objects (folded-page shapes) for: Purchase Requisition, Purchase Order, Goods Receipt, Invoice
- A Start event and End event
- A second page titled "KPI Dashboard" with ≥5 P2P KPIs as a table

## Why This Is Hard

- Swim lane diagrams require understanding of draw.io's pool/lane container shapes — not just rectangles
- The agent must map 14 detailed process steps across 5 departments from a specification document
- Decision diamonds (gateways) must be drawn with correct branching logic (yes/no paths)
- Data objects (folded-page shapes) are a distinct shape type in draw.io, not generic rectangles
- Exception paths (rejections looping back) require drawing backward-pointing arrows, which draw.io may route awkwardly
- The PDF export is a distinct export format from PNG — agent must use a different export menu path
- KPI Dashboard requires creating a structured table on a second page, a different task than process mapping

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| File saved after task start | 10 | Required (early exit if missing) |
| ≥18 total shapes | 15 | Partial: 6+ shapes = 6 pts |
| ≥12 total edges | 10 | Partial: 4+ edges = 4 pts |
| ≥4 swim lanes with correct names | 20 | Partial: 2+ lanes = 8 pts, any pool = 4 pts |
| ≥3 decision shapes (rhombus/diamond) | 15 | Partial: 1+ decision = 6 pts |
| Data objects (folded-page shapes) | 10 | — |
| ≥2 diagram pages | 10 | — |
| PDF exported | 10 | — |
| **Total** | **100** | **Pass: ≥60** |

## Verification Strategy

The verifier (`verify_purchase_to_pay_swimlane`):
1. Reads `/tmp/task_result.json` from `export_result.sh`
2. Checks file existence and modification timestamp
3. Detects swim lanes/pools via `swimlane` style attribute in draw.io XML; validates lane labels against required department names (case-insensitive, partial match)
4. Detects decision shapes via `rhombus` style
5. Detects data objects via `shape=mxgraph.flowchart.document` or `foldedPage` or `shape=note`
6. Counts total shapes (vertex) and edges
7. Checks page count and PDF existence

## Data Source

Process specification is based on the APQC Process Classification Framework v7.3, process group 4.0 (Source-to-Pay), and ISO 20022 payment process standards. The 14 process steps reflect real P2P workflows documented in ERP implementation guides (SAP Best Practices, Oracle Cloud Financials).

**5 required swim lanes**:
1. **Requester** — Purchase Requisition creation, goods receipt, 3-way match confirmation
2. **Procurement** — PR approval, PO creation, vendor management, 3-way match initiation
3. **Accounts Payable** — Invoice receipt, 3-way matching, dispute resolution, payment processing
4. **Supplier** — Receive PO, ship goods, submit invoice
5. **Finance/Treasury** — Payment approval, bank transfer, reconciliation

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, scoring hook |
| `setup_task.sh` | Creates `~/Desktop/p2p_process_spec.txt` with APQC-based spec, records start timestamp, launches draw.io blank |
| `export_result.sh` | Parses draw.io XML for swim lane styles, decision shapes, data objects, page count, PDF check |
| `verifier.py` | Multi-criterion scoring function `verify_purchase_to_pay_swimlane` |

## Edge Cases

- Swim lane containers may use the `table` or `group` style instead of `swimlane` — verifier checks all common pool/lane style variants
- Agent may draw separate rectangles as pseudo-lanes rather than using proper swimlane shapes — partial credit awarded if process and edge counts are met
- PDF export in draw.io Desktop requires going to File > Export As > PDF (different from PNG export which is directly accessible) — agents unfamiliar with draw.io may use Print to PDF instead, which is acceptable
- Decision diamonds may be drawn as generic diamonds (`shape=mxgraph.flowchart.decision` or just `rhombus`) — verifier accepts both
