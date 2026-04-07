#!/usr/bin/env python3
"""
Verifier for walker_constellation_setup@1

The agent must define 6 satellites adhering to a Walker-Delta 6/3/1 configuration.

Verification Strategy:
1. Programmatically parse the generated GMAT script using copy_from_env.
2. Group the 6 spacecraft by RAAN into orbital planes.
3. Validate 120 deg separation between 3 distinct RAAN planes.
4. Validate 180 deg in-plane TA spacing, and 60 deg inter-plane TA phasing (f=1).
5. Ensure geometry report was written with the expected format and values.
6. Verify via VLM that GMAT/Editor was utilized across the trajectory.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def angle_diff(a, b):
    """Calculates the shortest angular distance between two degrees."""
    diff = abs(a - b) % 360
    return min(diff, 360 - diff)

def verify_walker_constellation_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    sma_target = metadata.get('sma_target_km', 7071.14)
    ecc_max = metadata.get('ecc_max', 0.01)
    inc_target = metadata.get('inc_target_deg', 98.19)

    scores = {
        "script_exists": 5,
        "six_spacecraft": 15,
        "sma_consistent": 10,
        "ecc_consistent": 5,
        "inc_consistent": 5,
        "raan_pattern": 15,
        "ta_pattern": 15,
        "propagator_configured": 5,
        "propagation_present": 5,
        "report_exists": 5,
        "report_six_sats": 5,
        "report_period": 5,
        "report_walker_ref": 5,
        "vlm_verification": 5
    }

    total_score = 0
    feedback = []
    six_spacecraft_ok = False
    raan_ok = False

    # 1. Read Task Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Score file creation (anti-gaming timestamp verification)
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_exists"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 3. Process GMAT Script
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/walker_constellation.script')
    sc_names = []
    sc_params = {}
    prop_configured = False
    propagate_present = False

    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            for line in script_content.split('\n'):
                line_stripped = line.strip()
                if line_stripped.startswith('Create Spacecraft'):
                    names = line_stripped.replace('Create Spacecraft', '').strip('; \r\n').split(',')
                    for n in names:
                        name = n.strip()
                        if name:
                            sc_names.append(name)
                            sc_params[name] = {}
                elif line_stripped.startswith('Create ForceModel') or line_stripped.startswith('Create Propagator'):
                    prop_configured = True
                elif line_stripped.startswith('Propagate '):
                    propagate_present = True

            for line in script_content.split('\n'):
                line_stripped = line.strip()
                for name in sc_names:
                    if line_stripped.startswith(f"GMAT {name}."):
                        parts = line_stripped.split('=')
                        if len(parts) == 2:
                            param_part = parts[0].replace(f"GMAT {name}.", "").strip()
                            val_part = parts[1].strip('; \r\n')
                            try:
                                sc_params[name][param_part.upper()] = float(val_part)
                            except:
                                pass

            if len(sc_names) == 6:
                total_score += scores["six_spacecraft"]
                six_spacecraft_ok = True
                feedback.append("Exactly 6 spacecraft defined.")
            elif len(sc_names) > 0:
                total_score += int(scores["six_spacecraft"] * (min(len(sc_names), 6) / 6.0))
                feedback.append(f"{len(sc_names)} spacecraft defined (expected 6).")

            if prop_configured:
                total_score += scores["propagator_configured"]
            if propagate_present:
                total_score += scores["propagation_present"]

            if len(sc_names) > 0:
                sma_ok = all(abs(sc_params[n].get('SMA', 0) - sma_target) <= 10 for n in sc_names)
                ecc_ok = all(sc_params[n].get('ECC', 1.0) <= ecc_max for n in sc_names)
                inc_ok = all(abs(sc_params[n].get('INC', 0) - inc_target) <= 1.0 for n in sc_names)

                if sma_ok: total_score += scores["sma_consistent"]
                if ecc_ok: total_score += scores["ecc_consistent"]
                if inc_ok: total_score += scores["inc_consistent"]

                # Grouping by RAAN to check Walker Delta Geometry
                planes = []
                for name, params in sc_params.items():
                    r = params.get('RAAN', 0.0) % 360
                    t = params.get('TA', 0.0) % 360
                    placed = False
                    for p in planes:
                        if angle_diff(p['raan'], r) < 5:
                            p['tas'].append(t)
                            placed = True
                            break
                    if not placed:
                        planes.append({'raan': r, 'tas': [t]})

                if len(planes) == 3:
                    planes.sort(key=lambda x: x['raan'])
                    d1 = angle_diff(planes[0]['raan'] + 120, planes[1]['raan'])
                    d2 = angle_diff(planes[1]['raan'] + 120, planes[2]['raan'])
                    d3 = angle_diff(planes[2]['raan'] + 120, planes[0]['raan'])
                    
                    if d1 < 5 and d2 < 5 and d3 < 5:
                        total_score += scores["raan_pattern"]
                        raan_ok = True
                        feedback.append("RAAN spacing successfully matches 3 evenly spaced planes.")
                    else:
                        feedback.append("RAAN spacing is not 120 degrees apart.")
                    
                    in_plane_ok = True
                    for p in planes:
                        if len(p['tas']) == 2:
                            if angle_diff(p['tas'][0] + 180, p['tas'][1]) > 5:
                                in_plane_ok = False
                        else:
                            in_plane_ok = False
                            
                    if in_plane_ok:
                        t0 = planes[0]['tas'][0]
                        t1_actual = planes[1]['tas'][0]
                        t2_actual = planes[2]['tas'][0]
                        
                        t1_expected_a = (t0 + 60) % 360
                        t1_expected_b = (t0 + 240) % 360
                        d_phase1 = min(angle_diff(t1_actual, t1_expected_a), angle_diff(t1_actual, t1_expected_b))
                        
                        t2_expected_a = (t0 + 120) % 360
                        t2_expected_b = (t0 + 300) % 360
                        d_phase2 = min(angle_diff(t2_actual, t2_expected_a), angle_diff(t2_actual, t2_expected_b))
                        
                        if d_phase1 < 5 and d_phase2 < 5:
                            total_score += scores["ta_pattern"]
                            feedback.append("TA phasing matches Walker f=1 pattern.")
                        else:
                            feedback.append("TA phasing does not match f=1 pattern.")
                    else:
                        feedback.append("Satellites within a plane are not 180 deg apart.")
                else:
                    feedback.append(f"Found {len(planes)} RAAN planes, expected 3.")

        except Exception as e:
            feedback.append(f"Error parsing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. Report File Verification
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/constellation_report.txt')
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_exists"]
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()

            import re
            sats_found = re.findall(r'TS_[123][AB]', report_content)
            if len(set(sats_found)) == 6:
                total_score += scores["report_six_sats"]
            elif "TS_1A" in report_content and "TS_3B" in report_content:
                total_score += scores["report_six_sats"]

            if "6/3/1" in report_content:
                total_score += scores["report_walker_ref"]

            # Period usually around 98.8
            if re.search(r'9[5-9](\.[0-9]+)?|10[0-2](\.[0-9]+)?', report_content):
                total_score += scores["report_period"]

        except Exception as e:
            feedback.append(f"Error parsing report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # 5. VLM Trajectory Verification
    try:
        import sys
        from pathlib import Path
        
        # Dynamically import VLM utilities
        try:
            sys.path.insert(0, str(Path(__file__).parent.parent))
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
            
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if final:
                images = frames + [final]
                prompt = (
                    "Did the agent use a text editor or GMAT to configure multiple spacecraft "
                    "for a constellation? Answer YES or NO."
                )
                vlm_res = query_vlm(images=images, prompt=prompt)
                
                # Check for positive confirmation in VLM response
                if vlm_res and "YES" in str(vlm_res).upper():
                    total_score += scores["vlm_verification"]
                    feedback.append("VLM confirmed constellation setup activity.")
        except ImportError:
            logger.warning("VLM module not found in path, skipping VLM check.")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")

    passed = total_score >= 60 and six_spacecraft_ok and raan_ok
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }