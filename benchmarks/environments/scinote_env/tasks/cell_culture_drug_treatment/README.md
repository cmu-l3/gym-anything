# Cell Culture Drug Treatment Study Documentation

## Task Overview

**Difficulty**: hard
**Domain**: Cancer Biology / Pharmacology
**Occupation Context**: Molecular and Cellular Biologists, Biochemists and Biophysicists

An in-vitro drug dose-response study is partially documented in SciNote. The agent must complete the workflow, add the missing drug treatment and analysis tasks, document the treatment protocol, and populate the drug stock inventory.

---

## Starting State (Pre-seeded by setup_task.sh)

- **Project**: `HeLa Cell Doxorubicin Dose Response` (created)
- **Experiment**: `Dose Response Analysis` (created, inside project)
- **Tasks** (created, NOT connected):
  - `Cell Seeding` (left side of canvas)
  - `Cell Viability Assay` (right side of canvas, far away)
- **Inventory**: `Drug Stocks` (created) with 1 column: `Concentration (μM)` — but **no items**

---

## Goal

Complete the dose-response study documentation:

1. **Add 2 tasks**: `Drug Treatment` and `Data Analysis` to the `Dose Response Analysis` experiment
2. **Connect all 4 tasks** in order: `Cell Seeding` → `Drug Treatment` → `Cell Viability Assay` → `Data Analysis`
3. **Add ≥5 protocol steps** to the `Drug Treatment` task (drug dilution, media removal, drug addition, incubation, documentation)
4. **Expand inventory**: Add 2 more columns to `Drug Stocks`: `Solvent` and `Storage Conditions`
5. **Add 3 drug items** with all fields filled:
   - `Doxorubicin` (Concentration: 10000 μM, Solvent: DMSO, Storage: -20°C protected from light)
   - `Cisplatin` (Concentration: 3330 μM, Solvent: Saline, Storage: -20°C)
   - `Paclitaxel` (Concentration: 10000 μM, Solvent: DMSO, Storage: -20°C protected from light)

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Task 'Drug Treatment' exists | 8 | New task added |
| Task 'Data Analysis' exists | 7 | New task added |
| Total ≥4 tasks | 10 | All 4 tasks present |
| Connection: Cell Seeding → Drug Treatment | 15 | Workflow arrow |
| Connection: Drug Treatment → Cell Viability | 15 | Workflow arrow |
| Connection: Cell Viability → Data Analysis | 10 | Workflow arrow |
| Protocol ≥5 steps in Drug Treatment | 10 | Steps documented |
| Column 'Solvent' added | 5 | New inventory column |
| Column 'Storage Conditions' added | 5 | New inventory column |
| 3 drug items with solvent data | 15 | 3 pts item + 2 pts correct solvent (×3) |

**Pass threshold**: 60/100

---

## Verification Strategy

`export_result.sh`:
- Finds experiment by project name
- Finds 4 tasks by LIKE patterns (drug%treat, data%anal, cell%seed, cell%viab)
- Checks 3 specific connections
- Counts Drug Treatment protocol steps
- Finds Drug Stocks inventory, checks for 'solvent' and 'storage' columns
- Retrieves 3 drug items with concentration and solvent cell values

---

## Real Data Used

All drugs are genuine anticancer agents used in clinical and preclinical research:
- Doxorubicin (Adriamycin): anthracycline antibiotic, commonly dissolved in DMSO at 10 mM (10000 μM) stock
- Cisplatin: platinum-based agent, prepared in saline at ~3.33 mM
- Paclitaxel (Taxol): taxane, dissolved in DMSO at 10 mM stock

---

## Edge Cases

- Drug Stocks inventory pre-exists with 1 column; agent must add 2 more
- Connection order is important: Cell Seeding is the first step, Data Analysis is last
- Solvent values are compared case-insensitively (DMSO vs dmso)
- Partial credit for finding items without correct solvent data
