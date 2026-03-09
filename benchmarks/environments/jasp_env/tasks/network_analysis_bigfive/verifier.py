#!/usr/bin/env python3
"""
Verifier for network_analysis_bigfive task.
Checks for valid JASP project file, report content, and uses VLM to verify plots.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_network_analysis_bigfive(traj, env_info, task_info):
    """
    Verify the JASP network analysis task.
    
    Criteria:
    1. JASP project file exists, is a valid zip, and created during task.
    2. Text report exists and contains required keywords/values.
    3. VLM verifies Network Plot and Centrality Plot were generated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_variables = metadata.get('variables', ["Neuroticism", "Extraversion", "Openness", "Agreeableness", "Conscientiousness"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load basic result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # 2. Verify JASP File (25 points)
    jasp_score = 0
    if task_result.get("jasp_file_exists") and task_result.get("jasp_created_during_task"):
        jasp_path = metadata.get("expected_jasp_file")
        with tempfile.NamedTemporaryFile(suffix='.jasp') as jasp_tmp:
            try:
                copy_from_env(jasp_path, jasp_tmp.name)
                # JASP files are zipped archives. Check if it's a valid zip.
                if zipfile.is_zipfile(jasp_tmp.name):
                    jasp_score = 25
                    feedback_parts.append("Valid JASP project file saved.")
                else:
                    jasp_score = 10
                    feedback_parts.append("JASP file saved but is not a valid archive.")
            except Exception as e:
                feedback_parts.append(f"Failed to verify JASP file content: {e}")
    else:
        feedback_parts.append("JASP project file not found or not created during task.")
    
    score += jasp_score

    # 3. Verify Report Content (35 points)
    report_score = 0
    report_path = metadata.get("expected_report_file")
    
    if task_result.get("report_file_exists") and task_result.get("report_created_during_task"):
        try:
            with tempfile.NamedTemporaryFile(mode='w+', suffix='.txt') as report_tmp:
                copy_from_env(report_path, report_tmp.name)
                report_tmp.seek(0)
                content = report_tmp.read().lower()
                
                # Check for variable names
                found_vars = [v for v in expected_variables if v.lower() in content]
                if len(found_vars) >= 2:
                    report_score += 10
                    feedback_parts.append(f"Report mentions variables ({len(found_vars)}/5 found).")
                
                # Check for centrality keywords
                if "strength" in content:
                    report_score += 10
                    feedback_parts.append("Report includes Strength centrality.")
                if "betweenness" in content:
                    report_score += 5
                    feedback_parts.append("Report includes Betweenness centrality.")
                
                # Check for numeric values (basic check)
                import re
                numbers = re.findall(r'\d+\.?\d*', content)
                if len(numbers) >= 2:
                    report_score += 10
                    feedback_parts.append("Report contains numeric values.")
                else:
                    feedback_parts.append("Report missing numeric values.")
                    
        except Exception as e:
            feedback_parts.append(f"Failed to read report: {e}")
    else:
        feedback_parts.append("Report file not found.")

    score += report_score

    # 4. VLM Verification (40 points)
    # Check if plots were visible during the trajectory
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    if frames:
        prompt = """
        Analyze these screenshots of JASP statistical software.
        1. Is a Network Plot visible (a graph with nodes connected by lines)?
        2. Is a Centrality Plot visible (a bar chart or dot plot showing Strength/Betweenness/Closeness)?
        3. Are the nodes labeled with personality traits (e.g., Neuroticism, Extraversion)?
        
        Respond in JSON:
        {
            "network_plot_visible": true/false,
            "centrality_plot_visible": true/false,
            "labels_visible": true/false
        }
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("network_plot_visible"):
                vlm_score += 20
                feedback_parts.append("VLM: Network plot detected.")
            else:
                feedback_parts.append("VLM: No network plot detected.")
                
            if parsed.get("centrality_plot_visible"):
                vlm_score += 15
                feedback_parts.append("VLM: Centrality plot detected.")
            else:
                feedback_parts.append("VLM: No centrality plot detected.")

            if parsed.get("labels_visible"):
                vlm_score += 5
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("VLM verification failed.")
            # Fallback points if files are perfect
            if jasp_score == 25 and report_score >= 25:
                vlm_score += 20
                feedback_parts.append("Fallback score awarded for VLM failure.")

    score += vlm_score

    # Final logic
    passed = score >= 60 and jasp_score > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }