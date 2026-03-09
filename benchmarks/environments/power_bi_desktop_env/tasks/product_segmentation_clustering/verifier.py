#!/usr/bin/env python3
"""
Verifier for product_segmentation_clustering task.

Scoring Criteria:
1. File Saved (10 pts): Product_Segmentation.pbix exists.
2. Anti-Gaming (10 pts): File created during task window.
3. Scatter Chart (20 pts): Visual present.
4. Table Visual (20 pts): Visual present.
5. Clustering Implementation (20 pts): "Product_Segment" field found in DataModel.
6. VLM Verification (20 pts): Screenshot shows distinct colored clusters in scatter plot.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logger = logging.getLogger(__name__)

def verify_product_segmentation(traj, env_info, task_info):
    # 1. Setup and retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Initialize Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence (10 pts)
    if result.get('file_exists', False):
        score += 10
        feedback_parts.append("File saved successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Product_Segmentation.pbix not found."}

    # Criterion 2: Timestamp Check (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
    else:
        feedback_parts.append("Warning: File timestamp predates task start (anti-gaming penalty).")

    # Criterion 3: Visuals Check (40 pts total)
    has_scatter = result.get('has_scatter', False)
    has_table = result.get('has_table', False)
    
    if has_scatter:
        score += 20
        feedback_parts.append("Scatter chart detected.")
    else:
        feedback_parts.append("Missing Scatter chart.")
        
    if has_table:
        score += 20
        feedback_parts.append("Summary table detected.")
    else:
        feedback_parts.append("Missing summary table.")

    # Criterion 4: Clustering Logic Check (20 pts)
    # Checked via string search in DataModel binary for "Product_Segment"
    if result.get('cluster_field_found', False):
        score += 20
        feedback_parts.append("Clustering field 'Product_Segment' found in data model.")
    else:
        feedback_parts.append("Could not confirm 'Product_Segment' field. Did you rename the cluster group?")

    # Criterion 5: VLM Verification (20 pts)
    # Check if the scatter plot actually looks clustered (different colors)
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this Power BI report screenshot.
        1. Do you see a Scatter Chart?
        2. Are the dots in the scatter chart colored differently (indicating clusters/segments)?
        3. Do you see a legend indicating 'Product_Segment' or similar?
        
        Return JSON: {"scatter_present": bool, "clusters_visible": bool, "legend_visible": bool}
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('scatter_present', False):
                # We already gave points for programmatic detection, checking visual quality here
                pass
                
            if parsed.get('clusters_visible', False):
                vlm_score += 10
                feedback_parts.append("VLM confirmed visible clusters.")
            else:
                feedback_parts.append("VLM could not clearly see clusters.")
                
            if parsed.get('legend_visible', False):
                vlm_score += 10
                feedback_parts.append("VLM confirmed legend.")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic check passed, give partial VLM credit
            if has_scatter and result.get('cluster_field_found', False):
                vlm_score += 10
    
    score += vlm_score

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }