#!/usr/bin/env python3
"""
Verifier for streamer_recovery_conversion task.

Scoring breakdown (100 points total):
  15 pts - Parachute removed
  15 pts - Streamer added
  20 pts - Streamer width constrained to 5.0 cm
  15 pts - At least one simulation updated/run with the new configuration
  25 pts - Optimized ground hit velocity (7.0 - 8.0 m/s)
  10 pts - Recovery conversion report generated

Pass threshold: 70 points AND Streamer must be added AND velocity optimized.
Anti-gaming: Adding dummy mass components instead of optimizing streamer length results in 0 score.
"""

import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET


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


def verify_streamer_recovery_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/streamer_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/streamer_report.txt')
    target_width = metadata.get('target_width_m', 0.05)
    min_vel = metadata.get('min_velocity_ms', 7.0)
    max_vel = metadata.get('max_velocity_ms', 8.0)
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []
    
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        if os.path.exists(tmp_ork.name) and os.path.getsize(tmp_ork.name) > 0:
            ork_root, parse_err = _parse_ork(tmp_ork.name)
            if parse_err:
                feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        pass
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve modified rocket file. Make sure you saved to ~/Documents/rockets/streamer_rocket.ork"
        }

    # 1. Parachute Removed (15 pts)
    parachutes = list(ork_root.iter('parachute'))
    if len(parachutes) == 0:
        score += 15
        feedback_parts.append("Parachute removed [15/15 pts]")
    else:
        feedback_parts.append("Parachute still present [0/15 pts]")

    # 2. Streamer Added (15 pts)
    streamers = list(ork_root.iter('streamer'))
    if len(streamers) > 0:
        score += 15
        feedback_parts.append("Streamer added [15/15 pts]")
    else:
        feedback_parts.append("No streamer found [0/15 pts]")

    # 3. Width Constrained (20 pts)
    if len(streamers) > 0:
        try:
            w_text = streamers[0].findtext('stripwidth')
            if w_text is None:
                w_text = streamers[0].findtext('width', '0')
            w = float(w_text)
            if abs(w - target_width) < 0.001:
                score += 20
                feedback_parts.append("Streamer width constrained to 5.0 cm [20/20 pts]")
            else:
                feedback_parts.append(f"Streamer width is {w*100:.1f} cm, expected 5.0 cm [0/20 pts]")
        except (ValueError, TypeError):
            feedback_parts.append("Could not read streamer width [0/20 pts]")
    else:
        feedback_parts.append("Cannot check width (no streamer) [0/20 pts]")

    # 4. Simulation Updated and Velocity Optimized (15 + 25 pts)
    sims = ork_root.find('simulations')
    uptodate_count = 0
    ghv_values = []
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        ghv_values.append(float(fd.get('groundhitvelocity', '999')))
                    except (ValueError, TypeError):
                        pass

    if uptodate_count > 0:
        score += 15
        feedback_parts.append(f"Found {uptodate_count} uptodate simulation(s) [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/15 pts]")

    velocity_ok = False
    if ghv_values:
        min_ghv = min(ghv_values)
        if min_vel <= min_ghv <= max_vel:
            velocity_ok = True
            score += 25
            feedback_parts.append(f"Ground hit velocity {min_ghv:.1f} m/s in target range [25/25 pts]")
        else:
            feedback_parts.append(f"Ground hit velocity {min_ghv:.1f} m/s outside target range ({min_vel}-{max_vel}) [0/25 pts]")
    else:
        feedback_parts.append("Could not extract ground hit velocity [0/25 pts]")

    # Anti-gaming: Ensure no mass components were added to artificially lower descent rate
    mass_components = list(ork_root.iter('masscomponent'))
    if len(mass_components) > 0:
        score = 0
        feedback_parts.append("ANTI-GAMING FAIL: Mass components added instead of optimizing streamer length.")
        velocity_ok = False

    # 5. Report Generated (10 pts)
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 0:
            with open(tmp_report.name, 'r', errors='ignore') as f:
                content = f.read().lower()
                if "streamer" in content and ("velocity" in content or "m/s" in content or "7." in content or "8." in content):
                    score += 10
                    feedback_parts.append("Report generated with expected keywords [10/10 pts]")
                else:
                    score += 5
                    feedback_parts.append("Report generated but missing key information [5/10 pts]")
        else:
            feedback_parts.append("Report not found or empty [0/10 pts]")
    except Exception as e:
        feedback_parts.append(f"Failed to check report: {e} [0/10 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    # Calculate final pass
    key_criteria_met = (len(streamers) > 0) and velocity_ok
    passed = score >= pass_threshold and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }