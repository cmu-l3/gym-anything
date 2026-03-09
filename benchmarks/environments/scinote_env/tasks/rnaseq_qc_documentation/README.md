# RNA-seq Quality Control Pipeline Documentation

## Task Overview

**Difficulty**: very_hard
**Domain**: Genomics / Transcriptomics
**Occupation Context**: Molecular and Cellular Biologists, Biochemists and Biophysicists

This task requires building a complete RNA-seq QC pipeline ELN from scratch. It combines two separate experiment types (wet-lab library preparation and computational analysis) into one project — reflecting real research lab workflows where both bench scientists and bioinformaticians document their work in the same ELN.

---

## Goal

Create complete ELN documentation for an RNA-seq QC pipeline:

**Project**: `RNA-seq Quality Control Pipeline`

**Experiment 1**: `Library QC Assessment`
- Tasks (in order): `RNA Extraction` → `RNA Quality Assessment` → `Library Preparation` → `Library Quantification`
- All tasks connected in sequence

**Experiment 2**: `Bioinformatics Pipeline`
- Tasks (in order): `Read Trimming` → `Reference Alignment` → `Expression Quantification`
- All tasks connected in sequence

**Protocol**: Add ≥6 steps to `Library Preparation` (fragmentation, first/second strand synthesis, end repair, adapter ligation, PCR amplification)

**Inventory**: Create `RNA-seq Reagents` with 4 columns: `Supplier`, `Catalog Number`, `Concentration`, `Storage Temperature`; add items: `RNeasy Plus Mini Kit`, `KAPA Stranded mRNA-seq Kit`, `ERCC RNA Spike-In Mix`, `DNase I (RNase-free)`

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Project found | 10 | RNA-seq Quality Control Pipeline |
| Library QC Assessment experiment | 8 | Exists in project |
| Bioinformatics Pipeline experiment | 7 | Exists in project |
| 4 tasks in Experiment 1 | 20 | RNA Extraction, Quality Assessment, Library Prep, Quantification (5 pts each) |
| 3 tasks in Experiment 2 | 15 | Read Trimming, Reference Alignment, Expression Quantification (5 pts each) |
| 3 connections in Experiment 1 | 15 | Extract→Quality, Quality→LibPrep, LibPrep→Quant (5 pts each) |
| 2 connections in Experiment 2 | 10 | Trim→Align, Align→Quant (5 pts each) |
| Protocol ≥6 steps | 10 | In Library Preparation task |
| Inventory found | 5 | RNA-seq Reagents |
| ≥4 columns | 5 | Supplier, Catalog Number, Concentration, Storage Temperature |
| 4 items in inventory | 5 | RNeasy, KAPA, ERCC, DNase I |

**Pass threshold**: 60/100

---

## Starting State

Blank SciNote instance — agent creates everything from scratch.

---

## Verification Strategy

`export_result.sh`:
- Finds project by exact name match
- Finds Experiment 1 via LIKE '%library%qc%' and Experiment 2 via LIKE '%bioinformat%'
- Finds 7 tasks total across 2 experiments by name patterns
- Checks 5 specific connections (output_id, input_id)
- Counts steps in Library Preparation protocol
- Finds inventory and checks 4 items by keyword matching (rneasy, kapa, ercc, dnase)

---

## Real Data Used

All reagents are genuine commercial products used in RNA-seq workflows:
- RNeasy Plus Mini Kit (Qiagen 74134) - gold standard RNA extraction
- KAPA Stranded mRNA-seq Kit (Roche) - industry standard library prep
- ERCC RNA Spike-In Mix (Thermo Fisher 4456740) - QC standard
- DNase I RNase-free (Qiagen 79254) - gDNA removal

---

## Edge Cases

- Two separate experiments required (wet-lab + bioinformatics)
- Task name matching: 'Library QC Assessment' uses '%library%qc%' pattern
- Experiment 2 uses '%bioinformat%' which matches both 'Bioinformatics Pipeline' and 'Bioinformatic Pipeline'
- Partial credit for having only some connections
