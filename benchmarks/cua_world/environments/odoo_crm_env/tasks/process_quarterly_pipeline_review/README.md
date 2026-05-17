# process_quarterly_pipeline_review

**Environment**: `odoo_crm_env@0.1`  
**Difficulty**: Medium  
**Task ID**: `process_quarterly_pipeline_review@1`

## Task Description

The agent is a sales operations analyst conducting an end-of-quarter CRM cleanup. The pipeline contains real federal IT contract award data imported from USASpending.gov (NAICS 541512, FY2023, $50K–$500K). Three opportunities in the **Qualified** stage have stalled and require specific actions based on their Internal Notes:

- **Cloud Migration - Weis Markets** — notes describe a failed price negotiation: Azure EA bundle undercut the quote by 24%, and the customer's board threshold on discretionary IT prevents the approval cycle for a counter-offer. Action: mark as **Lost**, reason = `Too Expensive`.

- **ERP Rollout - VSE Corporation** — notes describe a high-risk situation: the VP IT champion announced departure, replacement is from the Aviano Aviation integration team with no enterprise ERP background, and CEO Cuomo flagged cost discipline during the transition. Action: add **At Risk** tag + set **Priority to Low (0 stars)**.

- **Consulting Retainer - Insteel Industries** — notes describe a verbal go-ahead from CFO M. Gazmarian and COO with the deal already in the FY25 capex budget; MSA under legal review. Action: move to **Negotiation** stage + set **Probability to 90%**.

## Data Sources

### Background Pipeline

**Primary** (at setup time): USASpending.gov REST API — `POST https://api.usaspending.gov/api/v2/search/spending_by_award/`
- NAICS 541512 (Computer Systems Design Services), FY2023 (2022-10-01–2023-09-30)
- Definitive contracts, $50K–$500K award range
- Two passes (sorted ascending + descending by amount) → ~190 unique real federal IT awardees
- Raw response saved to `/tmp/crm_background_usa.csv` during setup

**Fallback** (when API unavailable): `data/usaspending_naics541512_fy2023.csv`
- 200 real records from the same USASpending.gov query, downloaded 2026-05-17
- Contains genuine government-data messiness: all-caps recipient names, cryptic scope codes (`IGF::CT::IGF`, `BPA ORDER #N`, `U4xxxxx` IDs), typos, abbreviated descriptions
- Bundled with the task so real data is always available regardless of VM network access

Records are imported into Odoo via `crm.lead.load()` XML-RPC — the same mechanism backing the "Import Records" button in the UI.

**Stage assignment by award amount**:
| Amount range | Stage | Probability |
|---|---|---|
| $50K–$149K | New | 10% |
| $150K–$299K | Qualified | 25% |
| $300K–$449K | Proposition | 45% |
| $450K–$500K | Won | 100% |

### Three Target Opportunities

All situations grounded in real, publicly verifiable company data:

| Company | Verifiable Source | Grounding |
|---------|------------------|-----------|
| Weis Markets (WMK) | 10-K filed 2024-02-29, CIK 0000105418 | Conservative IT capex approach; board threshold for discretionary IT above which separate approval cycle applies |
| Weis Markets (WMK) | Microsoft Cloud for Retail program (partner portal) | Bundled Azure migration pricing for grocery chains |
| VSE Corporation (VSEC) | Aviano Aviation acquisition, April 2022 (press release + FY2022 10-K, CIK 0000102426) | Operational integration introduced new IT leadership; VP IT position affected |
| VSE Corporation (VSEC) | CEO John Cuomo, proxy statements + 10-Ks since 2022 | Documented cost-discipline stance during organizational transitions |
| Insteel Industries (IIIN) | CFO Michael C. Gazmarian, proxy statements + 10-K CIK 0000764401 | Named CFO responsible for capital allocation |
| Insteel Industries (IIIN) | 10-K filed 2023-11-17, MD&A section | FY2024 capital program includes operational technology modernization at manufacturing facilities |

Deal-size benchmarks (all published ranges, no invented values):
- Flexera "2024 State of the Cloud Report" — cloud migration
- Panorama Consulting "2023 ERP Report" — ERP module rollout
- IBIS World "IT Consulting in the US" 2023 — annual retainer

## Verification

`verifier.py::verify_pipeline_review` queries Odoo after the agent completes:

| Check | Points | Criterion |
|-------|--------|-----------|
| Weis Markets marked Lost | 15 | `active = False` |
| Weis Markets lost reason | 15 | `lost_reason_id.name == 'Too Expensive'` |
| VSE Corporation tagged At Risk | 20 | `'At Risk' in tag_ids[*].name` |
| VSE Corporation priority Low | 10 | `priority == '0'` |
| Insteel Industries stage Negotiation | 20 | `stage_id.name == 'Negotiation'` |
| Insteel Industries probability 90% | 20 | `89.9 <= probability <= 90.1` |

**Pass threshold**: ≥ 75 / 100 points.

## Starting State

The agent sees the Odoo CRM pipeline with ~190–200 opportunities across all stages (New, Qualified, Proposition, Won). All background records contain real USASpending.gov PIID numbers in their notes, verifiable at usaspending.gov. The three target opportunities are in the Qualified stage; the agent must navigate to each, read the note, and apply the correct update.
