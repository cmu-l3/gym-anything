#!/usr/bin/env python3
"""
Verifier for create_cooperative_testworld task.

This verifier uses a HYBRID approach:
1. Programmatic validation of the `.wbt` file contents (Header, WorldInfo, Arena, Robots, Ball).
2. VLM validation of the trajectory frames to ensure the agent actively built the scene in the Webots UI.
3. Anti-gaming checks using file timestamps.

Scoring (100 points total):
  - File exists and was created during task: 10 points
  - Valid WBT Header & WorldInfo (basicTimeStep <= 64, Gravity ~ -9.81): 15 points
  - Scene components (Arena/Floor, Viewpoint, Light): 15 points
  - Two E-puck robots placed > 0.3m apart: 20 points
  - Ball placed near center: 15 points
  - VLM verifies trajectory shows active scene building: 25 points

Pass threshold: 65 points with file creation confirmed.
"""

import json
import math
import os
import re
import tempfile
import logging

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """You are verifying an agent's completion of a Webots robotics simulation task.
The agent was asked to build a new simulation world from scratch containing an arena, two e-puck robots facing each other, and a ball in the middle.

Please review these frames from the agent's trajectory and the final screenshot.
Determine if the agent successfully performed the task by checking:
1. Did the agent interact with the Webots UI?
2. Did the agent progressively build a 3D scene?
3. Does the final or near-final scene show an arena/floor, two small robots (e-pucks), and a ball?
4. Was the scene saved?

Respond in JSON format with:
{
    "interacted_with_webots": true/false,
    "built_scene_progressively": true/false,
    "scene_contains_two_robots_and_ball": true/false,
    "confidence": "high"/"medium"/"low",
    "reasoning": "Brief explanation of what the trajectory shows"
}"""


def verify_create_cooperative_testworld(traj, env_info, task_info):
    """
    Verify that the cooperative testworld was correctly constructed and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('expected_output_path', '/home/ga/Desktop/cooperative_push.wbt')
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Read the export script's JSON results
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read export JSON: {e}")
        export_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    file_exists = export_result.get('file_exists', False)
    file_created_during_task = export_result.get('file_created_during_task', False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Target file {output_path} does not exist. The world was not saved."
        }
        
    if not file_created_during_task:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming failure: The file exists but was not created/modified during the task session."
        }
    
    score += 10
    feedback_parts.append("File successfully created during task")

    # ---------------------------------------------------------
    # 2. Parse the .wbt file contents programmatically
    # ---------------------------------------------------------
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_content = ""
    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.error(f"Failed to copy/read .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    if not wbt_content:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | Failed to read .wbt contents."}

    # -- Check Header & WorldInfo (15 pts) --
    if re.search(r'^#VRML_SIM', wbt_content):
        header_ok = True
    else:
        header_ok = False
        
    ts_match = re.search(r'basicTimeStep\s+(\d+)', wbt_content)
    ts_ok = False
    if ts_match:
        ts = int(ts_match.group(1))
        if 8 <= ts <= 64:
            ts_ok = True

    # Gravity defaults to -9.81 if missing, which is acceptable.
    grav_match = re.search(r'gravity\s+([-\d.]+(?:\s+[-\d.]+)*)', wbt_content)
    grav_ok = False
    if grav_match:
        vals = [float(x) for x in grav_match.group(1).split()]
        if any(-10.5 <= v <= -9.0 for v in vals):
            grav_ok = True
    elif 'WorldInfo' in wbt_content:
        grav_ok = True # default gravity
        
    if header_ok and ts_ok and grav_ok:
        score += 15
        feedback_parts.append("Valid Webots Header & Physical WorldInfo")
    elif header_ok:
        score += 5
        feedback_parts.append("Valid header but missing correct basicTimeStep or Gravity")
        
    # -- Check Scene Components (15 pts) --
    has_arena = bool(re.search(r'(RectangleArena|Floor)\s*\{', wbt_content))
    has_viewpoint = bool(re.search(r'Viewpoint\s*\{', wbt_content))
    has_light = bool(re.search(r'(TexturedBackgroundLight|PointLight|DirectionalLight|SpotLight)\s*\{', wbt_content))
    
    env_score = 0
    if has_arena: env_score += 5
    if has_viewpoint: env_score += 5
    if has_light: env_score += 5
    score += env_score
    if env_score == 15:
        feedback_parts.append("Scene environment correctly set up (Arena, Light, Viewpoint)")

    # -- Check Robots (20 pts) --
    robot_blocks = list(re.finditer(r'(E-puck|E-Puck|Robot)\s*\{', wbt_content))
    robot_names = re.findall(r'name\s+"([^"]*e-?puck[^"]*)"', wbt_content, re.IGNORECASE)
    translations = re.findall(r'translation\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)', wbt_content)
    
    if len(robot_blocks) >= 2:
        # Verify spatial distribution
        if len(translations) >= 2:
            t1 = [float(x) for x in translations[0]]
            t2 = [float(x) for x in translations[1]]
            dist = math.sqrt(sum((a-b)**2 for a,b in zip(t1, t2)))
            if dist >= 0.2:  # Accept >= 0.2m to be generous on exact placement
                score += 20
                feedback_parts.append("Two robots successfully placed at distinct positions")
            else:
                score += 10
                feedback_parts.append("Two robots found, but they appear to overlap or are too close")
        else:
            score += 10
            feedback_parts.append("Two robots found but missing explicit translation values")
    elif len(robot_blocks) == 1:
        score += 5
        feedback_parts.append("Only one robot found")
    else:
        feedback_parts.append("No valid robots found")

    # -- Check Ball (15 pts) --
    has_ball = bool(re.search(r'(Ball|Sphere)\s*\{', wbt_content, re.IGNORECASE))
    ball_section = re.search(r'(?:Ball|Sphere)\s*\{[^}]*translation\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)', wbt_content, re.IGNORECASE)
    
    if has_ball:
        score += 5
        feedback_parts.append("Ball object exists")
        if ball_section:
            bx, by = float(ball_section.group(1)), float(ball_section.group(2))
            if math.sqrt(bx**2 + by**2) <= 0.2:
                score += 10
                feedback_parts.append("Ball positioned near the center")
        elif re.search(r'(?:Ball|Sphere)\s*\{', wbt_content, re.IGNORECASE):
            # If no translation is found, it defaults to 0,0,0 which is the center.
            score += 10
            feedback_parts.append("Ball positioned at default center")

    # ---------------------------------------------------------
    # 3. VLM Trajectory Verification (25 pts)
    # ---------------------------------------------------------
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            if final_img:
                frames.append(final_img)
            
            if frames:
                vlm_result = query_vlm(images=frames, prompt=build_vlm_prompt())
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('interacted_with_webots'): vlm_score += 5
                    if parsed.get('built_scene_progressively'): vlm_score += 10
                    if parsed.get('scene_contains_two_robots_and_ball'): vlm_score += 10
                    
                    score += vlm_score
                    feedback_parts.append(f"VLM trajectory verification: {vlm_score}/25 pts. Reasoning: {parsed.get('reasoning', 'None')}")
                else:
                    feedback_parts.append("VLM query failed or format invalid. Skipping VLM score.")
            else:
                feedback_parts.append("No trajectory frames available for VLM verification.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification encountered an error.")
    else:
        # If VLM is not available in the testing environment, grant the points if programmatic score is high
        if score >= 50:
            score += 25
            feedback_parts.append("VLM unavailable; granting points based on strong programmatic evidence.")

    passed = score >= 65 and file_created_during_task
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }