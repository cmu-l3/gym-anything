#!/usr/bin/env python3
"""
Verifier for generate_slope_analysis task.

Verification Strategy:
1. File-based verification: Checks if `slope_analysis.top` and `slope_report.txt` are created.
2. Anti-gaming check: File modification timestamps must be strictly after the task started.
3. Content validation: The report must contain mentions of slope intervals and plausible percentage ranges.
4. Trajectory VLM Check: Confirms the agent achieved a colored slope map visual state in TopoCal.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a completed CAD software task in TopoCal.
The user was asked to generate a "Slope Analysis" (Análisis de pendientes).

Look at the provided trajectory images and determine:
1. Is TopoCal open and showing a 3D terrain triangulation (MDT / TIN) in the viewport?
2. Has the terrain been colored with multiple distinct solid colors (e.g., green, yellow, orange, red) indicating different slope zones/gradients?
3. Can you confirm the presence of a color legend or configuration dialog indicating a slope/taludes mapping?

Return a JSON object:
{
    "terrain_visible": true/false,
    "slope_colors_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Explain what you see regarding the slope analysis visualization."
}
"""

def verify_generate_slope_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    # Extract JSON results from Windows environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task state from environment."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Project Check (25 pts)
    proj_exists = result.get('project_exists', False)
    proj_created = result.get('project_created_during_task', False)
    proj_size = result.get('project_size', 0)
    
    if proj_exists and proj_created:
        if proj_size > 1024:
            score += 25
            feedback_parts.append("✅ Project saved successfully with changes")
        else:
            score += 10
            feedback_parts.append("⚠️ Project file saved but size seems too small")
    elif proj_exists:
        feedback_parts.append("❌ Project file exists but was not created/modified during task")
    else:
        feedback_parts.append("❌ slope_analysis.top not found")

    # 2. Report Existence Check (15 pts)
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    report_content = result.get('report_content', '').lower()
    
    if report_exists and report_created:
        score += 15
        feedback_parts.append("✅ Report file created")
    elif report_exists:
        feedback_parts.append("❌ Report file exists but was not created during task")
    else:
        feedback_parts.append("❌ slope_report.txt not found")

    # 3. Report Content Check (25 pts)
    content_pts = 0
    if report_exists and len(report_content) > 10:
        # Look for numbers/keywords that indicate slope ranges were exported
        has_15 = '15' in report_content
        has_30 = '30' in report_content
        has_50 = '50' in report_content
        
        has_min = 'min' in report_content or 'mín' in report_content
        has_max = 'max' in report_content or 'máx' in report_content
        has_avg = 'avg' in report_content or 'average' in report_content or 'media' in report_content or 'promedio' in report_content
        
        ranges_met = sum([has_15, has_30, has_50])
        stats_met = sum([has_min, has_max, has_avg])
        
        if ranges_met >= 2:
            content_pts += 15
            feedback_parts.append("✅ Report contains required slope classification zones")
        else:
            feedback_parts.append("❌ Report does not clearly list the requested slope classification zones")
            
        if stats_met >= 2:
            content_pts += 10
            feedback_parts.append("✅ Report contains min/max/avg statistical parameters")
        else:
            feedback_parts.append("❌ Report missing some statistical parameters (min/max/avg)")
            
    score += content_pts

    # 4. VLM Verification (35 pts)
    vlm_pts = 0
    if query_vlm:
        # Sample frames from trajectory
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        # We want to check frames near the end, where the visual result would be
        frames = sample_trajectory_frames(traj, n=3, strategy="recent")
        final_img = get_final_screenshot(traj)
        
        if final_img:
            eval_images = frames + [final_img]
            try:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, images=eval_images)
                if vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("slope_colors_visible"):
                        vlm_pts = 35
                        feedback_parts.append("✅ VLM verified colored slope map is visible in TopoCal")
                    elif parsed.get("terrain_visible"):
                        vlm_pts = 10
                        feedback_parts.append("⚠️ VLM verified terrain is visible, but could not confirm colored slope zones")
                    else:
                        feedback_parts.append("❌ VLM could not verify slope analysis in the application")
                else:
                    feedback_parts.append("⚠️ VLM evaluation failed")
            except Exception as e:
                logger.error(f"VLM check failed: {e}")
                feedback_parts.append("⚠️ VLM evaluation encountered an error")
    else:
        # Grant partial heuristic if VLM unavailable but file is created
        if report_exists and report_created and content_pts == 25:
            vlm_pts = 35
            feedback_parts.append("⚠️ VLM unavailable, trusting exact report content match")

    score += vlm_pts
    
    # Require at least some file-system proof and visual/content proof
    passed = score >= 60 and report_exists and proj_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }