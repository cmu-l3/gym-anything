#!/usr/bin/env python3
"""
Verifier for fragile_payload_kinematic_optimization task.

Scoring breakdown (100 points total):
  10 pts - Simulation exists with 'uptodate' status in the saved payload_ready.ork file
  20 pts - Altitude >= 1000m
  25 pts - Acceleration <= 100 m/s² (and > 0 to prevent do-nothing exploit)
  15 pts - Launch rod velocity >= 15 m/s
  10 pts - Launch rod length used <= 3.0m
  10 pts - Plot exported successfully (acceleration_plot.png)
  10 pts - Memo written (payload_memo.txt) with meaningful size

Pass threshold: 70 points
  Requires balancing conflicting physics constraints. Agent must successfully 
  pass both altitude and acceleration targets to hit threshold.
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return (root_element, error_string)."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def verify_payload_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork = metadata.get('target_ork', '/home/ga/Documents/rockets/payload_ready.ork')
    min_alt = metadata.get('min_altitude_m', 1000)
    max_accel = metadata.get('max_acceleration_ms2', 100)
    min_rail_vel = metadata.get('min_rail_velocity_ms', 15)
    max_rod = metadata.get('max_rod_length_m', 3.0)
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []
    
    # ---- 1. Check exported JSON metadata ----
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/payload_kinematic_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read result json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("ork_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file payload_ready.ork was not saved."
        }

    # ---- 2. Retrieve and parse .ork file ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    ork_root = None
    try:
        copy_from_env(target_ork, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve/parse rocket file."
        }

    # ---- 3. Analyze Simulation Data ----
    sims = ork_root.find('simulations')
    best_sim = None
    best_metrics = {'alt': 0.0, 'accel': 0.0, 'rail_vel': 0.0, 'rod_len': 1.0}
    
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                conds = sim.find('conditions')
                if fd is not None:
                    try:
                        alt = float(fd.get('maxaltitude', '0'))
                        accel = float(fd.get('maxacceleration', '0'))
                        rail_vel = float(fd.get('launchrodvelocity', '0'))
                        
                        rod_len = 1.0 # default
                        if conds is not None:
                            try:
                                rod_len = float(conds.findtext('launchrodlength', '1.0'))
                            except (ValueError, TypeError):
                                pass

                        # Prefer the simulation that best matches our altitude goal if multiple exist
                        if best_sim is None or alt > best_metrics['alt']:
                            best_sim = sim
                            best_metrics = {'alt': alt, 'accel': accel, 'rail_vel': rail_vel, 'rod_len': rod_len}
                    except (ValueError, TypeError):
                        pass

    # Evaluate Metrics
    if best_sim is not None:
        score += 10
        feedback_parts.append("Uptodate simulation found [10/10]")
        
        # Altitude (20 pts)
        if best_metrics['alt'] >= min_alt:
            score += 20
            feedback_parts.append(f"Altitude {best_metrics['alt']:.0f}m >= {min_alt}m [20/20]")
        elif best_metrics['alt'] >= min_alt * 0.8:
            score += 10
            feedback_parts.append(f"Altitude {best_metrics['alt']:.0f}m is close to {min_alt}m [10/20]")
        else:
            feedback_parts.append(f"Altitude {best_metrics['alt']:.0f}m too low [0/20]")

        # Acceleration (25 pts)
        if 0 < best_metrics['accel'] <= max_accel:
            score += 25
            feedback_parts.append(f"Accel {best_metrics['accel']:.1f}m/s² <= {max_accel}m/s² [25/25]")
        elif best_metrics['accel'] == 0:
            feedback_parts.append("Accel is 0 m/s² (Invalid/Empty flight) [0/25]")
        else:
            feedback_parts.append(f"Accel {best_metrics['accel']:.1f}m/s² exceeds limit [0/25]")

        # Launch Rod Velocity (15 pts)
        if best_metrics['rail_vel'] >= min_rail_vel:
            score += 15
            feedback_parts.append(f"Rail Vel {best_metrics['rail_vel']:.1f}m/s >= {min_rail_vel}m/s [15/15]")
        elif best_metrics['rail_vel'] > 10.0:
            score += 5
            feedback_parts.append(f"Rail Vel {best_metrics['rail_vel']:.1f}m/s marginal [5/15]")
        else:
            feedback_parts.append(f"Rail Vel {best_metrics['rail_vel']:.1f}m/s too slow [0/15]")

        # Launch Rod Length Limits (10 pts)
        if best_metrics['rod_len'] <= max_rod:
            score += 10
            feedback_parts.append(f"Rod length {best_metrics['rod_len']:.1f}m <= {max_rod}m [10/10]")
        else:
            feedback_parts.append(f"Rod length {best_metrics['rod_len']:.1f}m exceeds {max_rod}m [0/10]")
    else:
        feedback_parts.append("No uptodate simulation found [0/80]")

    # ---- 4. Check Artifacts ----
    # Plot exported (10 pts)
    if result_data.get("plot_exists") and result_data.get("plot_created_during_task"):
        if result_data.get("plot_size", 0) > 1024:
            score += 10
            feedback_parts.append("Plot image exported successfully [10/10]")
        else:
            score += 5
            feedback_parts.append("Plot image exported but file size is suspiciously small [5/10]")
    else:
        feedback_parts.append("Plot image not exported or not created during task [0/10]")

    # Memo written (10 pts)
    if result_data.get("memo_exists") and result_data.get("memo_created_during_task"):
        if result_data.get("memo_size", 0) > 50:
            score += 10
            feedback_parts.append("Memo written successfully [10/10]")
        else:
            score += 5
            feedback_parts.append("Memo written but lacks sufficient content [5/10]")
    else:
        feedback_parts.append("Memo not written or not created during task [0/10]")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }