#!/usr/bin/env python3
"""
Verifier for credit_risk_explainer task.

Scoring (100 pts total):
1. Model Performance (Metrics CSV) - 30 pts
   - CSV Exists & New: 10 pts
   - Accuracy > 0.65: 10 pts
   - AUC > 0.65: 10 pts
2. Variable Importance Plot - 20 pts
   - Exists & New: 10 pts
   - File size > 5KB: 10 pts
3. Partial Dependence Plot - 20 pts
   - Exists & New: 10 pts
   - File size > 5KB: 10 pts
4. Workflow/Script - 10 pts
   - Script uses correct libraries: 10 pts
5. VLM Verification - 20 pts
   - Validates that the plots actually contain content (not blank)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_credit_risk_explainer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Metrics Check (30 pts)
    metrics = result.get("metrics_csv", {})
    if metrics.get("exists") and metrics.get("is_new"):
        score += 10
        feedback.append("Metrics CSV created.")
        
        acc = metrics.get("accuracy", 0)
        auc = metrics.get("auc", 0)
        
        if acc > 0.65:
            score += 10
            feedback.append(f"Accuracy pass ({acc:.2f} > 0.65).")
        else:
            feedback.append(f"Accuracy fail ({acc:.2f}).")
            
        if auc > 0.65:
            score += 10
            feedback.append(f"AUC pass ({auc:.2f} > 0.65).")
        else:
            feedback.append(f"AUC fail ({auc:.2f}).")
    else:
        feedback.append("Metrics CSV missing or stale.")

    # 2. Variable Importance Plot (20 pts)
    imp_plot = result.get("imp_plot", {})
    imp_exists = False
    if imp_plot.get("exists") and imp_plot.get("is_new"):
        score += 10
        feedback.append("Importance plot created.")
        if imp_plot.get("size_bytes", 0) > 5000:
            score += 10
            imp_exists = True
        else:
            feedback.append("Importance plot too small (empty?).")
    else:
        feedback.append("Importance plot missing.")

    # 3. PDP Plot (20 pts)
    pdp_plot = result.get("pdp_plot", {})
    pdp_exists = False
    if pdp_plot.get("exists") and pdp_plot.get("is_new"):
        score += 10
        feedback.append("PDP plot created.")
        if pdp_plot.get("size_bytes", 0) > 5000:
            score += 10
            pdp_exists = True
        else:
            feedback.append("PDP plot too small (empty?).")
    else:
        feedback.append("PDP plot missing.")

    # 4. Script Logic (10 pts)
    script = result.get("script", {})
    if script.get("used_packages"):
        score += 10
        feedback.append("Script uses ML/Explainability packages.")
    else:
        feedback.append("Script missing required package calls.")

    # 5. VLM Verification (20 pts)
    # Only run if files exist to avoid unnecessary API calls
    if query_vlm and (imp_exists or pdp_exists):
        # We rely on the final screenshot or trajectory frames.
        # Ideally we'd look at the specific png files, but the standard interface 
        # usually passes screenshots. We'll check the final screenshot for plot visibility.
        final_img = get_final_screenshot(traj)
        if final_img:
            prompt = """
            Analyze this screenshot of RStudio.
            Does it show:
            1. A Variable Importance Plot (usually a horizontal bar chart of features)?
            2. A Partial Dependence Plot (usually a line curve)?
            3. R code in the editor related to 'ranger', 'randomForest', or 'pdp'?
            
            Return JSON: {"imp_plot_visible": bool, "pdp_plot_visible": bool, "code_visible": bool}
            """
            try:
                vlm_res = query_vlm(image=final_img, prompt=prompt)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    # We give points if VLM sees them OR if files verified above were substantial
                    # This is a bonus/validation layer.
                    
                    # Actually, let's use VLM to validate the files specifically if we could, 
                    # but here we validate the screenshot state.
                    if parsed.get("imp_plot_visible") or parsed.get("pdp_plot_visible"):
                        score += 20
                        feedback.append("VLM confirms plots visible in RStudio.")
                    elif parsed.get("code_visible"):
                        score += 10 # Partial credit if only code seen
                        feedback.append("VLM confirms code visible.")
                    else:
                        # Fallback: if we confirmed file existence and size programmatically,
                        # we assume they are valid even if not currently on screen (maybe closed).
                        # We grant the points if files passed checks.
                        if imp_exists and pdp_exists:
                             score += 20
                             feedback.append("Files valid (VLM didn't see active plot pane, but files exist).")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                # Fallback to file checks
                if imp_exists and pdp_exists:
                    score += 20

    # Fallback if no VLM but files are good
    if not query_vlm and imp_exists and pdp_exists:
        score += 20
        feedback.append("VLM skipped, files validated programmatically.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }