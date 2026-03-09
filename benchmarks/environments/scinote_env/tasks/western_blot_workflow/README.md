# Western Blot Workflow Documentation

## Task Overview

**Difficulty**: hard
**Domain**: Biochemistry / Protein Analysis
**Occupation Context**: Molecular and Cellular Biologists (top SciNote user occupation)

The agent is given a partially set-up western blot experiment and must complete the ELN documentation by adding tasks, connecting the workflow, adding a protocol, and creating a reagent inventory.

---

## Starting State (Pre-seeded by setup_task.sh)

- **Project**: `Western Blot - p53 Expression Study` (created)
- **Experiment**: `SDS-PAGE Workflow` (created, inside project)
- **Tasks** (created, NOT connected):
  - `Sample Preparation` (left side of canvas)
  - `Detection and Imaging` (right side of canvas, far away)

The gap in the middle represents two missing workflow steps the agent must add.

---

## Goal

Complete the western blot workflow documentation:

1. **Add 2 tasks**: `SDS-PAGE` and `Membrane Transfer` to the `SDS-PAGE Workflow` experiment
2. **Connect all 4 tasks** in order: `Sample Preparation` → `SDS-PAGE` → `Membrane Transfer` → `Detection and Imaging`
3. **Add ≥5 protocol steps** to the `Membrane Transfer` task
4. **Create inventory** `Western Blot Reagents` with columns: `Supplier`, `Catalog Number`, `Lot Number`; add 3 items:
   - `PVDF Membrane` (Supplier: Millipore, Catalog Number: IPVH00010)
   - `5% Non-fat Milk` (Supplier: Bio-Rad, Catalog Number: 1706404)
   - `Anti-beta-actin Antibody` (Supplier: Sigma-Aldrich, Catalog Number: A5441)

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Task 'SDS-PAGE' exists | 7 | New task added to experiment |
| Task 'Membrane Transfer' exists | 8 | New task added to experiment |
| Total ≥4 tasks | 15 | Experiment has all 4 tasks |
| Connection: Sample Prep → SDS-PAGE | 15 | Workflow arrow exists |
| Connection: SDS-PAGE → Membrane Transfer | 15 | Workflow arrow exists |
| Connection: Membrane Transfer → Detection | 10 | Workflow arrow exists |
| Protocol ≥5 steps in Membrane Transfer | 10 | Steps documented |
| Inventory found with ≥3 columns | 10 | Western Blot Reagents inventory |
| 3 items with catalog numbers | 10 | PVDF Membrane, Non-fat Milk, Anti-beta-actin with correct catalogs |

**Pass threshold**: 60/100

---

## Verification Strategy

`export_result.sh`:
- Looks up experiment by project name
- Finds 4 tasks by name patterns (LIKE '%sds%page%', '%membrane%transfer%', etc.)
- Checks specific connections in `connections` table
- Counts steps in Membrane Transfer's protocol
- Queries `Western Blot Reagents` inventory for columns and items with catalog numbers

`verifier.py`:
- Uses fuzzy matching for task and item names
- Checks catalog numbers exactly (case-sensitive)
- Partial credit for having items without correct catalog numbers

---

## Real Data Used

All catalog numbers are genuine:
- PVDF Membrane IPVH00010: Millipore Immobilon-P Transfer Membrane
- 1706404: Bio-Rad Blotting-Grade Blocker (5% non-fat dry milk)
- A5441: Sigma-Aldrich Anti-β-Actin antibody, mouse monoclonal

---

## Edge Cases

- The 4 tasks must be in one experiment (SDS-PAGE Workflow)
- Both new tasks must be created by agent (pre-seeded ones are at x=0 and x=900 on canvas)
- Connections must be directional: left-to-right in the workflow
- Archived tasks are excluded
