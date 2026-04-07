#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Audit Clinical Trial Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/clinical_trial_analysis"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/analysis"

# ──────────────────────────────────────────────────────────
# 1. Generate realistic clinical trial data (~200 patients)
# ──────────────────────────────────────────────────────────
echo "Generating clinical trial dataset..."

python3 << 'PYDATA' > "$WORKSPACE_DIR/data/trial_data.csv"
import random, csv, sys

random.seed(42)

writer = csv.writer(sys.stdout)
writer.writerow([
    "patient_id", "treatment_group", "age", "sex", "site_id",
    "primary_endpoint", "secondary_endpoint", "adverse_events", "subgroup"
])

ae_pool = [
    "headache", "nausea", "fatigue", "dizziness", "insomnia",
    "diarrhea", "rash", "arthralgia", "back_pain", "cough",
    "upper_respiratory_infection", "injection_site_reaction"
]

for i in range(1, 201):
    pid = f"P{i:03d}"
    group = random.choice(["treatment", "placebo"])
    age = random.randint(35, 80)
    sex = random.choice(["M", "F"])
    site = f"SITE{random.randint(1,8):02d}"

    # Primary endpoint: treatment has higher mean (drug works)
    if group == "treatment":
        primary = round(random.gauss(12.5, 3.0), 2)
    else:
        primary = round(random.gauss(10.0, 3.0), 2)

    # Secondary endpoint: ~10% missing (20 patients)
    if random.random() < 0.10:
        secondary = ""
    else:
        if group == "treatment":
            secondary = round(random.gauss(8.0, 2.5), 2)
        else:
            secondary = round(random.gauss(6.5, 2.5), 2)

    # Adverse events: some patients have 0, some have 1-3
    n_ae = random.choices([0, 1, 2, 3], weights=[0.35, 0.35, 0.20, 0.10])[0]
    if n_ae == 0:
        ae_str = ""
    else:
        ae_str = ";".join(random.sample(ae_pool, n_ae))

    subgroup = "age_over_65" if age >= 65 else "age_under_65"

    writer.writerow([pid, group, age, sex, site, primary, secondary, ae_str, subgroup])
PYDATA

echo "Trial data generated (200 patients)."

# ──────────────────────────────────────────────────────────
# 2. config.py  (BUG: alpha = 0.10 instead of 0.05)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/config.py" << 'EOF'
"""
Configuration for PX-4127 Phase III Clinical Trial Analysis
Protocol: PX4127-CT-301
"""

# ── Trial metadata ──────────────────────────────────────
TRIAL_ID = "PX4127-CT-301"
DRUG_NAME = "PX-4127"
INDICATION = "Moderate-to-severe chronic pain"
PHASE = "III"

# ── Statistical parameters ──────────────────────────────
SIGNIFICANCE_LEVEL = 0.10          # alpha for hypothesis testing
CONFIDENCE_LEVEL = 0.95            # for confidence intervals
RANDOM_SEED = 42

# ── Data paths ──────────────────────────────────────────
DATA_PATH = "data/trial_data.csv"
OUTPUT_DIR = "output/"

# ── Endpoint definitions ────────────────────────────────
PRIMARY_ENDPOINT = "primary_endpoint"
SECONDARY_ENDPOINT = "secondary_endpoint"
TREATMENT_COL = "treatment_group"
TREATMENT_LABEL = "treatment"
CONTROL_LABEL = "placebo"

# ── Subgroup definitions ────────────────────────────────
SUBGROUPS = {
    "age_over_65": ("subgroup", "age_over_65"),
    "age_under_65": ("subgroup", "age_under_65"),
    "male": ("sex", "M"),
    "female": ("sex", "F"),
}

# ── Safety thresholds ──────────────────────────────────
SERIOUS_AE_THRESHOLD = 0.05       # flag if SAE rate > 5%
EOF

# ──────────────────────────────────────────────────────────
# 3. analysis/data_loader.py  (BUG: drops NaN secondary endpoint)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/analysis/data_loader.py" << 'EOF'
"""
Data loading and cleaning for PX-4127 Phase III trial.

Implements the Intent-to-Treat (ITT) population per ICH E9 guidelines.
All randomized patients should be included in the ITT analysis set.
"""

import pandas as pd
import numpy as np
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config


def load_and_clean(filepath=None):
    """
    Load trial data and prepare the ITT analysis population.

    Parameters
    ----------
    filepath : str, optional
        Path to the CSV data file. Defaults to config.DATA_PATH.

    Returns
    -------
    pd.DataFrame
        Cleaned dataframe ready for analysis.
    """
    if filepath is None:
        filepath = config.DATA_PATH

    df = pd.read_csv(filepath)

    # ── Basic validation ────────────────────────────────
    required_cols = [
        "patient_id", "treatment_group", "age", "sex",
        "primary_endpoint", "secondary_endpoint", "adverse_events", "subgroup"
    ]
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")

    # ── Type coercion ───────────────────────────────────
    df["primary_endpoint"] = pd.to_numeric(df["primary_endpoint"], errors="coerce")
    df["secondary_endpoint"] = pd.to_numeric(df["secondary_endpoint"], errors="coerce")
    df["age"] = pd.to_numeric(df["age"], errors="coerce")

    # ── Remove patients with incomplete endpoint data ───
    # Ensures we only analyse patients with evaluable data
    df = df.dropna(subset=["primary_endpoint"])
    df = df.dropna(subset=["secondary_endpoint"])

    # ── Derive convenience flags ────────────────────────
    df["is_treatment"] = (df["treatment_group"] == config.TREATMENT_LABEL).astype(int)

    print(f"[data_loader] Loaded {len(df)} patients for ITT analysis.")
    return df


def get_treatment_groups(df):
    """Split dataframe into treatment and control arms."""
    treatment = df[df["treatment_group"] == config.TREATMENT_LABEL]
    control = df[df["treatment_group"] == config.CONTROL_LABEL]
    return treatment, control
EOF

# ──────────────────────────────────────────────────────────
# 4. analysis/primary_endpoint.py
#    BUG 1: one-sided t-test (should be two-sided)
#    BUG 2: z-score CI (should use t-distribution)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/analysis/primary_endpoint.py" << 'EOF'
"""
Primary efficacy endpoint analysis for PX-4127 Phase III trial.

The primary endpoint is the change from baseline in pain score
(continuous, normally distributed). Statistical test: independent
two-sample comparison between treatment and placebo arms.
"""

import numpy as np
from scipy import stats
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config


def analyze_primary(df):
    """
    Perform the primary efficacy analysis.

    Computes:
    - Group means and standard deviations
    - Between-group difference and confidence interval
    - Hypothesis test (superiority)

    Parameters
    ----------
    df : pd.DataFrame
        Cleaned ITT population from data_loader.

    Returns
    -------
    dict
        Results dictionary with statistics, CI, and p-value.
    """
    treatment = df.loc[
        df["treatment_group"] == config.TREATMENT_LABEL, config.PRIMARY_ENDPOINT
    ].values
    control = df.loc[
        df["treatment_group"] == config.CONTROL_LABEL, config.PRIMARY_ENDPOINT
    ].values

    n_trt, n_ctrl = len(treatment), len(control)
    mean_trt = np.mean(treatment)
    mean_ctrl = np.mean(control)
    std_trt = np.std(treatment, ddof=1)
    std_ctrl = np.std(control, ddof=1)

    # ── Between-group difference ────────────────────────
    diff = mean_trt - mean_ctrl

    # ── Pooled standard error ───────────────────────────
    se = np.sqrt(std_trt**2 / n_trt + std_ctrl**2 / n_ctrl)

    # ── Confidence interval (95%) ───────────────────────
    z_critical = 1.96  # 95% CI
    ci_lower = diff - z_critical * se
    ci_upper = diff + z_critical * se

    # ── Hypothesis test ─────────────────────────────────
    t_stat, p_value = stats.ttest_ind(treatment, control, alternative='greater')

    # ── Clinical significance ───────────────────────────
    cohens_d = diff / np.sqrt(
        ((n_trt - 1) * std_trt**2 + (n_ctrl - 1) * std_ctrl**2)
        / (n_trt + n_ctrl - 2)
    )

    results = {
        "n_treatment": n_trt,
        "n_control": n_ctrl,
        "mean_treatment": round(mean_trt, 4),
        "mean_control": round(mean_ctrl, 4),
        "difference": round(diff, 4),
        "se": round(se, 4),
        "ci_lower": round(ci_lower, 4),
        "ci_upper": round(ci_upper, 4),
        "t_statistic": round(t_stat, 4),
        "p_value": round(p_value, 6),
        "cohens_d": round(cohens_d, 4),
        "significant": p_value < config.SIGNIFICANCE_LEVEL,
    }

    print(f"[primary] Treatment mean: {mean_trt:.3f}, Control mean: {mean_ctrl:.3f}")
    print(f"[primary] Difference: {diff:.3f}  95% CI: ({ci_lower:.3f}, {ci_upper:.3f})")
    print(f"[primary] t={t_stat:.3f}, p={p_value:.6f}")

    return results
EOF

# ──────────────────────────────────────────────────────────
# 5. analysis/safety_analysis.py
#    BUG: counts total AE events, not patients with >=1 AE
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/analysis/safety_analysis.py" << 'EOF'
"""
Safety analysis for PX-4127 Phase III trial.

Calculates adverse event incidence rates per treatment arm.
Per FDA guidance, incidence should be reported as the proportion
of patients experiencing at least one event of each type.
"""

import pandas as pd
import numpy as np
from collections import defaultdict
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config


def analyze_safety(df):
    """
    Compute adverse event incidence rates by treatment group.

    For each AE term, calculates:
    - Count and incidence rate in treatment arm
    - Count and incidence rate in control arm
    - Risk difference

    Parameters
    ----------
    df : pd.DataFrame
        Cleaned ITT population.

    Returns
    -------
    dict
        Safety summary with per-AE and overall statistics.
    """
    results = {}

    for arm_label in [config.TREATMENT_LABEL, config.CONTROL_LABEL]:
        arm_df = df[df["treatment_group"] == arm_label]
        n_patients = len(arm_df)

        # ── Count adverse events per term ───────────────
        ae_counts = defaultdict(int)
        total_ae_count = 0

        for _, row in arm_df.iterrows():
            ae_field = row["adverse_events"]
            if pd.isna(ae_field) or str(ae_field).strip() == "":
                continue
            patient_events = [e.strip() for e in str(ae_field).split(";") if e.strip()]
            total_ae_count += len(patient_events)
            for event in patient_events:
                ae_counts[event] += len(patient_events)

        # ── Calculate incidence rates ───────────────────
        ae_table = {}
        for term, count in ae_counts.items():
            ae_table[term] = {
                "count": count,
                "incidence_rate": round(count / n_patients, 4) if n_patients > 0 else 0,
            }

        results[arm_label] = {
            "n_patients": n_patients,
            "total_ae_count": total_ae_count,
            "overall_ae_rate": round(total_ae_count / n_patients, 4) if n_patients > 0 else 0,
            "ae_by_term": ae_table,
        }

    # ── Summary table ───────────────────────────────────
    trt = results.get(config.TREATMENT_LABEL, {})
    ctrl = results.get(config.CONTROL_LABEL, {})

    print(f"[safety] Treatment arm: {trt.get('n_patients', 0)} patients, "
          f"{trt.get('total_ae_count', 0)} total AE events")
    print(f"[safety] Control arm:   {ctrl.get('n_patients', 0)} patients, "
          f"{ctrl.get('total_ae_count', 0)} total AE events")

    return results
EOF

# ──────────────────────────────────────────────────────────
# 6. analysis/subgroup_analysis.py
#    BUG: no multiplicity adjustment for multiple comparisons
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/analysis/subgroup_analysis.py" << 'EOF'
"""
Pre-specified subgroup analyses for PX-4127 Phase III trial.

Evaluates treatment effect consistency across demographic subgroups
as required by the statistical analysis plan (SAP).
"""

import numpy as np
from scipy import stats
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config


def analyze_subgroups(df):
    """
    Perform subgroup analyses on the primary endpoint.

    For each pre-specified subgroup, computes the treatment vs. control
    difference, 95 % confidence interval, and p-value.

    Parameters
    ----------
    df : pd.DataFrame
        Cleaned ITT population.

    Returns
    -------
    dict
        Results keyed by subgroup name.
    """
    subgroup_results = {}

    for sg_name, (col, value) in config.SUBGROUPS.items():
        sg_df = df[df[col] == value]

        treatment = sg_df.loc[
            sg_df["treatment_group"] == config.TREATMENT_LABEL, config.PRIMARY_ENDPOINT
        ].values
        control = sg_df.loc[
            sg_df["treatment_group"] == config.CONTROL_LABEL, config.PRIMARY_ENDPOINT
        ].values

        if len(treatment) < 5 or len(control) < 5:
            subgroup_results[sg_name] = {"skipped": True, "reason": "insufficient n"}
            continue

        mean_trt = np.mean(treatment)
        mean_ctrl = np.mean(control)
        diff = mean_trt - mean_ctrl

        t_stat, p_value = stats.ttest_ind(treatment, control)
        se = np.sqrt(np.var(treatment, ddof=1) / len(treatment)
                     + np.var(control, ddof=1) / len(control))

        subgroup_results[sg_name] = {
            "n_treatment": len(treatment),
            "n_control": len(control),
            "mean_treatment": round(mean_trt, 4),
            "mean_control": round(mean_ctrl, 4),
            "difference": round(diff, 4),
            "se": round(se, 4),
            "t_statistic": round(t_stat, 4),
            "p_value": round(p_value, 6),
            "significant": p_value < config.SIGNIFICANCE_LEVEL,
        }

    _print_subgroup_table(subgroup_results)
    return subgroup_results


def _print_subgroup_table(results):
    """Pretty-print subgroup analysis table."""
    print("\n[subgroup] Subgroup Analysis Summary")
    print("-" * 72)
    header = f"{'Subgroup':<20} {'N(trt)':<8} {'N(ctrl)':<8} {'Diff':<10} {'p-value':<12} {'Sig?'}"
    print(header)
    print("-" * 72)

    for sg_name, res in results.items():
        if res.get("skipped"):
            print(f"{sg_name:<20} -- skipped ({res['reason']})")
            continue
        sig_flag = "*" if res["significant"] else ""
        print(
            f"{sg_name:<20} {res['n_treatment']:<8} {res['n_control']:<8} "
            f"{res['difference']:<10.4f} {res['p_value']:<12.6f} {sig_flag}"
        )
    print("-" * 72)
EOF

# ──────────────────────────────────────────────────────────
# 7. analysis/report_generator.py  (correct, no bugs)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/analysis/report_generator.py" << 'EOF'
"""
Report generation utilities for PX-4127 Phase III trial.

Compiles analysis results into a summary suitable for inclusion
in the NDA clinical study report (CSR).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config


def generate_report(primary_results, safety_results, subgroup_results, output_dir=None):
    """
    Generate the analysis summary report.

    Parameters
    ----------
    primary_results : dict
    safety_results : dict
    subgroup_results : dict
    output_dir : str, optional

    Returns
    -------
    str
        Path to the generated report JSON.
    """
    if output_dir is None:
        output_dir = config.OUTPUT_DIR
    os.makedirs(output_dir, exist_ok=True)

    report = {
        "trial_id": config.TRIAL_ID,
        "drug": config.DRUG_NAME,
        "indication": config.INDICATION,
        "phase": config.PHASE,
        "alpha": config.SIGNIFICANCE_LEVEL,
        "primary_efficacy": primary_results,
        "safety_summary": _summarize_safety(safety_results),
        "subgroup_analyses": subgroup_results,
    }

    report_path = os.path.join(output_dir, "analysis_report.json")
    with open(report_path, "w") as fh:
        json.dump(report, fh, indent=2, default=str)

    print(f"[report] Report written to {report_path}")
    return report_path


def _summarize_safety(safety_results):
    """Create a concise safety summary from the full results."""
    summary = {}
    for arm, data in safety_results.items():
        summary[arm] = {
            "n_patients": data["n_patients"],
            "total_ae_count": data["total_ae_count"],
            "overall_ae_rate": data["overall_ae_rate"],
            "top_5_ae": sorted(
                data["ae_by_term"].items(),
                key=lambda x: x[1]["count"],
                reverse=True,
            )[:5],
        }
    return summary
EOF

# ──────────────────────────────────────────────────────────
# 8. analysis/__init__.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/analysis/__init__.py" << 'EOF'
# PX-4127 Phase III Clinical Trial Analysis Package
EOF

# ──────────────────────────────────────────────────────────
# 9. run_analysis.py  (main pipeline runner)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_analysis.py" << 'EOF'
#!/usr/bin/env python3
"""
Main pipeline for PX-4127 Phase III Clinical Trial Analysis.

Orchestrates:
    1. Data loading / ITT population derivation
    2. Primary efficacy endpoint analysis
    3. Safety (adverse event) analysis
    4. Pre-specified subgroup analyses
    5. Report generation

Usage:
    python run_analysis.py
"""

import sys
import os

# Ensure project root is on the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import config
from analysis.data_loader import load_and_clean, get_treatment_groups
from analysis.primary_endpoint import analyze_primary
from analysis.safety_analysis import analyze_safety
from analysis.subgroup_analysis import analyze_subgroups
from analysis.report_generator import generate_report


def main():
    print("=" * 60)
    print(f"  {config.DRUG_NAME} Phase {config.PHASE} Analysis Pipeline")
    print(f"  Protocol: {config.TRIAL_ID}")
    print(f"  Alpha: {config.SIGNIFICANCE_LEVEL}")
    print("=" * 60)

    # Step 1 – Load & prepare data
    print("\n── Step 1: Data Loading ──")
    df = load_and_clean()

    # Step 2 – Primary efficacy
    print("\n── Step 2: Primary Endpoint Analysis ──")
    primary_results = analyze_primary(df)

    # Step 3 – Safety
    print("\n── Step 3: Safety Analysis ──")
    safety_results = analyze_safety(df)

    # Step 4 – Subgroups
    print("\n── Step 4: Subgroup Analyses ──")
    subgroup_results = analyze_subgroups(df)

    # Step 5 – Report
    print("\n── Step 5: Report Generation ──")
    report_path = generate_report(primary_results, safety_results, subgroup_results)

    print("\n" + "=" * 60)
    sig = "YES" if primary_results["significant"] else "NO"
    print(f"  Primary endpoint significant: {sig}  (p = {primary_results['p_value']})")
    print(f"  Report: {report_path}")
    print("=" * 60)


if __name__ == "__main__":
    main()
EOF

# ──────────────────────────────────────────────────────────
# 10. requirements.txt
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
numpy>=1.24
pandas>=2.0
scipy>=1.10
EOF

# ──────────────────────────────────────────────────────────
# Ownership, baseline hashes, VSCode launch
# ──────────────────────────────────────────────────────────
chown -R ga:ga "$WORKSPACE_DIR"

# Record baseline hashes so the verifier can detect actual edits
md5sum \
    "$WORKSPACE_DIR/config.py" \
    "$WORKSPACE_DIR/analysis/data_loader.py" \
    "$WORKSPACE_DIR/analysis/primary_endpoint.py" \
    "$WORKSPACE_DIR/analysis/safety_analysis.py" \
    "$WORKSPACE_DIR/analysis/subgroup_analysis.py" \
    > /tmp/clinical_trial_initial_hashes.txt

echo "Baseline hashes recorded."

# Open VSCode
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code --no-sandbox --disable-workspace-trust '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1
focus_vscode_window
sleep 3

echo "=== Audit Clinical Trial Pipeline Task Setup Complete ==="
echo "Workspace: $WORKSPACE_DIR"
echo "Pipeline entry point: run_analysis.py"
echo "The QA team has flagged statistical methodology errors."
echo "Audit and fix all issues before FDA submission."
