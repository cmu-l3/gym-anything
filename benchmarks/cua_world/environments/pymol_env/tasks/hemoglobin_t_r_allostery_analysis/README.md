# Hemoglobin T/R Allostery Analysis

## Task Overview

**Difficulty**: Very Hard
**Environment**: PyMOL (pymol_env)
**Professional Context**: Structural biologist preparing a review article on hemoglobin allostery

## Background

Hemoglobin undergoes a large-scale allosteric transition between the **T-state** (tense/deoxy) and **R-state** (relaxed/oxy) conformations when oxygen binds. This transition, described by the Monod-Wyman-Changeux (MWC) model, involves a ~15° rotation of the αβ dimer pairs and quaternary structural rearrangements. The T315I "gatekeeper" mutation in Abl kinase is a classic drug resistance example; hemoglobin allostery is the classic paradigm for cooperative binding.

- **4HHB**: Human deoxyhemoglobin (T-state), Fermi et al. 1984 — the reference T-state structure
- **1HHO**: Human oxyhemoglobin (R-state), Shaanan 1983 — the reference R-state structure

## Expected Outputs

1. **`/home/ga/PyMOL_Data/images/hemo_superposition.png`** — High-resolution PNG showing both structures superimposed, with the two states colored distinctly to reveal conformational differences

2. **`/home/ga/PyMOL_Data/hemo_rmsd_report.txt`** — Plain-text report containing:
   - The overall RMSD from the structural superposition (Å)
   - References to both PDB IDs (4HHB and 1HHO)
   - Ideally: description of the conformational change

## Verification Criteria (100 pts total)

| Criterion | Points | Check |
|-----------|--------|-------|
| Figure exists, is new (post-task-start), size > 30 KB | 30 | Anti-gaming: timestamp + size gate |
| Report file exists with ≥20 chars of content | 20 | Non-empty check |
| Report contains valid RMSD in range 0.1–6.0 Å | 25 | Physically plausible range check |
| Report mentions both 4HHB and 1HHO | 25 | Both allosteric states required |

**Pass threshold**: 70/100

## Anti-Gaming Measures

- **Timestamp gate**: Stale output files are deleted before the task start timestamp is recorded; the figure must be created AFTER the task begins
- **RMSD range check**: Numbers outside 0.1–6.0 Å cannot satisfy criterion 3, ruling out arbitrary or extreme values
- **Both PDB IDs required**: The report must reference both structures, preventing analysis of only one conformation

## Key Scientific Facts

- Expected RMSD on alpha subunits from T→R transition: ~1–3 Å
- The allosteric transition involves large relative rotation of the α₁β₁ and α₂β₂ dimers
- The 2,3-BPG binding site is only present in the T-state (between the β subunits)
- Key interface residues change contact partners between states: His146β, Asp94β, Lys40α

## PyMOL Workflow (Outline — Not Given to Agent)

```
load /home/ga/PyMOL_Data/structures/4HHB.pdb, tstate
load /home/ga/PyMOL_Data/structures/1HHO.pdb, rstate
align rstate, tstate, object=aln
rmsd_value = cmd.get_raw_alignment('aln')  # or use rms_cur
color marine, tstate
color salmon, rstate
ray 1200, 900
png /home/ga/PyMOL_Data/images/hemo_superposition.png
```
