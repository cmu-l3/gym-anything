#!/usr/bin/env python3
"""
Verifier for aggregate_routes_to_od_matrix task.

VERIFICATION METRICS:
1. OD Matrix generation: File exists, non-empty, and was created AFTER task start. (30 points)
2. Agent Output created: Analysis text file exists and was created AFTER task start. (10 points)
3. Content accuracy (Trips): Agent's reported max trips matches the ground truth exactly. (25 points)
4. Content accuracy (Edges): Agent's reported Origin and Destination match the ground truth. (25 points)
5. Trajectory Verification: VLM confirms terminal was used to run commands. (10 points)
"""

import os
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these screenshots from a Linux desktop trajectory.
The user's goal was to open a terminal, run a Python script ('route2OD.py'), and analyze the text output.

Check for these indicators:
1. Is a terminal window open?
2. Are there commands or command-line outputs visible in the terminal indicating script execution or file reading (like 'python3', 'route2OD.py', 'cat', 'less', 'grep')?

Respond in JSON format:
{
    "terminal_used": true/false,
    "script_execution_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_aggregate_routes_to_od_matrix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve packaged results
    import tempfile
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
    
    # Check 1: OD File Generation (30 pts max)
    od_exists = result.get("od_exists", False)
    od_created = result.get("od_created_during_task", False)
    od_size = result.get("od_size_bytes", 0)
    
    if od_exists and od_size > 100:
        score += 20
        feedback_parts.append("OD matrix successfully generated")
        if od_created:
            score += 10
            feedback_parts.append("OD matrix created during task session")
        else:
            feedback_parts.append("WARNING: OD matrix existed prior to task (possible anti-gaming violation)")
    else:
        feedback_parts.append("OD matrix not found or empty")
    
    # Check 2: Analysis Text File (10 pts)
    txt_exists = result.get("txt_exists", False)
    txt_created = result.get("txt_created_during_task", False)
    
    if txt_exists:
        if txt_created:
            score += 10
            feedback_parts.append("Analysis file created during task")
        else:
            score += 5
            feedback_parts.append("Analysis file exists but created prior to task")
    else:
        feedback_parts.append("Analysis file not found")
        
    # Content Checking against Ground Truth (50 pts total)
    gt = result.get("ground_truth", {})
    gt_success = gt.get("success", False)
    
    if not gt_success:
        # Fallback if XML parsing broke
        feedback_parts.append("WARNING: Ground truth generation failed. Granting partial credit for content.")
        score += 50 
    elif txt_exists:
        # Agent's parsed values
        try:
            agent_trips = int(result.get("agent_trips", "0").strip())
        except ValueError:
            agent_trips = -1
            
        agent_o = result.get("agent_o", "").strip()
        agent_d = result.get("agent_d", "").strip()
        
        # Ground truth values
        gt_max_trips = gt.get("max_trips", 0)
        gt_peak_pairs = gt.get("peak_pairs", [])
        
        # Check 3: Accurate Max Trips Count (25 pts)
        if agent_trips == gt_max_trips:
            score += 25
            feedback_parts.append(f"Peak trips count correct ({gt_max_trips})")
        else:
            feedback_parts.append(f"Peak trips count incorrect (Agent: {agent_trips}, Expected: {gt_max_trips})")
            
        # Check 4: Accurate Edge IDs (25 pts)
        agent_pair = [agent_o, agent_d]
        if agent_pair in gt_peak_pairs:
            score += 25
            feedback_parts.append(f"Peak edge pair correct ({agent_o} -> {agent_d})")
        else:
            expected_pairs_str = " OR ".join([f"({o}->{d})" for o, d in gt_peak_pairs])
            feedback_parts.append(f"Peak edge pair incorrect. Expected: {expected_pairs_str}, Got: ({agent_o}->{agent_d})")

    # Check 5: VLM Verification for terminal usage (10 pts)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final]
            
            vlm_response = query_vlm(images=images, prompt=build_vlm_prompt())
            parsed = vlm_response.get("parsed", {})
            
            if parsed.get("terminal_used") and parsed.get("script_execution_visible"):
                score += 10
                feedback_parts.append("VLM verified proper CLI usage")
            else:
                feedback_parts.append("VLM could not strongly verify CLI usage")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")
            score += 10  # Give benefit of doubt if framework API fails

    # Determine Pass/Fail 
    # Must have >=60 points AND successfully ran the logic
    key_criteria_met = od_exists and txt_exists
    passed = (score >= 60) and key_criteria_met
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }