# Antibody-Antigen Interface Mapping

## Task Overview

**Difficulty**: Very Hard
**Environment**: PyMOL (pymol_env)
**Professional Context**: Structural biologist at a biotherapeutics company, epitope engineering project

## Background

PDB:1DVF contains the D1.3 antibody Fab fragment in complex with hen egg-white lysozyme (HEL), determined at 1.8 Å resolution (Bhat et al. 1994). This is one of the canonical antibody-antigen complexes used in structural immunology — D1.3 was the first antibody whose crystal structure was determined. The D1.3/HEL interface is well-characterized and serves as a benchmark for computational epitope mapping methods.

**Chain layout:**
- Chain A: VH (heavy variable domain)
- Chain B: VL (light variable domain)
- Chain C: Hen egg-white lysozyme (antigen)

## Expected Outputs

1. **`/home/ga/PyMOL_Data/images/dvf_interface.png`** — High-resolution PNG showing the antibody-antigen interface with epitope (chain C residues at interface) and paratope (chains A/B residues at interface) colored distinctly

2. **`/home/ga/PyMOL_Data/dvf_interface_report.txt`** — Interface summary containing:
   - Total contact count (atoms within 4.0 Å between antibody and antigen)
   - Epitope residues (chain C residues within 4 Å of antibody)
   - At least 3 specific contact pairs in format `chainX:RESI -- chainY:RESI`

## Known Epitope

The D1.3 epitope on lysozyme (chain C) includes: **Gln18, Ser21, Asn22, Ser43, Asn45, Asp96, Pro97, Ala98, Asp99, Gly116, Asn117, Trp118, Val119, Ala120**

## Verification Criteria (100 pts total)

| Criterion | Points | Check |
|-----------|--------|-------|
| Figure exists, is new, size > 30 KB | 25 | Anti-gaming: timestamp + size gate |
| Report contains ≥3 chain:residue contact pairs | 25 | Explicit contact pair format required |
| ≥4 known epitope residues identified (from chain C) | 25 | Real epitope check against literature |
| Report states a plausible total contact count (5–200) | 25 | Quantitative interface characterization |

**Pass threshold**: 70/100

## PyMOL Workflow (Outline — Not Given to Agent)

```python
load /home/ga/PyMOL_Data/structures/1DVF.pdb

# Define interface selections
select epitope, chain C within 4.0 of (chain A or chain B)
select paratope, (chain A or chain B) within 4.0 of chain C

# Visualize
color white, all
color red, epitope
color blue, paratope
show surface, all
ray 1200, 900
png /home/ga/PyMOL_Data/images/dvf_interface.png

# Count contacts using Python API
stored.contacts = []
iterate_state 1, epitope, stored.contacts.append((chain, resi, resn))
```
