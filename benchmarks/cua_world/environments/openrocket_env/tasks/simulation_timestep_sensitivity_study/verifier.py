#!/usr/bin/env python3
"""
Verifier for simulation_timestep_sensitivity_study task.

Scoring breakdown (100 points total):
  15 pts - At least 3 simulations exist in the .ork file and are `uptodate`.
  25 pts - Time steps of exactly 0.1, 0.05, and 0.01 are found in the simulation XML.
  25 pts - At least 3 CSV files found in the exports directory.
  20 pts - CSV Anti-gaming check: CSV files have drastically different row counts 
           (proving different time steps were actually run, not just duplicated).
  15 pts - Text report exists with required keywords and numerical analysis.

Pass threshold: 70 points
"""

import os
import re
import math
import json
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


def verify_simulation_timestep_sensitivity_study(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/sensitivity_study.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/sensitivity_report.txt')
    expected_timesteps = metadata.get('expected_timesteps', [0.1, 0.05, 0.01])
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []
    
    # ---- 1. Check Result JSON from Container ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    result_data = {}
    try:
        copy_from_env('/tmp/sensitivity_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Could not read task result metadata: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # ---- 2. Verify ORK File (Simulations and Timesteps) ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
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
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"
        }

    # Extract simulation details
    sims_elem = ork_root.find('simulations')
    uptodate_count = 0
    found_timesteps = []
    
    if sims_elem is not None:
        for sim in sims_elem.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
            
            # Find timestep in options (or anywhere in the sim)
            for ts_el in sim.iter('timestep'):
                try:
                    found_timesteps.append(float(ts_el.text))
                except (ValueError, TypeError):
                    pass

    # Criterion 1: At least 3 uptodate sims (15 pts)
    if uptodate_count >= 3:
        score += 15
        feedback_parts.append(f"Found {uptodate_count} uptodate simulations [15/15 pts]")
    elif uptodate_count > 0:
        pts = uptodate_count * 5
        score += pts
        feedback_parts.append(f"Found {uptodate_count} uptodate simulations (need 3) [{pts}/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/15 pts]")

    # Criterion 2: Correct time steps assigned (25 pts)
    matched_ts = set()
    for exp_ts in expected_timesteps:
        for f_ts in found_timesteps:
            if math.isclose(exp_ts, f_ts, rel_tol=1e-3):
                matched_ts.add(exp_ts)
                break
    
    if len(matched_ts) == len(expected_timesteps):
        score += 25
        feedback_parts.append("All requested time steps configured (0.1, 0.05, 0.01) [25/25 pts]")
    elif len(matched_ts) > 0:
        pts = len(matched_ts) * 8
        score += pts
        feedback_parts.append(f"Found {len(matched_ts)}/{len(expected_timesteps)} requested time steps [{pts}/25 pts]")
    else:
        feedback_parts.append("Requested time steps not found in simulation configurations [0/25 pts]")

    # ---- 3. Verify CSV Exports (25 pts) ----
    csv_count = result_data.get('csv_count', 0)
    if csv_count >= 3:
        score += 25
        feedback_parts.append(f"Found {csv_count} exported CSV files [25/25 pts]")
    elif csv_count > 0:
        pts = csv_count * 8
        score += pts
        feedback_parts.append(f"Found {csv_count} exported CSV files (need 3) [{pts}/25 pts]")
    else:
        feedback_parts.append("No exported CSV files found [0/25 pts]")

    # ---- 4. CSV Anti-Gaming Check via row counts (20 pts) ----
    csv_stats = result_data.get('csv_stats', [])
    if len(csv_stats) >= 3:
        lines = [stat['lines'] for stat in csv_stats if stat['lines'] > 5]
        if len(lines) >= 3:
            max_lines = max(lines)
            min_lines = min(lines)
            
            # A 0.01s sim will yield roughly 10x the rows of a 0.1s sim.
            # We check if max is at least 5x min to confidently prove different timesteps were run.
            if max_lines >= min_lines * 5:
                score += 20
                feedback_parts.append("CSV row counts vary significantly, validating time step differences [20/20 pts]")
            else:
                feedback_parts.append("CSV row counts are too similar, indicating duplicated data or missing time step changes [0/20 pts]")
        else:
            feedback_parts.append("CSV files do not contain enough data [0/20 pts]")
    else:
        feedback_parts.append("Not enough CSVs for anti-gaming verification [0/20 pts]")

    # ---- 5. Sensitivity Report Analysis (15 pts) ----
    report_exists = result_data.get('report_exists', False)
    report_size = result_data.get('report_size', 0)
    
    if report_exists and report_size > 20:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                
            has_accel = "acceleration" in content or "m/s" in content or "g-force" in content or "g" in content
            has_ts = ("0.1" in content or ".1" in content) and ("0.01" in content or ".01" in content)
            
            if has_accel and has_ts:
                score += 15
                feedback_parts.append("Report found with correct keywords and numerical comparisons [15/15 pts]")
            elif has_accel or has_ts:
                score += 7
                feedback_parts.append("Report found but missing some context (acceleration or time steps) [7/15 pts]")
            else:
                feedback_parts.append("Report found but lacks required context [0/15 pts]")
                
        except Exception as e:
            feedback_parts.append(f"Could not read report file: {e}")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Sensitivity report not found or empty [0/15 pts]")

    # Evaluate pass/fail criteria
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }