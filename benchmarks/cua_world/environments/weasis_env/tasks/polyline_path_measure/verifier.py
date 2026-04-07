#!/usr/bin/env python3
"""
Verifier for Polyline Path Measurement task in Weasis.

Evaluates:
1. Anti-gaming check (file timestamps must be after task started)
2. Existence and size of the output files
3. Semantic parsing of the text report (finding valid segments & lengths)
4. Trajectory-based VLM visual check (verifying polyline + measurement labels actually rendered)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_polyline_path_measure(traj, env_info, task_info):
    # Enforce safe retrieval of data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely load the generated JSON
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

    score = 0
    feedback_parts = []

    # 1. File existence (Report) (10 points)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    
    if report_exists and len(report_content.strip()) > 0:
        score += 10
        feedback_parts.append("Report file exists and is non-empty")
    else:
        feedback_parts.append("Report file missing or empty")

    # 2. Text Parsing: Tool, Segments, Length (40 points total)
    tool_match = re.search(r"Tool:\s*(.*)", report_content, re.IGNORECASE)
    segments_match = re.search(r"Segments:\s*(\d+)", report_content, re.IGNORECASE)
    length_match = re.search(r"Total Length:\s*([\d.]+)", report_content, re.IGNORECASE)

    if tool_match and "polyline" in tool_match.group(1).lower():
        score += 10
        feedback_parts.append("Tool correctly documented (Polyline)")
    else:
        feedback_parts.append("Polyline tool not correctly documented")

    if segments_match and int(segments_match.group(1)) >= 4:
        score += 15
        feedback_parts.append(f"Segments requirement met ({segments_match.group(1)})")
    else:
        feedback_parts.append("Insufficient segments documented (must be >= 4)")

    if length_match and float(length_match.group(1)) > 10.0:
        score += 15
        feedback_parts.append(f"Valid length documented ({length_match.group(1)})")
    else:
        feedback_parts.append("Valid length not documented")

    # 3. File existence (Screenshot) (15 points)
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size', 0)
    
    if screenshot_exists and screenshot_size > 10240: # > 10KB rules out empty frames
        score += 15
        feedback_parts.append("Valid screenshot file exists")
    else:
        feedback_parts.append("Screenshot file missing or too small")

    # 4. Anti-gaming Timestamps (5 points)
    task_start = result.get('task_start', 0)
    report_mtime = result.get('report_mtime', 0)
    screenshot_mtime = result.get('screenshot_mtime', 0)
    
    created_after_start = False
    if task_start > 0:
        if (not report_exists or report_mtime >= task_start) and \
           (not screenshot_exists or screenshot_mtime >= task_start):
            created_after_start = True
            
    if created_after_start and (report_exists or screenshot_exists):
        score += 5
        feedback_parts.append("Files created after task start (passed anti-gaming)")
    else:
        feedback_parts.append("Failed timestamp checks (potential gaming)")

    # 5. VLM Visual Verification using Trajectory (30 points)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are evaluating screenshots to verify an agent completed a polyline measurement.
Check the chronological screenshots and determine the following:
1. 'polyline_annotation_visible': Did the agent draw a multi-segment line path (polyline) over the medical image?
2. 'measurement_label_visible': Is there a numeric measurement label indicating length/distance displayed near the path?

Respond strictly in JSON format:
{
    "polyline_annotation_visible": true/false,
    "measurement_label_visible": true/false
}"""
            vlm_result = query_vlm(prompt=prompt, images=images)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('polyline_annotation_visible'):
                    score += 20
                    feedback_parts.append("VLM confirmed polyline path rendered")
                else:
                    feedback_parts.append("VLM did not detect polyline path")
                    
                if parsed.get('measurement_label_visible'):
                    score += 10
                    feedback_parts.append("VLM confirmed measurement label visible")
                else:
                    feedback_parts.append("VLM did not detect measurement label")
            else:
                feedback_parts.append("VLM query failed to parse success state")
        except ImportError:
            feedback_parts.append("VLM library missing, skipping visual check")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM verification encountered an error")
    else:
        feedback_parts.append("VLM not available for visual verification")

    # Final tally check. The core output must exist and standard passing bar is 60/100
    key_criteria_met = report_exists and screenshot_exists
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }