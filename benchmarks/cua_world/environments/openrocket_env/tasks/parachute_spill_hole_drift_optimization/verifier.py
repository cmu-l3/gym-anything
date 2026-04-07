#!/usr/bin/env python3
"""
Verifier for parachute_spill_hole_drift_optimization task.

Scoring breakdown (100 points total):
  20 pts - Parachute Outer Diameter Maintained (must be exactly 0.9144m / 36 inches)
  20 pts - Spill Hole Applied (spillholediameter must be > 0.0)
  30 pts - Target Descent Rate Achieved (Ground hit velocity between 5.0 and 5.5 m/s)
  15 pts - Anti-Gaming Compliance (Simulation wind speed remains exactly 6.0 m/s)
  15 pts - Drift Report Generated (Contains required flight metrics)

Pass threshold: 60 points + Target Descent Rate must be hit + Spill hole must be present.
"""

import os
import re
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


def verify_parachute_spill_hole_drift_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/spill_hole_optimized.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/drift_report.txt')
    target_min = metadata.get('target_velocity_min', 5.0)
    target_max = metadata.get('target_velocity_max', 5.5)

    score = 0
    feedback_parts = []
    
    # ---- Read JSON Results ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/spill_hole_result.json", tmp_json.name)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # ---- Copy .ork file from VM ----
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
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve the saved rocket file."
        }

    # ---- Evaluate Parachute Sizing (40 points) ----
    main_diam = 0.0
    spill_diam = 0.0
    for para in ork_root.iter('parachute'):
        try:
            main_diam = float(para.findtext('diameter', '0'))
            spill_diam = float(para.findtext('spillholediameter', '0'))
        except (ValueError, TypeError):
            pass

    # Criterion 1: Outer Diameter (20 pts)
    if abs(main_diam - 0.9144) < 0.001:
        score += 20
        feedback_parts.append("Parachute outer diameter maintained at 0.9144m [20/20 pts]")
    else:
        feedback_parts.append(f"Parachute outer diameter changed to {main_diam:.4f}m (should be 0.9144m) [0/20 pts]")

    # Criterion 2: Spill Hole (20 pts)
    if spill_diam > 0.0:
        score += 20
        feedback_parts.append(f"Spill hole applied: {spill_diam:.4f}m [20/20 pts]")
    else:
        feedback_parts.append("No spill hole applied [0/20 pts]")

    # ---- Evaluate Simulation Results & Integrity (45 points) ----
    sims = ork_root.find('simulations')
    uptodate_ghv = []
    wind_speeds = []
    if sims is not None:
        for sim in sims.findall('simulation'):
            # Grab conditions for anti-gaming check
            conds = sim.find('conditions')
            if conds is not None:
                try:
                    ws = float(conds.findtext('windspeed', '0'))
                    wind_speeds.append(ws)
                except (ValueError, TypeError):
                    pass

            # Only verify flight stats on uptodate simulations
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        ghv = float(fd.get('groundhitvelocity', '999'))
                        uptodate_ghv.append(ghv)
                    except (ValueError, TypeError):
                        pass

    # Criterion 3: Target Descent Rate Achieved (30 pts)
    ghv_in_range = False
    if uptodate_ghv:
        # Check if any up to date sim meets criteria
        ghv_in_range = any(target_min <= ghv <= target_max for ghv in uptodate_ghv)
        if ghv_in_range:
            score += 30
            feedback_parts.append(f"Ground hit velocity is within target range ({target_min}-{target_max} m/s) [30/30 pts]")
        else:
            feedback_parts.append(f"Ground hit velocity {uptodate_ghv[0]:.2f} m/s is outside {target_min}-{target_max} m/s range [0/30 pts]")
    else:
        feedback_parts.append("No uptodate simulations found with valid flight data [0/30 pts]")

    # Criterion 4: Anti-Gaming Compliance (15 pts)
    if wind_speeds and all(abs(ws - 6.0) < 0.01 for ws in wind_speeds):
        score += 15
        feedback_parts.append("Wind speed maintained at 6.0 m/s [15/15 pts]")
    elif wind_speeds:
        feedback_parts.append(f"Wind speed altered to {wind_speeds[0]} m/s (must remain 6.0) [0/15 pts]")
    else:
        feedback_parts.append("Could not verify wind speed settings [0/15 pts]")

    # ---- Evaluate Report (15 points) ----
    report_pts = 0
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 5:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()

            # Lenient match for metrics indicating they pulled data from simulation
            has_vel = re.search(r'5\.\d+|velocity|m/s', content) is not None
            has_drift = re.search(r'drift|distance|lateral|\d+\s*m', content) is not None

            if has_vel and has_drift:
                report_pts = 15
                feedback_parts.append("Report contains final velocity and drift metrics [15/15 pts]")
            elif has_vel or has_drift:
                report_pts = 7
                feedback_parts.append("Report missing some metrics (either velocity or drift) [7/15 pts]")
            else:
                feedback_parts.append("Report lacks quantitative flight metrics [0/15 pts]")
        else:
            feedback_parts.append("Report file is empty [0/15 pts]")
    except Exception:
        feedback_parts.append("Report file not found [0/15 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)
            
    score += report_pts

    # To pass, they must hit the required threshold, use the right mechanism (spill hole), and hit the velocity target.
    passed = score >= 60 and spill_diam > 0.0 and ghv_in_range

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }