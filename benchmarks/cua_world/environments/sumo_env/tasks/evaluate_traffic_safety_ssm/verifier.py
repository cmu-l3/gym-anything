#!/usr/bin/env python3
"""
Verifier for evaluate_traffic_safety_ssm task.

Programmatic verification of XML configuration generation, headless execution,
and data extraction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine this sequence of screenshots from a Linux desktop.
The user's goal was to modify a SUMO traffic simulation XML configuration file, 
run the simulation from the terminal using the 'sumo' command, and parse the output file to count XML tags.

Did the user actively perform this task?
Look for:
1. Terminal usage or text editor (nano/vim/gedit) usage modifying a .sumocfg file.
2. A command execution like `sumo -c run_ssm.sumocfg` in the terminal.
3. Viewing, parsing, or grepping an output XML file (ssm.xml).

Return a JSON with a single boolean field:
{
  "task_attempted": true/false
}
"""


def verify_evaluate_traffic_safety_ssm(traj, env_info, task_info):
    """
    Verify the SUMO SSM safety task.

    CRITERIA:
    1. Configuration file created (15 pts)
    2. Simulation executed successfully (tripinfos.xml generated) (25 pts)
    3. SSM file generated with correct root structure (25 pts)
    4. Correct measures configured (TTC, DRAC) (15 pts)
    5. Agent correctly extracted the exact conflict count (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_measures = metadata.get('required_measures', ["TTC", "DRAC"])

    # Load result.json from environment
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

    feedback_parts = []
    score = 0

    # 1. Check Configuration (15 pts)
    if result.get("config_exists") and result.get("config_created_during_task"):
        score += 15
        feedback_parts.append("Config file run_ssm.sumocfg correctly created")
    elif result.get("config_exists"):
        score += 5
        feedback_parts.append("Config file exists but timestamp check failed")
    else:
        feedback_parts.append("Missing run_ssm.sumocfg")

    # 2. Check Execution (25 pts)
    if result.get("tripinfo_exists") and result.get("tripinfo_created_during_task"):
        score += 25
        feedback_parts.append("Simulation completed successfully")
    elif result.get("tripinfo_exists"):
        score += 10
        feedback_parts.append("Simulation output found, but timestamp check failed")
    else:
        feedback_parts.append("Simulation did not run successfully (no tripinfos generated)")

    # 3. Check SSM Generation (25 pts)
    if result.get("ssm_xml_exists") and result.get("ssm_log_found"):
        score += 25
        feedback_parts.append("Valid SSM XML log generated")
    else:
        feedback_parts.append("SSM XML output missing or malformed")

    # 4. Check Configured Measures (15 pts)
    measures_found = result.get("measures_found", [])
    has_ttc = "TTC" in measures_found
    has_drac = "DRAC" in measures_found
    if has_ttc and has_drac:
        score += 15
        feedback_parts.append("Correct SSM measures configured (TTC, DRAC)")
    elif has_ttc or has_drac:
        score += 7
        feedback_parts.append("Partial SSM measures configured (missing TTC or DRAC)")
    else:
        feedback_parts.append("Required SSM measures not found in output file")

    # 5. Check Extraction Count (20 pts)
    conflict_count = result.get("conflict_count", -1)
    agent_count = result.get("agent_count", -1)

    if conflict_count >= 0:
        if agent_count == conflict_count:
            score += 20
            feedback_parts.append(f"Correctly extracted conflict count: {agent_count}")
        elif agent_count >= 0:
            feedback_parts.append(f"Incorrect conflict count. Expected {conflict_count}, got {agent_count}")
        else:
            feedback_parts.append("Agent did not write a valid count to conflict_count.txt")
    else:
        feedback_parts.append("Could not verify ground truth conflict count (SSM XML may be empty or missing)")

    # VLM Trajectory Verification (anti-gaming check)
    vlm_passed = True
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            vlm_response = query_vlm(
                images=images,
                prompt=build_vlm_prompt()
            )
            vlm_data = vlm_response.get("parsed", {})
            vlm_passed = vlm_data.get("task_attempted", True)
            
            if not vlm_passed:
                feedback_parts.append("VLM flagged trajectory: Task does not appear to have been actively attempted.")
                score = min(score, 30) # Penalize heavily if VLM suspects gaming
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Pass threshold: 70 points
    passed = score >= 70 and vlm_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "config_exists": result.get("config_exists"),
            "tripinfo_exists": result.get("tripinfo_exists"),
            "ssm_log_found": result.get("ssm_log_found"),
            "measures": measures_found,
            "expected_count": conflict_count,
            "agent_count": agent_count
        }
    }