# Task: Longitudinal Epilepsy Trial — GEE and GLMM Analysis

## Domain Context

**Occupation**: Biomedical Engineer / Biostatistician
**GDP impact**: ~$160M (Bioengineers and Biomedical Engineers using RStudio, ONET importance=93)

Biostatisticians in pharmaceutical clinical trials routinely analyze longitudinal count data from randomized controlled trials. The Thall and Vail (1990) epilepsy dataset is a landmark study that introduced the challenge of overdispersed, correlated count data. It requires choosing between marginal models (GEE) and conditional models (GLMM), understanding working correlation structures, and diagnosing overdispersion.

## Dataset

**Source**: `MASS::epil` — Thall, P.F. and Vail, S.C. (1990). *Some covariance models for longitudinal count data with overdispersion.* Biometrics 46, 657–671.

This is a REAL randomized placebo-controlled trial of the antiepileptic drug progabide. 59 patients, 4 assessment periods of 2 weeks each.

**Columns**:
- `y`: seizure count (outcome)
- `trt`: 0 = placebo, 1 = progabide
- `base`: baseline seizure count (8-week pre-randomization / 4 = per-period baseline)
- `age`: patient age in years
- `V4`: indicator for 4th visit (to capture visit-specific effects)
- `subject`: patient ID (1–59)
- `period`: visit period (1–4)

## Task Requirements

### Deliverable 1: Model Comparison CSV
File: `/home/ga/RProjects/output/seizure_model_comparison.csv`

Required columns:
- `model`: name of model ("poisson_gee_exchangeable", "nb_gee_ar1", etc.)
- `AIC_or_QIC`: model fit statistic
- `treatment_RR`: treatment rate ratio (exp(beta_trt))
- `treatment_RR_lower95`: lower 95% CI
- `treatment_RR_upper95`: upper 95% CI
- `p_value`: p-value for treatment effect

### Deliverable 2: Diagnostics CSV
File: `/home/ga/RProjects/output/seizure_diagnostics.csv`

Required columns:
- `metric`: name of diagnostic metric
- `value`: numeric value

Must include:
- `overdispersion_ratio`: residual deviance / residual df from Poisson GLM
- `ar1_correlation`: estimated AR(1) correlation from GEE with AR-1 structure
- `n_patients`: 59
- `n_observations`: 236 (59 × 4)

### Deliverable 3: Multi-Panel Figure
File: `/home/ga/RProjects/output/seizure_analysis.png`

Must include 3 panels:
- **Panel A**: Mean seizure count over time by treatment group with error bars
- **Panel B**: Individual patient spaghetti plot colored by treatment
- **Panel C**: Forest plot of treatment rate ratios from models

## Verification Strategy

1. Check that both output CSVs exist, were created during the task, and have correct columns
2. Check that treatment RR values are in biologically plausible range (0.3–2.0)
3. Check that overdispersion ratio > 1 (as expected for this overdispersed dataset)
4. Check that the PNG figure exists, is new, and is substantial in size (>30KB)
5. Verify the R script was modified and contains meaningful statistical code
6. VLM verification of the figure quality

## Why This Task Is Hard

1. **Discovery burden**: The agent must identify the correct dataset structure and understand what GEE vs GLMM is appropriate for
2. **Model complexity**: GEE with exchangeable correlation + negative binomial variants require knowing `geepack` API
3. **Multiple independent deliverables**: 2 CSVs + 1 PNG, all requiring different analysis pipelines
4. **Judgment required**: Must decide on correlation structure (exchangeable vs AR-1), link function, overdispersion handling
5. **Domain knowledge**: Understanding the clinical interpretation — is progabide effective?
6. **Multi-panel visualization**: Combining trajectory plots + forest plots requires ggplot2 mastery

## Reference Expected Results

- Overdispersion ratio: ~2.2 (known from the literature)
- Treatment RR (progabide vs placebo): approximately 0.72–0.85 (modest reduction in seizures)
- AR(1) correlation: approximately 0.3–0.5
