#!/usr/bin/env python3
"""
Verifier for Site Architecture Visualization task.

SCORING CRITERIA:
1. Output HTML file exists (30 pts)
2. File was created AFTER task start (20 pts)
3. File contains valid graph content (HTML + target domain data) (30 pts)
4. Visualization window was detected OR App was running (10 pts)
5. VLM Verification of final screenshot (10 pts)

Pass Threshold: 80 points (Must produce a valid graph file)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_site_architecture_visualization(traj, env_info, task_info):
    """
    Verify the agent generated the site architecture graph.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria

    # Criterion 1: File Exists (30 pts)
    if result.get("file_exists", False):
        score += 30
        feedback_parts.append("Output file exists (30/30)")
    else:
        feedback_parts.append("Output file site_graph.html NOT found (0/30)")

    # Criterion 2: Freshness (20 pts)
    if result.get("file_created_during_task", False):
        score += 20
        feedback_parts.append("File created during task (20/20)")
    elif result.get("file_exists", False):
        feedback_parts.append("File exists but is STALE (modified before task) (0/20)")
    else:
        feedback_parts.append("No file to check timestamp (0/20)")

    # Criterion 3: Content Validation (30 pts)
    # Requires HTML structure AND specific domain data
    content_valid = result.get("content_looks_like_html_graph", False)
    domain_found = result.get("target_domain_in_file", False)
    
    if content_valid and domain_found:
        score += 30
        feedback_parts.append("File content valid and contains target domain data (30/30)")
    elif content_valid:
        score += 15
        feedback_parts.append("File is HTML/Graph but missing specific target domain data (15/30)")
    else:
        feedback_parts.append("File content invalid or empty (0/30)")

    # Criterion 4: Application State (10 pts)
    # Did they actually run the app?
    if result.get("visualization_window_detected", False):
        score += 10
        feedback_parts.append("Visualization window detected (10/10)")
    elif result.get("app_running", False):
        score += 5
        feedback_parts.append("App running, but visualization window not found (5/10)")
    else:
        feedback_parts.append("App not running (0/10)")

    # Criterion 5: VLM Verification (10 pts)
    # Check if final screenshot looks like a graph or the export dialog
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if query_vlm and get_final_screenshot:
        try:
            final_img = get_final_screenshot(traj)
            prompt = """
            Look at this screenshot from Screaming Frog SEO Spider.
            Does it show:
            1. A network graph, force-directed diagram, or visualization window?
            2. A 'Save As' or 'Export' dialog?
            3. The Screaming Frog interface?
            
            Reply with YES if any of these are visible, otherwise NO.
            """
            vlm_res = query_vlm(prompt=prompt, image=final_img)
            if vlm_res.get('success'):
                resp = vlm_res.get('response', '').lower()
                if 'yes' in resp:
                    vlm_score = 10
                    feedback_parts.append("VLM confirms visual evidence (10/10)")
                else:
                    feedback_parts.append("VLM did not see graph/interface (0/10)")
        except Exception:
            feedback_parts.append("VLM check failed (0/10)")
    
    score += vlm_score

    # Final result
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }