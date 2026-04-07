#!/usr/bin/env python3
"""
Verifier for bootstrap_birthwt_inference task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bootstrap_inference(traj, env_info, task_info):
    """
    Verify the Bootstrap & Permutation Inference task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    parsed = result.get("parsed_data", {})
    files = result.get("files", {})

    # ----------------------------------------------------------------
    # Criterion 1: Bootstrap CI CSV (25 pts)
    # ----------------------------------------------------------------
    f_ci = files.get("bootstrap_ci", {})
    data_ci = parsed.get("bootstrap_ci", {})
    
    if f_ci.get("exists") and f_ci.get("is_new"):
        score += 5
        feedback.append("Bootstrap CSV exists and is new (+5)")
    
    # Check required columns
    required_cols_ci = ["statistic", "observed", "boot_se", "ci_bca_lower", "ci_bca_upper"]
    cols = data_ci.get("cols") or []
    if all(c in cols for c in required_cols_ci):
        score += 5
        feedback.append("Bootstrap CSV has correct columns (+5)")
    else:
        feedback.append(f"Bootstrap CSV missing columns. Found: {cols}")

    # Check stats content
    stats = data_ci.get("stats", {})
    expected_stats = ["mean_bwt_smoke", "mean_bwt_nosmoke", "diff_smoke", "or_smoke", "median_bwt", "cor_age_bwt"]
    
    found_stats = 0
    plausible_values = 0
    
    if all(s in stats for s in expected_stats):
        found_stats = 1
        score += 5
        feedback.append("All 6 statistics present (+5)")
    else:
        feedback.append(f"Missing some statistics. Found: {list(stats.keys())}")

    # Value checks
    # diff_smoke should be roughly 200-400g
    ds = stats.get("diff_smoke", {})
    if ds:
        obs = ds.get("observed")
        se = ds.get("boot_se")
        if obs is not None and 150 <= obs <= 500:
            plausible_values += 1
        if se is not None and se > 0:
            plausible_values += 1
            
    # or_smoke should be > 1 (smokers have higher risk, or ~2.0)
    ors = stats.get("or_smoke", {})
    if ors:
        obs = ors.get("observed")
        if obs is not None and 1.0 <= obs <= 5.0:
            plausible_values += 1
            
    if plausible_values >= 3:
        score += 10
        feedback.append("Bootstrap statistics values are plausible (+10)")
    else:
        feedback.append("Bootstrap statistics values seem off or missing")


    # ----------------------------------------------------------------
    # Criterion 2: Permutation Tests CSV (25 pts)
    # ----------------------------------------------------------------
    f_perm = files.get("permutation", {})
    data_perm = parsed.get("permutation", {})
    
    if f_perm.get("exists") and f_perm.get("is_new"):
        score += 5
        feedback.append("Permutation CSV exists and is new (+5)")
        
    required_cols_perm = ["test_name", "p_value_permutation", "p_value_classical"]
    cols_p = data_perm.get("cols") or []
    if all(c in cols_p for c in required_cols_perm):
        score += 5
        feedback.append("Permutation CSV has correct columns (+5)")
        
    tests = data_perm.get("tests", {})
    expected_tests = ["smoke_bwt", "race_bwt"] # Check at least these two
    
    valid_p = 0
    agreement = 0
    
    if all(t in tests for t in expected_tests):
        score += 5
        feedback.append("Required permutation tests present (+5)")
        
    # Check smoke_bwt p-value (should be sig or borderline sig < 0.1)
    sm = tests.get("smoke_bwt", {})
    if sm:
        p_perm = sm.get("p_perm")
        p_class = sm.get("p_class")
        n_perm = sm.get("n_perm")
        
        if n_perm and n_perm >= 1000:
            valid_p += 1 # Bonus for doing enough permutations
            
        if p_perm is not None and p_perm < 0.1:
            valid_p += 1
            
        if p_perm is not None and p_class is not None:
            # They should be roughly similar
            if abs(p_perm - p_class) < 0.05:
                agreement += 1

    if valid_p >= 1 and agreement >= 1:
        score += 10
        feedback.append("Permutation results valid and match classical (+10)")
        
    # ----------------------------------------------------------------
    # Criterion 3: Comparison CSV (15 pts)
    # ----------------------------------------------------------------
    f_comp = files.get("comparison", {})
    data_comp = parsed.get("comparison", {})
    
    if f_comp.get("exists") and f_comp.get("is_new"):
        score += 5
        feedback.append("Comparison CSV exists (+5)")
        
    comps = data_comp.get("comparisons", {})
    if len(comps) >= 5:
        score += 5
        feedback.append("Comparison CSV has entries (+5)")
        
        # Check relative widths are not all 1.0 (exact match suspicious) or 0
        widths = [c.get("rel_width") for c in comps.values() if c.get("rel_width") is not None]
        if widths and any(0.8 < w < 1.2 for w in widths) and not all(w == 1.0 for w in widths):
            score += 5
            feedback.append("Comparison widths look reasonable (+5)")

    # ----------------------------------------------------------------
    # Criterion 4: Visualization (25 pts)
    # ----------------------------------------------------------------
    f_plot = files.get("plot", {})
    
    if f_plot.get("exists") and f_plot.get("is_new"):
        score += 10
        feedback.append("Plot PNG exists and is new (+10)")
        
        size = f_plot.get("size", 0)
        if size > 50000: # >50KB implies decent content
            score += 10
            feedback.append(f"Plot size is substantial ({size//1024}KB) (+10)")
        elif size > 10000:
            score += 5
            feedback.append(f"Plot size is okay ({size//1024}KB) (+5)")
            
        # VLM could verify panels here, but size is a decent proxy for "multi-panel"
        # We assume VLM scoring is done via a separate optional step or implicit in final check
        
        # Bonus check: Script used boot package
        if result.get("script_content_valid"):
            score += 5
            feedback.append("Script uses 'boot' package (+5)")

    # ----------------------------------------------------------------
    # Final Score
    # ----------------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }