#!/usr/bin/env python3
"""
Verifier for ecommerce_cohort_retention task.

Scoring Breakdown (100 pts total):
1. Script & File Artifacts (20 pts)
   - Script modified (5)
   - CSV exists & new (5)
   - Plot exists & new (5)
   - Plot size > 20KB (5)
2. Data Accuracy (50 pts)
   - CSV has correct columns (10)
   - Retention rates match ground truth within tolerance (40)
3. Visual Verification (30 pts)
   - VLM confirms heatmap structure (axes, gradient, triangular/cohort shape)

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for Heatmap
HEATMAP_PROMPT = """You are analyzing a data visualization created by an agent.
The task was to create a "Cohort Retention Heatmap".

Look for the following:
1. Chart Type: Is it a heatmap (grid of colored cells)?
2. Axes:
   - Y-axis should show dates/months (e.g., "2010-12", "Dec 2010").
   - X-axis should show "Cohort Index" or number of months (0, 1, 2...).
3. Data Pattern:
   - Cohort retention usually drops over time.
   - Column 0 (first month) is often 100% (or removed).
   - The shape is often triangular or rectangular with missing data in bottom-right (since newer cohorts have less history).
   - Colors should indicate value magnitude.

Respond in JSON format:
{
    "is_heatmap": true/false,
    "has_date_axis": true/false,
    "has_index_axis": true/false,
    "triangular_shape_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "..."
}
"""

def verify_cohort_retention(traj, env_info, task_info):
    """Verify the cohort retention task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    score = 0
    feedback = []

    # 1. Artifact Check (20 pts)
    if result.get('script_modified', False):
        score += 5
        feedback.append("Script modified (+5)")
    else:
        feedback.append("Script not modified (0)")

    if result.get('csv_exists') and result.get('csv_is_new'):
        score += 5
        feedback.append("Output CSV created (+5)")
    else:
        feedback.append("Output CSV missing or old (0)")

    if result.get('plot_exists') and result.get('plot_is_new'):
        score += 5
        feedback.append("Heatmap PNG created (+5)")
    
    plot_size = result.get('plot_size_bytes', 0)
    if plot_size > 20000: # >20KB
        score += 5
        feedback.append("Heatmap file size reasonable (+5)")
    elif plot_size > 0:
        feedback.append("Heatmap file too small (possible empty plot) (0)")

    # 2. Data Accuracy (50 pts)
    metrics = result.get('accuracy_metrics', {})
    
    if "error" in metrics:
        feedback.append(f"Data accuracy check failed: {metrics['error']} (0/50)")
    else:
        # Check columns
        cols = metrics.get('columns_found', [])
        required = ['retention', 'rate'] # Loose match logic handled in export script
        if any('retention' in c for c in cols) or any('rate' in c for c in cols):
             score += 10
             feedback.append("CSV has retention columns (+10)")
        else:
             feedback.append("CSV missing 'retention' or 'rate' column (0)")

        # Check values
        # The export script calculates an accuracy score based on deviation
        acc_score = metrics.get('accuracy_score', 0)
        # We allow up to 40 points here. The script returns 0-100, we scale it.
        # If perfect match (100) -> 40 points.
        # If 5% off -> score drops.
        
        points_earned = min(40, max(0, acc_score * 0.4))
        score += points_earned
        feedback.append(f"Data values match ground truth: {points_earned:.1f}/40 pts")
        
        # Debug info
        if 'gt_mean_idx1' in metrics:
             feedback.append(f"(Stats: Agent Mean={metrics['agent_mean_idx1']:.3f}, GT={metrics['gt_mean_idx1']:.3f})")

    # 3. Visual Verification (30 pts)
    # We check the final screenshot (desktop) OR verify the image file if we could fetch it.
    # Since we can't fetch the PNG file content easily to Python via `copy_from_env` without extra temp steps,
    # we'll use the final desktop screenshot which should ideally show the plot if the agent followed instructions to display it,
    # OR we rely on the agent having saved it. 
    # Better: Use `get_final_screenshot` which captures the desktop. The plot might be visible in RStudio Plots pane.
    
    if query_vlm:
        final_ss = get_final_screenshot(traj)
        if final_ss:
            vlm_res = query_vlm(prompt=HEATMAP_PROMPT, image=final_ss)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_heatmap'):
                    score += 15
                    feedback.append("VLM confirms heatmap visualization (+15)")
                if parsed.get('triangular_shape_visible') or parsed.get('has_index_axis'):
                    score += 15
                    feedback.append("VLM confirms cohort structure (+15)")
            else:
                feedback.append("VLM analysis failed (0)")
        else:
            feedback.append("No screenshot available for VLM (0)")
    else:
        # Fallback if VLM not available but file exists
        if result.get('plot_exists'):
             score += 15
             feedback.append("VLM unavailable, granting partial credit for file existence (+15)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }