#!/usr/bin/env python3
"""
Verifier for the audit_clinical_trial_pipeline task.

Checks whether the agent identified and fixed 6 statistical /
regulatory-compliance bugs in the PX-4127 Phase III analysis pipeline.

Each fix is worth ~17 points (total 100).  Pass threshold: 60.
"""

import sys
import os
import json
import re
import hashlib
import logging
import tempfile
import shutil

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../", "utils"),
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────
# Helper utilities
# ──────────────────────────────────────────────────────────

def _safe_get(data, key):
    """Return file content from the result dict, or empty string."""
    val = data.get(key)
    return val if isinstance(val, str) else ""


def _md5(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()


# ──────────────────────────────────────────────────────────
# Individual bug checks
# ──────────────────────────────────────────────────────────

def check_itt_fix(data_loader_src):
    """
    Bug 1 – ITT Violation (data_loader.py)
    The original code filters out patients with NaN secondary_endpoint
    via df.dropna(subset=["secondary_endpoint"]).  The fix is to
    remove that filter so all randomised patients stay in the ITT set.
    """
    if not data_loader_src:
        return False, "data_loader.py is missing or empty"

    # The buggy line drops rows where secondary_endpoint is missing.
    # We check for several patterns that would constitute the bug.
    bug_patterns = [
        r'dropna\s*\(\s*subset\s*=\s*\[.*secondary_endpoint.*\]',
        r'\.dropna\(.*secondary_endpoint',
        r'isna\(.*secondary_endpoint',
        r'isnull\(.*secondary_endpoint',
        r'notna\(.*secondary_endpoint',
        r'notnull\(.*secondary_endpoint',
    ]

    for pat in bug_patterns:
        if re.search(pat, data_loader_src):
            return False, "data_loader.py still filters on secondary_endpoint NaN"

    return True, "ITT population correctly retains all randomised patients"


def check_two_sided_test(primary_src):
    """
    Bug 2 – Wrong p-value sidedness (primary_endpoint.py)
    Original uses alternative='greater' (one-sided).
    Fix: alternative='two-sided' or remove the parameter entirely.
    """
    if not primary_src:
        return False, "primary_endpoint.py is missing or empty"

    has_greater = bool(re.search(r"alternative\s*=\s*['\"]greater['\"]", primary_src))
    has_less = bool(re.search(r"alternative\s*=\s*['\"]less['\"]", primary_src))
    has_two_sided = bool(re.search(r"alternative\s*=\s*['\"]two-sided['\"]", primary_src))

    if has_greater or has_less:
        return False, "primary_endpoint.py still uses one-sided test"

    # Either explicitly two-sided or parameter removed (default is two-sided)
    return True, "primary_endpoint.py correctly uses two-sided test"


def check_t_distribution_ci(primary_src):
    """
    Bug 3 – z-score CI instead of t-distribution (primary_endpoint.py)
    Original uses z_critical = 1.96.
    Fix: should use scipy.stats.t.ppf / t.interval / t_critical.
    """
    if not primary_src:
        return False, "primary_endpoint.py is missing or empty"

    # Check whether the hard-coded 1.96 z-score is still used as the
    # critical value for the CI.  We look for the assignment pattern.
    still_uses_z = bool(re.search(r'(?:z_critical|z_crit|zcrit)\s*=\s*1\.96', primary_src))

    # Also flag if 1.96 appears in the CI calculation lines without any
    # t-distribution reference nearby.
    uses_t_dist = bool(
        re.search(r'stats\.t\.ppf|stats\.t\.interval|t\.ppf|t\.interval|t_critical\s*=\s*stats', primary_src)
        or re.search(r'from\s+scipy\.stats\s+import\s+t\b', primary_src)
    )

    if still_uses_z and not uses_t_dist:
        return False, "primary_endpoint.py still uses z=1.96 for CI instead of t-distribution"

    if uses_t_dist:
        return True, "primary_endpoint.py correctly uses t-distribution for CI"

    # If 1.96 is gone but no explicit t-dist reference, give benefit of the doubt
    # only if the literal 1.96 no longer appears in CI context
    if not re.search(r'1\.96', primary_src):
        return True, "primary_endpoint.py no longer uses hard-coded 1.96"

    return False, "primary_endpoint.py may still use z-score CI"


def check_patient_level_counting(safety_src):
    """
    Bug 4 – Event counting vs patient counting (safety_analysis.py)
    Original increments counts by len(patient_events) per AE term,
    thereby counting events not patients.  Fix: count each patient
    at most once per AE term.
    """
    if not safety_src:
        return False, "safety_analysis.py is missing or empty"

    # The buggy pattern: ae_counts[event] += len(patient_events)
    bug_patterns = [
        r'\+=\s*len\s*\(\s*patient_events\s*\)',
        r'\+=\s*len\s*\(\s*events\s*\)',
    ]
    for pat in bug_patterns:
        if re.search(pat, safety_src):
            return False, "safety_analysis.py still counts events instead of patients"

    # Look for correct patient-level patterns
    correct_patterns = [
        r'\+=\s*1',           # increment by 1 per patient
        r'set\s*\(',          # using a set to track unique patients
        r'nunique',           # pandas nunique
        r'unique\s*\(',       # np.unique or similar
    ]
    has_correct = any(re.search(p, safety_src) for p in correct_patterns)

    if has_correct:
        return True, "safety_analysis.py correctly counts patients (not events)"

    # If the len() bug is gone but we can't confirm the fix pattern,
    # give partial credit via a weaker check
    return True, "safety_analysis.py no longer uses event-level counting"


def check_multiplicity_adjustment(subgroup_src):
    """
    Bug 5 – No multiplicity adjustment (subgroup_analysis.py)
    Original performs 4 subgroup comparisons without correcting for
    multiple testing.  Fix: Bonferroni (or similar) correction.
    """
    if not subgroup_src:
        return False, "subgroup_analysis.py is missing or empty"

    adjustment_patterns = [
        r'[Bb]onferroni',
        r'p_value\s*\*\s*(?:len|n_comparisons|num_comparisons|n_tests|num_tests|4)',
        r'p_value\s*\*=\s*(?:len|n_comparisons|num_comparisons|n_tests|num_tests|4)',
        r'alpha\s*/\s*(?:len|n_comparisons|num_comparisons|n_tests|num_tests|4)',
        r'SIGNIFICANCE_LEVEL\s*/\s*(?:len|n_comparisons|num_comparisons|n_tests|4)',
        r'multipletests',                # statsmodels multipletests
        r'holm',                          # Holm correction
        r'benjamini',                     # Benjamini-Hochberg
        r'p_adjust',                      # R-style name
        r'adjusted_p',                    # common naming
        r'corrected_p',                   # common naming
        r'n_comparisons\s*=',            # defines number of comparisons
        r'num_comparisons\s*=',
        r'p_value\s*\*\s*n_',            # multiply p by n_something
    ]

    for pat in adjustment_patterns:
        if re.search(pat, subgroup_src):
            return True, "subgroup_analysis.py includes multiplicity adjustment"

    return False, "subgroup_analysis.py has no multiplicity adjustment"


def check_alpha_level(config_src):
    """
    Bug 6 – Wrong alpha (config.py)
    Original: SIGNIFICANCE_LEVEL = 0.10
    Fix:      SIGNIFICANCE_LEVEL = 0.05
    """
    if not config_src:
        return False, "config.py is missing or empty"

    # Extract the value assigned to SIGNIFICANCE_LEVEL
    m = re.search(r'SIGNIFICANCE_LEVEL\s*=\s*([0-9.]+)', config_src)
    if not m:
        return False, "config.py does not define SIGNIFICANCE_LEVEL"

    val = float(m.group(1))
    if abs(val - 0.05) < 1e-9:
        return True, "config.py correctly sets alpha = 0.05"
    elif abs(val - 0.10) < 1e-9:
        return False, "config.py still uses alpha = 0.10 (should be 0.05)"
    else:
        return False, f"config.py uses unexpected alpha = {val}"


# ──────────────────────────────────────────────────────────
# Anti-gaming: verify files were actually changed
# ──────────────────────────────────────────────────────────

def _files_were_modified(data, copy_from_env, temp_dir):
    """
    Compare current file contents against baseline hashes recorded
    during setup.  Returns True if at least one file was modified.
    """
    try:
        hashes_local = os.path.join(temp_dir, "initial_hashes.txt")
        copy_from_env("/tmp/clinical_trial_initial_hashes.txt", hashes_local)
        if not os.path.exists(hashes_local):
            return True  # can't verify, assume modified

        with open(hashes_local, "r") as fh:
            original_hashes = {}
            for line in fh:
                parts = line.strip().split()
                if len(parts) >= 2:
                    h, path = parts[0], parts[-1]
                    # Extract relative key
                    for key in data:
                        if path.endswith(key) or path.endswith(key.replace("/", os.sep)):
                            original_hashes[key] = h

        # Check if any monitored file has a different hash now
        for key, orig_hash in original_hashes.items():
            content = data.get(key, "")
            if content and _md5(content) != orig_hash:
                return True

        return False
    except Exception as e:
        logger.warning(f"Could not verify file modification: {e}")
        return True  # fail open


# ──────────────────────────────────────────────────────────
# Main verifier entry point
# ──────────────────────────────────────────────────────────

def verify_clinical_trial_pipeline(traj, env_info, task_info):
    """
    Verify that the agent fixed the 6 bugs in the clinical trial pipeline.

    Returns
    -------
    dict
        {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_dir = tempfile.mkdtemp(prefix="verify_clinical_")

    try:
        # ── Retrieve exported result JSON ───────────────
        result_local = os.path.join(temp_dir, "clinical_trial_result.json")
        try:
            copy_from_env("/tmp/clinical_trial_result.json", result_local)
        except Exception as e:
            logger.error(f"Could not copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve result file: {e}",
            }

        if not os.path.exists(result_local):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found after export",
            }

        with open(result_local, "r", encoding="utf-8") as fh:
            data = json.load(fh)

        # ── Extract file contents ───────────────────────
        config_src = _safe_get(data, "config.py")
        data_loader_src = _safe_get(data, "analysis/data_loader.py")
        primary_src = _safe_get(data, "analysis/primary_endpoint.py")
        safety_src = _safe_get(data, "analysis/safety_analysis.py")
        subgroup_src = _safe_get(data, "analysis/subgroup_analysis.py")

        # ── Anti-gaming check ───────────────────────────
        if not _files_were_modified(data, copy_from_env, temp_dir):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No files appear to have been modified from the original.",
            }

        # ── Run the six checks ──────────────────────────
        checks = [
            ("ITT population fix", 17, check_itt_fix(data_loader_src)),
            ("Two-sided test", 17, check_two_sided_test(primary_src)),
            ("t-distribution CI", 17, check_t_distribution_ci(primary_src)),
            ("Patient-level AE counting", 17, check_patient_level_counting(safety_src)),
            ("Multiplicity adjustment", 16, check_multiplicity_adjustment(subgroup_src)),
            ("Alpha level correction", 16, check_alpha_level(config_src)),
        ]

        score = 0
        feedback_lines = []

        for label, points, (ok, msg) in checks:
            if ok:
                score += points
                feedback_lines.append(f"PASS [{points}pts] {label}: {msg}")
            else:
                feedback_lines.append(f"FAIL [ 0pts] {label}: {msg}")

        passed = score >= 60
        feedback_lines.insert(
            0,
            f"{'PASSED' if passed else 'FAILED'}: {score}/100 "
            f"(threshold 60, {sum(1 for _, _, (ok, _) in checks if ok)}/6 bugs fixed)",
        )

        logger.info(f"Score: {score}/100, passed={passed}")
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_lines),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }

    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
