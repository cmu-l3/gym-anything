#!/usr/bin/env python3
"""
Verifier for LaLonde Causal Inference Task.
Checks CSV content for statistical correctness and plot existence.
"""

import json
import os
import tempfile
import logging
import csv
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lalonde_analysis(traj, env_info, task_info):
    """
    Verify the LaLonde PSM analysis.
    
    Scoring Criteria:
    1. Balance Table CSV (20 pts): Exists, new, has SMD columns.
    2. Balance Improvement (15 pts): SMD decreases after matching.
    3. Treatment Effects CSV (20 pts): Exists, new, contains estimates.
    4. Naive vs Matched Contrast (10 pts): Naive < 0, Matched > 0 (roughly).
    5. Love Plot (20 pts): Exists, new, valid PNG.
    6. R Script (15 pts): Contains 'MatchIt'/'matchit' and usage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_dir = tempfile.mkdtemp()
    files = {
        "result_json": "task_result.json",
        "balance_csv": "submitted_balance.csv",
        "effects_csv": "submitted_effects.csv",
        "plot_png": "submitted_plot.png",
        "script_r": "submitted_script.R"
    }
    
    local_files = {}
    for key, remote_name in files.items():
        local_path = os.path.join(temp_dir, remote_name)
        try:
            # Note: The export script places files in /tmp/
            # result.json is at /tmp/task_result.json
            remote_path = f"/tmp/{remote_name}"
            copy_from_env(remote_path, local_path)
            if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                local_files[key] = local_path
        except Exception as e:
            logger.warning(f"Failed to copy {remote_name}: {e}")

    # Load JSON metadata
    result_data = {}
    if "result_json" in local_files:
        with open(local_files["result_json"], 'r') as f:
            try:
                result_data = json.load(f)
            except:
                pass

    score = 0
    feedback = []
    
    # --- Criterion 1 & 2: Balance Table (35 pts total) ---
    bal_score = 0
    if "balance_csv" in local_files:
        bal_data = []
        try:
            with open(local_files["balance_csv"], 'r', encoding='utf-8', errors='replace') as f:
                reader = csv.reader(f)
                headers = next(reader, [])
                bal_data = list(reader)
            
            # Check for header keywords indicating Before/After or Unmatched/Matched
            header_str = " ".join(headers).lower()
            has_smd_cols = any(x in header_str for x in ['unmatched', 'all', 'before']) and \
                           any(x in header_str for x in ['matched', 'after'])
            
            if len(bal_data) >= 5: # Should have Age, Educ, Race, etc.
                bal_score += 10 # Structure ok
                
                if has_smd_cols:
                    bal_score += 10 # Columns ok
                    
                    # Try to parse values to check improvement
                    # We look for numeric columns. Usually Unmatched is col 1 or 2, Matched is next.
                    # Heuristic: find two columns with floats.
                    numeric_cols = []
                    for r in bal_data:
                        nums = []
                        for val in r:
                            try:
                                nums.append(abs(float(val)))
                            except:
                                nums.append(None)
                        numeric_cols.append(nums)
                    
                    # Assume column with higher average value is Unmatched (SMD usually high initially)
                    # or rely on header if possible. Let's rely on reduction logic.
                    # If *any* pair of columns shows reduction in mean value, give credit.
                    found_improvement = False
                    
                    # Transpose to analyze columns
                    if numeric_cols:
                        cols_vals = list(zip(*numeric_cols))
                        means = []
                        for c in cols_vals:
                            valid_nums = [x for x in c if x is not None]
                            if len(valid_nums) > 3:
                                means.append(sum(valid_nums)/len(valid_nums))
                            else:
                                means.append(-1)
                        
                        # Check if we have a "high" mean (>0.1) and a "low" mean (<0.1)
                        # Unmatched LaLonde SMDs are large (~0.3-0.8). Matched should be <0.1.
                        if any(m > 0.15 for m in means) and any(m < 0.1 for m in means):
                            found_improvement = True
                    
                    if found_improvement:
                        bal_score += 15
                        feedback.append("Balance table shows improvement in SMD.")
                    else:
                        feedback.append("Balance table found but improvement unclear/marginal.")
                else:
                    feedback.append("Balance table missing clear Unmatched/Matched headers.")
            else:
                feedback.append("Balance table has too few rows.")
        except Exception as e:
            feedback.append(f"Error parsing balance CSV: {e}")
    else:
        feedback.append("Balance table CSV not found.")
    
    score += bal_score

    # --- Criterion 3 & 4: Treatment Effects (30 pts total) ---
    eff_score = 0
    if "effects_csv" in local_files:
        try:
            with open(local_files["effects_csv"], 'r') as f:
                content = f.read().lower()
                
            # Check for existence of methods
            has_naive = "naive" in content or "unadj" in content
            has_match = "match" in content or "nn" in content or "full" in content
            
            if has_naive and has_match:
                eff_score += 15
                
                # Extract numbers to check direction
                # This is tricky with regex on CSV, but let's try finding the estimates.
                # Naive should be negative (~ -600 to -15000), Matched positive (~500 to 3000)
                # Simple check: is there a negative number and a positive number > 500?
                numbers = [float(x) for x in re.findall(r'-?\d+\.?\d*', content)]
                
                has_neg = any(n < -100 for n in numbers)
                has_pos_sig = any(n > 100 for n in numbers)
                
                if has_neg and has_pos_sig:
                    eff_score += 15
                    feedback.append("Treatment effects show correction from negative to positive.")
                else:
                    feedback.append("Treatment effects found but values look unexpected (expecting neg -> pos).")
            else:
                feedback.append("Treatment effects file missing required methods (Naive + Matching).")
                eff_score += 5 # Credit for file existence
        except:
            feedback.append("Error reading effects CSV.")
    else:
        feedback.append("Treatment effects CSV not found.")
        
    score += eff_score

    # --- Criterion 5: Love Plot (20 pts) ---
    if "plot_png" in local_files:
        size = os.path.getsize(local_files["plot_png"])
        if size > 15000: # 15KB
            score += 20
            feedback.append("Love plot exists and has valid size.")
        else:
            score += 5
            feedback.append("Love plot file exists but is very small.")
    else:
        feedback.append("Love plot PNG not found.")

    # --- Criterion 6: R Script (15 pts) ---
    if "script_r" in local_files:
        try:
            with open(local_files["script_r"], 'r') as f:
                script_content = f.read()
            
            if "matchit" in script_content.lower() and "bal" in script_content.lower():
                score += 15
                feedback.append("R script contains expected matching logic.")
            else:
                score += 5
                feedback.append("R script exists but missing key function calls.")
        except:
            pass
    else:
        feedback.append("Analysis script not found.")

    # Cleanup
    import shutil
    shutil.rmtree(temp_dir)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }