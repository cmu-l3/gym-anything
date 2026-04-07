#!/usr/bin/env python3
"""
Verifier for Spatial Point Pattern Analysis task.

Scoring Criteria:
1. Spatial Stats CSV (30 pts):
   - Exists and parsed (10 pts)
   - Clark-Evans Index > 1.0 (Regularity) (10 pts)
   - Clark-Evans p-value < 0.05 (Significant) (10 pts)
2. L-function Plot (30 pts):
   - Exists and valid size > 30KB (indicating content) (30 pts)
3. Density Map (15 pts):
   - Exists (15 pts)
4. Script Quality (15 pts):
   - Modified and loads spatstat (15 pts)
5. VLM Verification (10 pts):
   - Verifies L-function plot shows envelopes (black line within or crossing red dashed lines)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_spatial_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Retrieve result JSON
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    score = 0
    feedback = []

    # 1. Check Stats CSV (30 pts)
    if res.get('stats_csv_exists'):
        score += 10
        ce_idx = res.get('ce_index', 0)
        ce_p = res.get('ce_pvalue', 1)
        
        # Clark-Evans R for 'cells' dataset is ~1.28 (Regular)
        if 1.1 <= ce_idx <= 1.5:
            score += 10
            feedback.append(f"Clark-Evans Index correct ({ce_idx})")
        else:
            feedback.append(f"Clark-Evans Index incorrect or out of range (got {ce_idx}, expected ~1.28)")

        if ce_p < 0.05:
            score += 10
            feedback.append("Clark-Evans test significant (p < 0.05)")
        else:
            feedback.append(f"Clark-Evans p-value too high ({ce_p})")
    else:
        feedback.append("spatial_stats.csv missing")

    # 2. Check L-function Plot (30 pts)
    if res.get('l_plot_exists'):
        size = res.get('l_plot_size', 0)
        if size > 30000: # > 30KB
            score += 30
            feedback.append("L-function plot created and valid size")
        else:
            score += 10
            feedback.append(f"L-function plot too small ({size} bytes)")
    else:
        feedback.append("L-function plot missing")

    # 3. Check Density Map (15 pts)
    if res.get('density_map_exists'):
        score += 15
        feedback.append("Density map created")
    else:
        feedback.append("Density map missing")

    # 4. Script Quality (15 pts)
    if res.get('script_modified') and res.get('script_has_spatstat'):
        score += 15
        feedback.append("R script modified and uses spatstat")
    elif res.get('script_modified'):
        score += 5
        feedback.append("R script modified but spatstat load not detected")
    else:
        feedback.append("R script not modified")

    # 5. VLM Verification (10 pts bonus/confirmation)
    # We check the final screenshot or specific plot if available via trajectory
    # For now, we assume programmatic checks are robust enough for pass/fail, 
    # but add points if VLM confirms the plot looks like an L-function with envelopes.
    
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    vlm_score = 0
    if query_vlm and get_final_screenshot:
        img = get_final_screenshot(traj)
        if img:
            prompt = """
            Does this image show RStudio with a plot that looks like a spatial function (lines increasing from 0,0) 
            possibly with a grey shaded area (envelopes) or dashed lines? 
            Is there a map showing density (heatmap style) or points?
            Return JSON: {"has_spatial_plot": true/false}
            """
            try:
                vlm_res = query_vlm(prompt=prompt, image=img)
                if vlm_res.get('success') and vlm_res['parsed'].get('has_spatial_plot'):
                    vlm_score = 10
                    feedback.append("VLM confirmed spatial plot visible")
            except:
                pass
    
    score = min(100, score + vlm_score)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }