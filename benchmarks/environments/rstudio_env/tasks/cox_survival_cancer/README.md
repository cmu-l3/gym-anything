# Cox Survival Cancer Task

## Overview

A clinical biostatistician analyzes data from the **German Breast Cancer Study Group (GBSG2)**
randomized trial to evaluate prognostic factors for disease-free survival in primary
node-positive breast cancer patients. The dataset (686 patients) is available via the
`TH.data` R package.

**Occupation:** Clinical Biostatistician / Oncology Researcher
**Difficulty:** very_hard
**Dataset:** GBSG2 (TH.data package) — real randomized trial data

---

## Dataset

| Field | Details |
|-------|---------|
| Source | TH.data::GBSG2 |
| Reference | Schumacher M et al. (1994). *Journal of the Royal Statistical Society*, Series C |
| N | 686 patients |
| Endpoint | Disease-free survival (time, cens) |
| Covariates | horTh, tsize, pnodes, progrec, estrec, menostat, tgrade |

### Variables

- `horTh` — hormonal therapy: yes/no (key treatment variable; expected protective effect)
- `tsize` — tumor size in mm
- `pnodes` — number of positive lymph nodes
- `progrec` — progesterone receptor (fmol/l)
- `estrec` — estrogen receptor (fmol/l)
- `menostat` — menopausal status: pre/post
- `tgrade` — tumor grade: I/II/III
- `time` — recurrence-free survival time (days)
- `cens` — censoring indicator (1 = event, 0 = censored)

---

## Task Goal

Produce four deliverables:

1. **Cox PH model results** (`gbsg_cox_results.csv`)
   Columns: `covariate`, `hazard_ratio`, `hr_lower95`, `hr_upper95`, `p_value`, `significant`
   Expected: `horTh` HR ≈ 0.7 (protective), `pnodes` HR > 1 (risk factor)

2. **PH assumption test** (`gbsg_ph_test.csv`)
   Columns: `covariate`, `chisq`, `df`, `p_value`, `ph_violated`
   Use `cox.zph()` from the survival package; check each covariate + global test

3. **Kaplan-Meier curves** (`gbsg_km_curves.png`)
   Stratified by `horTh` (yes vs no) using `survminer::ggsurvplot`
   Must include: risk table, log-rank p-value, confidence bands

4. **Forest plot** (`gbsg_forest_plot.png`)
   Hazard ratios with 95% CIs for all 7 covariates
   Can use `survminer::ggforest` or manual ggplot2 implementation

---

## Expected Results

| Covariate | Expected HR | Direction |
|-----------|-------------|-----------|
| horTh     | ~0.65–0.80 | Protective |
| pnodes    | >1.0       | Risk factor |
| progrec   | <1.0       | Mild protective |
| tsize     | >1.0       | Risk factor |
| tgrade    | >1.0       | Higher grade = worse |

---

## Verification Strategy

### Criterion 1: Cox Results CSV (30 pts)
- File exists and has mtime after task start (10 pts)
- Has hazard_ratio column (5 pts)
- Has p_value column (5 pts)
- `horTh` HR in plausible range 0.3–1.2 (10 pts)

### Criterion 2: PH Test CSV (20 pts)
- File exists and is new (10 pts)
- Has chi-sq statistic column (10 pts)
- Expect ≥8 rows (7 covariates + 1 global)

### Criterion 3: KM Curves PNG (25 pts)
- File exists and is new (10 pts)
- Valid PNG header (5 pts)
- File size ≥ 80KB (risk table likely present) (10 pts)

### Criterion 4: Forest Plot PNG (25 pts)
- File exists and is new (10 pts)
- Valid PNG header (5 pts)
- File size ≥ 30KB (10 pts)

**Score cap gates**: PH test CSV and KM PNG are required deliverables; missing either caps score at 59 (below pass threshold of 60).

**VLM bonus**: Up to 10 additional points from visual inspection of RStudio screenshot.

---

## Edge Cases

- `pnodes` and `progrec`/`estrec` are highly skewed — agents may log-transform, which is acceptable
- Forest plot may be produced via `survminer::ggforest(cox_model)` or custom ggplot2
- KM curves stratified by `horTh` is specified; agents using other stratifications get partial credit for file existence only
- `cox.zph()` tests may show some covariates violating PH assumption (pnodes sometimes does)
