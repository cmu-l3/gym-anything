#!/usr/bin/env python3
"""
Verifier for spatial_autocorrelation_sids task.

Scoring (100 points total):
  1. Statistical Accuracy (Global Moran's I) - 30 pts
     - Computed value matches expected (~0.42) within tolerance
     - Indicates correct rate calculation (raw counts would be different)
  2. Data Output (LISA CSV) - 20 pts
     - CSV exists, new, has required columns
  3. Visualization (Map & Scatterplot) - 30 pts
     - Files exist, substantial size
     - VLM verifies map content
  4. Process (Script & Deps) - 20 pts
     - Script modified, uses spdep functions

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/spatial_autocorrelation_sids_result.json"

# VLM Prompt for Map Verification
MAP_VERIFICATION_PROMPT = """You are verifying a spatial analysis task result.
The image should be a map of North Carolina counties showing SIDS (Sudden Infant Death Syndrome) clusters (LISA analysis).

Look for:
1. A map shape resembling North Carolina (wide, ~100 counties).
2. Choropleth coloring (different colors for different regions).
3. A legend indicating cluster types like "High-High", "Low-Low", "Not Significant", or similar statistical labels.
4. Specific hotspots: typically clusters in the south/southeast are highlighted (often Red for High-High).

Respond in JSON format:
{
    "is_nc_map": true/false,
    "has_choropleth_colors": true/false,
    "has_cluster_legend": true/false,
    "confidence": "low"/"medium"/"high",
    "description": "brief description of what you see"
}
"""

def verify_spatial_autocorrelation_sids(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Result file not found"}
        except json.JSONDecodeError:
            return {"passed": False, "score": 0, "feedback": "Result JSON malformed"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Statistical Accuracy (30 pts)
    expected_moran = task_info['metadata'].get('expected_moran_i', 0.42)
    tolerance = task_info['metadata'].get('moran_tolerance', 0.05)
    
    extracted_i = result.get('global_i_extracted', "")
    
    stat_pass = False
    if result.get('global_txt_new'):
        try:
            val = float(extracted_i)
            diff = abs(val - expected_moran)
            if diff <= tolerance:
                score += 30
                stat_pass = True
                feedback.append(f"Global Moran's I ({val}) matches expected ({expected_moran}) (30/30)")
            else:
                score += 10
                feedback.append(f"Global Moran's I computed ({val}) but outside tolerance (expected ~{expected_moran}). Check rate calculation. (10/30)")
        except ValueError:
            score += 5
            feedback.append("Global Moran's I file exists but value could not be parsed (5/30)")
    else:
        feedback.append("Global Moran's I output missing (0/30)")

    # 2. Data Output (20 pts)
    if result.get('lisa_csv_new'):
        score += 10
        feedback.append("LISA CSV created (10/10)")
        if result.get('lisa_has_rate_col') and result.get('lisa_has_pval_col'):
            score += 10
            feedback.append("LISA CSV has Rate and P-value columns (10/10)")
        else:
            feedback.append("LISA CSV missing required columns (0/10)")
    else:
        feedback.append("LISA CSV output missing (0/20)")

    # 3. Visualization (30 pts)
    # Scatterplot (10 pts)
    if result.get('scatter_png_new') and result.get('scatter_size_kb', 0) > 10:
        score += 10
        feedback.append("Moran scatterplot created (10/10)")
    else:
        feedback.append("Moran scatterplot missing or empty (0/10)")

    # Map (20 pts)
    map_score = 0
    if result.get('map_png_new') and result.get('map_size_kb', 0) > 20:
        map_score += 10
        feedback.append("Cluster map file created (10/10)")
        
        # VLM Check on map content if file exists
        if query_vlm:
            # We need to get the actual image file from container for VLM
            # But here we typically use the final screenshot or traj frames
            # If the map is open in RStudio plot pane, it will be in screenshot
            # Ideally we'd verify the file content itself, but `query_vlm` takes `image` object
            # For now, we'll check the final screenshot for map evidence
            
            final_ss = get_final_screenshot(traj) if get_final_screenshot else None
            if final_ss:
                vlm_res = query_vlm(prompt=MAP_VERIFICATION_PROMPT, image=final_ss)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_nc_map') and parsed.get('has_choropleth_colors'):
                    map_score += 10
                    feedback.append("VLM confirms map shows NC clusters (10/10)")
                else:
                    feedback.append(f"VLM did not recognize map in screenshot: {parsed.get('description')} (0/10)")
            else:
                feedback.append("No screenshot available for VLM check (0/10)")
        else:
            # If no VLM, give points for file existence/size logic being strong
            map_score += 10
            feedback.append("VLM skipped, file checks passed (10/10)")
    else:
        feedback.append("Cluster map missing or too small (0/20)")
    
    score += map_score

    # 4. Process (20 pts)
    if result.get('script_modified'):
        score += 10
        feedback.append("R script modified (10/10)")
    else:
        feedback.append("R script not modified (0/10)")
        
    if result.get('has_spdep_calls'):
        score += 10
        feedback.append("Script uses spdep functions (10/10)")
    else:
        feedback.append("Script missing spdep calls (0/10)")

    return {
        "passed": score >= 60 and stat_pass,
        "score": score,
        "feedback": " | ".join(feedback)
    }