#!/usr/bin/env python3
"""
Verifier for Airway Differential Expression Task.

Verifies:
1. DE Results CSV: Existence, validity, and biological plausibility (significant genes).
2. Visualizations: Volcano plot and Heatmap existence and size.
3. Summary metrics: Existence of summary file.
4. Code execution: Script modification and content.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_airway_de_analysis(traj, env_info, task_info):
    """
    Verify the airway RNA-seq analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: DE Results CSV (40 pts) ---
    res = result.get('res_csv', {})
    if res.get('exists') and res.get('is_new'):
        score += 10
        feedback.append("DE results file created (+10)")
        
        if res.get('has_columns'):
            score += 10
            feedback.append("DE results have correct columns (+10)")
        else:
            feedback.append("DE results missing required columns (log2FoldChange, padj)")
            
        sig_count = res.get('sig_gene_count', 0)
        # Expected range: ~100 to ~4000 depending on exact thresholds/methods
        if sig_count > 50:
            score += 20
            feedback.append(f"Found {sig_count} significant genes (biologically plausible) (+20)")
        elif sig_count > 0:
            score += 10
            feedback.append(f"Found {sig_count} significant genes (low count) (+10)")
        else:
            feedback.append("No significant genes found (check filtering logic)")
    else:
        feedback.append("DE results file missing or not created during task")

    # --- Criterion 2: Visualizations (30 pts) ---
    plots = result.get('plots', {})
    
    # Volcano Plot
    if plots.get('volcano_exists'):
        size = plots.get('volcano_size', 0)
        if size > 10000: # >10KB
            score += 15
            feedback.append("Volcano plot created successfully (+15)")
        else:
            score += 5
            feedback.append("Volcano plot file exists but is very small (+5)")
    else:
        feedback.append("Volcano plot missing")
        
    # Heatmap
    if plots.get('heatmap_exists'):
        size = plots.get('heatmap_size', 0)
        if size > 10000: # >10KB
            score += 15
            feedback.append("Heatmap created successfully (+15)")
        else:
            score += 5
            feedback.append("Heatmap file exists but is very small (+5)")
    else:
        feedback.append("Heatmap missing")

    # --- Criterion 3: Summary Data (15 pts) ---
    summ = result.get('summary', {})
    if summ.get('exists') and summ.get('valid'):
        score += 15
        feedback.append("Summary CSV created (+15)")
    else:
        feedback.append("Summary CSV missing or invalid")

    # --- Criterion 4: Script Quality (15 pts) ---
    script = result.get('script', {})
    if script.get('modified'):
        score += 5
        feedback.append("Analysis script modified (+5)")
        if script.get('content_check'):
            score += 10
            feedback.append("Script contains expected analysis keywords (+10)")
        else:
            feedback.append("Script missing key analysis function calls")
    else:
        feedback.append("Starter script was not modified")

    # Pass logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }