#!/usr/bin/env python3
"""
Verifier for deploy_swarm_experiment task.

A swarm robotics researcher must discover and fix 3 configuration errors in a multi-robot
Webots world: wrong controllers (soccer_player_broken), all robots at overlapping positions,
and too-slow basicTimeStep. No errors are identified in the task description.

Scoring (100 points total):
  - File saved at correct path: 10 points
  - At least 3 robots with valid controllers (not 'soccer_player_broken', not '<none>'): 30 points
  - At least 2 robot pairs with distinct non-overlapping positions (dist > 0.15m): 30 points
  - basicTimeStep <= 64 (was 128): 30 points

Pass threshold: 70 points
"""

import json
import re
import math
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

BROKEN_CONTROLLER = 'soccer_player_broken'
INVALID_CONTROLLERS = {BROKEN_CONTROLLER, '<none>', 'void', '', '<extern>'}


def verify_deploy_swarm_experiment(traj, env_info, task_info):
    """
    Verify that all swarm configuration errors have been discovered and fixed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/swarm_ready.wbt')
    thresholds = metadata.get('verification_thresholds', {
        'min_robots_with_valid_controller': 3,
        'min_distinct_positions': 2,
        'timestep_max': 64
    })

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy the .wbt file independently ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    # --- Check file existence ---
    if not wbt_content or len(wbt_content) < 200:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Output file not found at {output_path}. "
                "The corrected world must be saved using File > Save World As."
            )
        }

    score += 10
    feedback_parts.append("Fixed swarm world saved at correct path")
    subscores["file_exists"] = True

    # --- Check Error 1: Robot controllers ---
    # Find all controller assignments in the world
    all_controllers = re.findall(r'controller\s+"([^"]*)"', wbt_content)

    # Count controllers that are NOT in the broken/invalid set
    valid_controllers = [c for c in all_controllers if c not in INVALID_CONTROLLERS]
    min_valid = thresholds.get('min_robots_with_valid_controller', 3)

    if len(valid_controllers) >= min_valid:
        score += 30
        # Check if they correctly identified soccer_player
        if 'soccer_player' in valid_controllers:
            feedback_parts.append(
                f"Controllers fixed: {len(valid_controllers)} robots now have valid controllers "
                f"including 'soccer_player' (correct controller for this world)"
            )
        else:
            feedback_parts.append(
                f"Controllers updated: {len(valid_controllers)} robots have non-broken controllers. "
                f"Controllers found: {list(set(valid_controllers))[:4]}"
            )
        subscores["controllers_fixed"] = True
    else:
        still_broken = [c for c in all_controllers if c == BROKEN_CONTROLLER]
        feedback_parts.append(
            f"Only {len(valid_controllers)} robot(s) have valid controllers "
            f"(need >= {min_valid}). "
            f"{len(still_broken)} robot(s) still have controller='{BROKEN_CONTROLLER}'. "
            "Check controllers/ directory for available controllers and update each robot."
        )
        subscores["controllers_fixed"] = False

    # --- Check Error 2: Robot positions (non-overlapping) ---
    # Find positions of soccer player robots specifically
    player_positions = []
    lines = wbt_content.split('\n')
    for i, line in enumerate(lines):
        if re.search(r'(DEF BLUE_PLAYER|DEF YELLOW_PLAYER|SoccerPlayer)', line):
            # Look ahead for translation within next 10 lines
            for j in range(i + 1, min(i + 10, len(lines))):
                m = re.match(
                    r'\s+translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', lines[j]
                )
                if m:
                    player_positions.append(
                        (float(m.group(1)), float(m.group(2)), float(m.group(3)))
                    )
                    break

    # Count distinct position pairs (distance > 0.15m)
    distinct_pairs = 0
    for i in range(len(player_positions)):
        for j in range(i + 1, len(player_positions)):
            dx = player_positions[i][0] - player_positions[j][0]
            dy = player_positions[i][1] - player_positions[j][1]
            dz = player_positions[i][2] - player_positions[j][2]
            dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist > 0.15:
                distinct_pairs += 1

    min_distinct = thresholds.get('min_distinct_positions', 2)

    if distinct_pairs >= min_distinct:
        score += 30
        feedback_parts.append(
            f"Robot positions fixed: {distinct_pairs} non-overlapping robot pairs found "
            "(robots are no longer all stacked at the same position)"
        )
        subscores["positions_fixed"] = True
    else:
        feedback_parts.append(
            f"Only {distinct_pairs} non-overlapping robot position pairs "
            f"(need >= {min_distinct}). "
            "Move robots to distinct, non-overlapping positions. "
            f"Found {len(player_positions)} player robots with positions: "
            f"{[(round(p[0],2), round(p[1],2), round(p[2],2)) for p in player_positions[:4]]}"
        )
        subscores["positions_fixed"] = False

    # --- Check Error 3: basicTimeStep ---
    timestep_match = re.search(r'basicTimeStep\s+(\d+)', wbt_content)
    if timestep_match:
        actual_timestep = int(timestep_match.group(1))
        max_timestep = thresholds.get('timestep_max', 64)
        if actual_timestep <= max_timestep:
            score += 30
            feedback_parts.append(
                f"basicTimeStep fixed: {actual_timestep}ms "
                f"(was 128ms, now <= {max_timestep}ms for real-time soccer control)"
            )
            subscores["timestep_fixed"] = True
        else:
            feedback_parts.append(
                f"basicTimeStep={actual_timestep}ms is still too slow "
                f"(was 128ms, should be <= {max_timestep}ms for soccer robot control). "
                "Find WorldInfo in the scene tree and reduce basicTimeStep."
            )
            subscores["timestep_fixed"] = False
    else:
        feedback_parts.append("basicTimeStep not found in saved world")
        subscores["timestep_fixed"] = False

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "wbt_size": len(wbt_content),
            "all_controllers_found": all_controllers[:8],
            "player_positions_found": len(player_positions),
            "errors_fixed_count": sum([
                subscores.get("controllers_fixed", False),
                subscores.get("positions_fixed", False),
                subscores.get("timestep_fixed", False)
            ])
        }
    }
