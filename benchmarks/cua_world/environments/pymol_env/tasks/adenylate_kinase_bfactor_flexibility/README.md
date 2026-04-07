# Adenylate Kinase B-factor Flexibility Analysis

## Task Overview

**Difficulty**: Very Hard
**Environment**: PyMOL (pymol_env)
**Professional Context**: Biophysicist studying enzyme conformational dynamics for a catalysis manuscript

## Background

Adenylate kinase (ADK) catalyzes the reaction: ATP + AMP ⇌ 2 ADP. This enzyme undergoes one of the largest conformational changes known for a small protein — the LID domain (residues 118–167) closes over the substrate by ~7 Å, and the AMPbind domain (residues 30–68) moves toward the CORE. These motions are captured by comparing the apo open (4AKE) and holo closed (1AKE) structures.

Crystallographic B-factors (temperature factors) encode per-atom mean-square displacement: B = 8π²⟨u²⟩. High B-factors indicate regions of high thermal motion, which in ADK correlates with the domain flexibility required for catalysis.

- **4AKE**: E. coli ADK, apo open conformation (Müller et al. 1996) — B-factors reflect LID flexibility

## Expected Outputs

1. **`/home/ga/PyMOL_Data/images/adk_bfactor.png`** — High-resolution PNG of the protein colored by B-factor (e.g., blue=rigid, red=flexible spectrum), created using PyMOL's `spectrum b` or `cartoon putty` command

2. **`/home/ga/PyMOL_Data/adk_flexibility_report.txt`** — Plain-text report containing:
   - Top 5 most flexible Cα atoms (residue number + B-factor value)
   - Which structural domain has the highest average B-factor
   - Minimum 5 lines of content

## Domain Definitions

| Domain | Residue Range | Role |
|--------|---------------|------|
| CORE | 1–29, 69–117, 168–214 | Catalytic core, ATP binding |
| AMPbind | 30–68 | AMP binding, closes during catalysis |
| LID | 118–167 | Closes over phosphoryl groups during transfer |

## Verification Criteria (100 pts total)

| Criterion | Points | Check |
|-----------|--------|-------|
| Figure exists, is new, size > 30 KB | 25 | Anti-gaming: timestamp + size gate |
| Report has ≥5 lines | 25 | Top-5 residue requirement |
| Report contains ≥5 distinct residue numbers (1–220) | 25 | Real per-residue data required |
| LID domain mentioned OR ≥3 B-factor values > 30 Å² | 25 | Domain-level analysis required |

**Pass threshold**: 70/100

## Key Scientific Facts

- LID domain B-factors in 4AKE: typically 40–80 Å² (highly mobile)
- CORE domain B-factors: typically 15–30 Å² (well-ordered)
- The large LID mobility is required for efficient substrate binding and product release
- B-factor coloring reveals the catalytically relevant flexible regions directly

## PyMOL Workflow (Outline — Not Given to Agent)

```python
load /home/ga/PyMOL_Data/structures/4AKE.pdb
# Color by B-factor
spectrum b, blue_white_red, chain A, minimum=10, maximum=80
# Or use putty representation for visual clarity
cartoon putty
set cartoon_putty_scale_min, 0.2
set cartoon_putty_scale_max, 2.0
ray 1200, 900
png /home/ga/PyMOL_Data/images/adk_bfactor.png

# Extract B-factors via Python API
stored.bfactors = []
iterate (chain A and name CA), stored.bfactors.append((resi, b))
top5 = sorted(stored.bfactors, key=lambda x: -x[1])[:5]
```
