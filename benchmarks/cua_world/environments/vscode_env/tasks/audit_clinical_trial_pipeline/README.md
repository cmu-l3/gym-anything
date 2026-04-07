# Audit Clinical Trial Pipeline

## Scenario

A pharmaceutical company is preparing an NDA (New Drug Application) submission
for drug candidate PX-4127, a Phase III clinical trial for moderate-to-severe
chronic pain.  The statistical analysis pipeline has been flagged by the quality
assurance team as containing methodology errors that would cause the FDA to
reject the submission.

The agent must audit the entire Python analysis pipeline, identify all
statistical and regulatory compliance errors, and fix them before the
submission deadline.

## Occupation

**Biostatistician** (SOC 19-1011.00) -- Pharmaceutical Industry

## Skills Tested

- Statistical analysis methodology (hypothesis testing, confidence intervals)
- FDA regulatory compliance knowledge (ICH E9, ITT principle)
- Adverse event reporting standards
- Multiple comparisons / multiplicity adjustment
- Python scientific computing (NumPy, SciPy, pandas)
- Code auditing and debugging

## Workspace

`/home/ga/workspace/clinical_trial_analysis/`

| File | Purpose |
|------|---------|
| `config.py` | Trial configuration and statistical parameters |
| `analysis/data_loader.py` | Data loading and ITT population derivation |
| `analysis/primary_endpoint.py` | Primary efficacy endpoint analysis |
| `analysis/safety_analysis.py` | Adverse event incidence analysis |
| `analysis/subgroup_analysis.py` | Pre-specified subgroup analyses |
| `analysis/report_generator.py` | CSR summary report generation |
| `run_analysis.py` | Main pipeline entry point |

## Difficulty

**Very Hard** -- requires domain-specific biostatistics knowledge and the
ability to identify subtle statistical methodology errors embedded in
otherwise well-structured code.

## Verification

The verifier checks whether each identified bug has been correctly fixed.
Scoring is based on the number of errors found and resolved (pass threshold:
60/100).
