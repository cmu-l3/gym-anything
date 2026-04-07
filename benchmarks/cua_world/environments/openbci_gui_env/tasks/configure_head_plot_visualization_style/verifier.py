#!/usr/bin/env python3
"""
Verifier for configure_head_plot_visualization_style task.

Verifies:
1. Agent created the requested screenshot file (head_plot_viridis.png).
2. Screenshot shows OpenBCI GUI with Head Plot widget.
3. Head Plot uses 'Smoothed' style (contours/heatmap) not 'Mesh'.
4. Head Plot uses 'Viridis' colormap (purple-blue-green-yellow).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_head_plot_style(traj, env_info, task_info):
    """
    Verify the Head Plot configuration using VLM analysis of the agent's screenshot.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_screenshot_path', '/home/ga/Documents/OpenBCI_GUI/Screenshots/head_plot_viridis.png')

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Task Result JSON
    # ================================================================
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_json_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)

    # ================================================================
    # 2. Verify File Existence & Anti-Gaming (30 pts)
    # ================================================================
    file_exists = task_result.get('file_exists', False)
    created_during = task_result.get('file_created_during_task', False)
    
    if file_exists:
        if created_during:
            score += 30
            feedback_parts.append("Screenshot file created successfully.")
        else:
            score += 10 # Penalty for using old file
            feedback_parts.append("Screenshot file exists but timestamp is old.")
    else:
        feedback_parts.append(f"Expected screenshot not found at {expected_path}.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # ================================================================
    # 3. Retrieve and Analyze Screenshot (70 pts)
    # ================================================================
    
    # We need to analyze the specific screenshot the agent took, 
    # as instructed in the task ("take a screenshot of the configured Head Plot").
    # If that fails, we fallback to the final system screenshot, but the task specifically requests a file.
    
    agent_screenshot_local = tempfile.mktemp(suffix='.png')
    image_to_analyze = None
    
    try:
        copy_from_env(expected_path, agent_screenshot_local)
        image_to_analyze = agent_screenshot_local
    except Exception:
        feedback_parts.append("Could not retrieve agent's screenshot for analysis.")
    
    if image_to_analyze:
        # Construct VLM Prompt
        prompt = """
        Analyze this screenshot of the OpenBCI GUI. Focus on the 'Head Plot' or topomap widget.
        
        1. Is the 'Head Plot' widget visible? (It shows a circular head map with electrode signals).
        2. What is the Plot Type? 
           - 'Smoothed' / 'Contours': A continuous gradient heatmap.
           - 'Mesh' / 'Points': Discrete triangles, lines, or dots.
        3. What is the Colormap / Color Palette?
           - 'Viridis': Distinctive dark purple background transitioning to blue, green, and yellow.
           - 'Jet' / 'Rainbow': Dark blue background transitioning to cyan, yellow, and red.
           - 'Greyscale': Black and white.
        
        Answer strictly in JSON format:
        {
            "head_plot_visible": true/false,
            "plot_type": "smoothed" or "mesh" or "other",
            "colormap": "viridis" or "jet" or "other",
            "reasoning": "short explanation"
        }
        """
        
        try:
            vlm_response = query_vlm(
                prompt=prompt,
                image=image_to_analyze
            )
            
            analysis = vlm_response.get('parsed', {})
            logger.info(f"VLM Analysis: {analysis}")
            
            # Check Widget Visibility
            if analysis.get('head_plot_visible', False):
                score += 10
                feedback_parts.append("Head Plot widget is visible.")
                
                # Check Plot Type (Smoothed)
                p_type = analysis.get('plot_type', '').lower()
                if 'smooth' in p_type or 'contour' in p_type:
                    score += 30
                    feedback_parts.append("Plot style is Smoothed.")
                else:
                    feedback_parts.append(f"Plot style appears to be {p_type} (expected Smoothed).")
                
                # Check Colormap (Viridis)
                c_map = analysis.get('colormap', '').lower()
                if 'viridis' in c_map:
                    score += 30
                    feedback_parts.append("Colormap is Viridis.")
                elif 'jet' in c_map or 'rainbow' in c_map:
                    feedback_parts.append("Colormap appears to be default Jet/Rainbow (expected Viridis).")
                else:
                    feedback_parts.append(f"Colormap appears to be {c_map} (expected Viridis).")
            else:
                feedback_parts.append("Head Plot widget was not detected in the screenshot.")
                
        except Exception as e:
            logger.error(f"VLM query failed: {e}")
            feedback_parts.append("Verification failed due to VLM error.")
    
    # Clean up
    if os.path.exists(agent_screenshot_local):
        os.unlink(agent_screenshot_local)

    # Pass threshold
    # 30 (file) + 10 (visible) + 30 (smooth) + 30 (viridis) = 100
    # Must have at least file + visible + (smooth OR viridis) roughly
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }