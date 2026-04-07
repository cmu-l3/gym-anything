# H-Ras p21 Nucleotide Binding Analysis

## Task Overview

**Difficulty**: Very Hard
**Environment**: PyMOL (pymol_env)
**Professional Context**: Cancer biologist / medicinal chemist at a research institute studying RAS oncogene inhibition

## Background

RAS GTPases (H-Ras, K-Ras, N-Ras) are the most frequently mutated oncogenes in human cancers (~30% of all cancers). The G12V mutation (and G12D, G12C) at Glycine 12 impairs the intrinsic GTP hydrolysis rate by ~1000-fold, locking Ras in the active GTP-bound state and constitutively activating downstream proliferation signals (RAF/MEK/ERK, PI3K/AKT).

**PDB:5P21** — Human H-Ras p21 in complex with GppNHp (the non-hydrolyzable GTP analog, ligand code GNP), at 1.35 Å resolution. This structure reveals why G12 cannot be mutated without disrupting catalysis: G12 sits directly adjacent to the gamma-phosphate, and any substitution causes steric clash with Gln61 or the catalytic water.

## Expected Outputs

1. **`/home/ga/PyMOL_Data/images/ras_nucleotide.png`** — High-resolution PNG showing GNP in the binding site with surrounding protein residues as sticks and protein as cartoon

2. **`/home/ga/PyMOL_Data/ras_binding_report.txt`** — Binding analysis report containing:
   - Distance from G12 Cα to GNP gamma-phosphate (PG atom) in Angstroms
   - Total count of protein residues within 3.5 Å of GNP
   - List of those residue names/numbers

## Verification Criteria (100 pts total)

| Criterion | Points | Check |
|-----------|--------|-------|
| Figure exists, is new, size > 30 KB | 25 | Anti-gaming: timestamp + size gate |
| G12-GNP distance in range 3.0–8.0 Å | 25 | Physically plausible distance check |
| ≥5 distinct residue numbers (1–170) in report | 25 | Real binding site analysis required |
| ≥2 known key binding residues (G10, G12, G13, K16, T35, G60, Q61) | 25 | Cannot pass with random residue list |

**Pass threshold**: 70/100

## Key GTP-Binding Residues (from 5P21)

| Residue | Role |
|---------|------|
| G10, G12, G13 | P-loop (phosphate-binding loop) |
| K16 | P-loop, contacts beta/gamma phosphate |
| T35 | Switch I, contacts gamma-phosphate + Mg²⁺ |
| G60 | Switch II |
| Q61 | Switch II, positions catalytic water |
| E63 | Switch II |
| N116, D119 | Guanine recognition |

## G12 to GNP Distance

In 5P21, the Cα of Gly12 is approximately 4.0–5.5 Å from the gamma-phosphate (PG) of GNP. This close proximity explains why mutations at G12 cause steric interference with the catalytic mechanism.

## PyMOL Workflow (Outline — Not Given to Agent)

```python
load /home/ga/PyMOL_Data/structures/5P21.pdb

# Show binding site
show cartoon, polymer
show sticks, resn GNP
show sticks, polymer within 3.5 of resn GNP
color white, polymer
color yellow, resn GNP
color red, resi 12

# Measure G12 Cα to GNP PG distance
distance g12_to_gnp, (resi 12 and name CA), (resn GNP and name PG)

ray 1200, 900
png /home/ga/PyMOL_Data/images/ras_nucleotide.png
```
