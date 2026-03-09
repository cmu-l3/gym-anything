#!/usr/bin/env python3
"""
Verifier for configure_surveillance_drone task.

A UAV systems engineer must configure a surveillance drone's camera, GPS, and altitude
for emergency services deployment.

Scoring (100 points total):
  - File saved at correct path: 10 points
  - Camera width = 1280: 20 points
  - Camera height = 720: 20 points
  - Camera fieldOfView in [0.6, 0.9] (approx 45 degrees): 20 points
  - GPS node present: 10 points
  - Drone altitude Z in [4.0, 6.0] meters: 20 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_surveillance_drone(traj, env_info, task_info):
    """
    Verify the surveillance drone world was correctly configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/surveillance_drone.wbt')
    expected_width = metadata.get('expected_camera_width', 1280)
    expected_height = metadata.get('expected_camera_height', 720)
    expected_fov = metadata.get('expected_camera_fov', 0.7854)
    expected_altitude = metadata.get('expected_altitude', 5.0)

    score = 0
    feedback_parts = []

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
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world with File > Save World As."
        }

    score += 10
    feedback_parts.append("World file saved at correct path")

    # --- Check camera width ---
    width_matches = re.findall(r'width\s+(\d+)', wbt_content)
    if width_matches:
        actual_width = int(width_matches[0])
        if actual_width == expected_width:
            score += 20
            feedback_parts.append(f"Camera width correctly set to {expected_width}")
        else:
            feedback_parts.append(
                f"Camera width is {actual_width}, expected {expected_width} (HD surveillance standard)"
            )
    else:
        feedback_parts.append("Camera width field not found")

    # --- Check camera height ---
    height_matches = re.findall(r'height\s+(\d+)', wbt_content)
    if height_matches:
        actual_height = int(height_matches[0])
        if actual_height == expected_height:
            score += 20
            feedback_parts.append(f"Camera height correctly set to {expected_height}")
        else:
            feedback_parts.append(
                f"Camera height is {actual_height}, expected {expected_height} (HD surveillance standard)"
            )
    else:
        feedback_parts.append("Camera height field not found")

    # --- Check camera fieldOfView ---
    fov_matches = re.findall(r'fieldOfView\s+([\d.]+)', wbt_content)
    if fov_matches:
        actual_fov = float(fov_matches[0])
        if 0.6 <= actual_fov <= 0.9:
            score += 20
            feedback_parts.append(
                f"Camera fieldOfView={actual_fov:.4f} rad is within acceptable range "
                f"for surveillance (45 degrees = 0.7854 rad)"
            )
        else:
            feedback_parts.append(
                f"Camera fieldOfView={actual_fov:.4f} rad, "
                f"expected ~{expected_fov:.4f} (0.7854 = 45 degrees for surveillance)"
            )
    else:
        feedback_parts.append("Camera fieldOfView field not found")

    # --- Check GPS presence ---
    # GPS nodes in .wbt are written as 'GPS {' (built-in node)
    has_gps = bool(re.search(r'\bGPS\b\s*\{', wbt_content))
    if has_gps:
        score += 10
        feedback_parts.append("GPS sensor node present on drone")
    else:
        feedback_parts.append(
            "GPS node not found. Add a GPS node to the drone's children list."
        )

    # --- Check drone altitude (Z translation) ---
    # Find SURVEILLANCE_DRONE translation and check Z component
    # Pattern: 'translation X Y Z' — we want Z > 4.0
    drone_idx = wbt_content.find('SURVEILLANCE_DRONE')
    if drone_idx == -1:
        drone_idx = 0

    # Search for translation in drone section
    drone_segment = wbt_content[drone_idx:drone_idx + 600]
    trans_match = re.search(
        r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)',
        drone_segment
    )

    if trans_match:
        drone_z = float(trans_match.group(3))
        if 4.0 <= drone_z <= 6.0:
            score += 20
            feedback_parts.append(
                f"Drone altitude Z={drone_z:.1f}m is within acceptable operating range [4.0, 6.0]m"
            )
        else:
            feedback_parts.append(
                f"Drone altitude Z={drone_z:.1f}m, expected ~{expected_altitude}m above ground"
            )
    else:
        # Fall back: search for any translation with Z >= 4.0 in the file
        all_trans = re.findall(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', wbt_content)
        high_alt = [(x, y, z) for x, y, z in [(float(t[0]), float(t[1]), float(t[2])) for t in all_trans]
                    if 4.0 <= z <= 6.0]
        if high_alt:
            score += 20
            feedback_parts.append(
                f"Drone appears to be at altitude Z={high_alt[0][2]:.1f}m (acceptable range)"
            )
        else:
            feedback_parts.append(
                f"Drone altitude (Z translation) not in expected range [4.0, 6.0]m. "
                "Set SURVEILLANCE_DRONE translation Z to 5.0m."
            )

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "debug": {
            "wbt_size": len(wbt_content),
            "has_gps": has_gps,
        }
    }
