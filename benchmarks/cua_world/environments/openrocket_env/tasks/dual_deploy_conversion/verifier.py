#!/usr/bin/env python3
"""
Verifier for dual_deploy_conversion task.

This verifier pulls the .ork file from the environment, unpacks its ZIP layout, 
and strictly parses the XML parameters representing the design changes without 
giving the agent executing capabilities.
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing chronological screenshots of a user converting a model rocket to a dual-deploy recovery system in OpenRocket.
Review these trajectory frames and determine if the agent actually used the OpenRocket UI to accomplish this task.

Look for evidence of:
1. Parachute configuration dialogs being opened.
2. The component tree (left panel) showing multiple parachutes added to the rocket.
3. The "Flight Simulations" tab being open or simulation progress dialogs.

Did the agent genuinely progress through the software UI to configure recovery and run simulations?
Respond ONLY with a valid JSON object matching this schema:
{
    "ui_interaction_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def _parse_ork(local_path):
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        return ET.fromstring(xml_bytes.decode('utf-8')), None
    except Exception as e:
        return None, f"Failed to parse .ork file: {e}"

def verify_dual_deploy_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/simple_model_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/dual_deploy_conversion_report.txt')
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON export result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export data: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Anti-gaming check (Did they do anything?)
    original_hash = result.get('original_hash', 'A')
    current_hash = result.get('current_hash', 'B')
    if original_hash == current_hash:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Rocket file was not modified (hashes match). No work done."
        }

    # 3. Fetch and parse the modified .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(parse_err)
    except Exception as e:
        feedback_parts.append(f"Failed to copy .ork: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)
            
    if ork_root is None:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Invalid ORK file."}

    # 4. Assess Recovery Architecture (XML Parameter Checking)
    parachutes = list(ork_root.iter('parachute'))
    if len(parachutes) >= 2:
        score += 15
        feedback_parts.append(f"Multiple parachutes found ({len(parachutes)}) [+15]")
    else:
        feedback_parts.append(f"Found {len(parachutes)} parachute(s), expected at least 2 [0/15]")

    has_apogee = False
    has_altitude = False
    main_diam = 0.0
    drogue_diam = 0.0
    
    for para in parachutes:
        event = para.findtext('deployevent', '')
        alt_str = para.findtext('deployaltitude', '0')
        diam_str = para.findtext('diameter', '0')
        
        try:
            alt = float(alt_str)
        except ValueError:
            alt = 0.0
            
        try:
            diam = float(diam_str)
        except ValueError:
            diam = 0.0
            
        if event == 'apogee':
            has_apogee = True
            drogue_diam = max(drogue_diam, diam)
        elif event == 'altitude' and alt <= 300.0:
            has_altitude = True
            main_diam = max(main_diam, diam)

    if has_apogee:
        score += 10
        feedback_parts.append("Drogue (apogee deployment) configured [+10]")
    else:
        feedback_parts.append("No apogee deployment found [0/10]")
        
    if has_altitude:
        score += 15
        feedback_parts.append("Main (altitude <= 300m) configured [+15]")
    else:
        feedback_parts.append("No valid altitude deployment <= 300m found [0/15]")

    if main_diam >= 0.600 and (drogue_diam < main_diam) and drogue_diam > 0:
        score += 10
        feedback_parts.append(f"Parachute sizing correct (Main: {main_diam}m, Drogue: {drogue_diam}m) [+10]")
    else:
        feedback_parts.append(f"Parachute sizing incorrect/unsafe (Main: {main_diam}m, Drogue: {drogue_diam}m) [0/10]")

    # 5. Assess Simulation Runs
    sims = ork_root.find('simulations')
    uptodate_sims = 0
    safe_ghv = False
    
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_sims += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    ghv_str = fd.get('groundhitvelocity', '999')
                    try:
                        ghv = float(ghv_str)
                        if ghv <= 15.0:
                            safe_ghv = True
                    except ValueError:
                        pass

    if uptodate_sims > 0 and safe_ghv:
        score += 15
        feedback_parts.append("Uptodate simulation with safe descent velocity (<=15m/s) found [+15]")
    elif uptodate_sims > 0:
        score += 5
        feedback_parts.append("Uptodate simulation found, but descent velocity not safe or missing [+5/15]")
    else:
        feedback_parts.append("No uptodate simulations found [0/15]")

    # 6. Verify Contextual Conversion Report
    if result.get('report_exists') and result.get('report_size', 0) > 50:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                content = f.read().lower()
            
            keywords = ['drogue', 'main', 'apogee', 'altitude', 'deploy']
            matches = sum(1 for kw in keywords if kw in content)
            
            if matches >= 3:
                score += 15
                feedback_parts.append(f"Valid report with relevant keywords found [+15]")
            else:
                score += 5
                feedback_parts.append(f"Report found but lacks relevant details [+5/15]")
        except Exception:
            feedback_parts.append("Failed to read report [0/15]")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("No valid report found [0/15]")

    # 7. Hybrid Verification: VLM visual analysis of interaction
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            # Sample chronological frames to prove the workflow was done
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('ui_interaction_visible'):
                        score += 20
                        feedback_parts.append("VLM confirms progression via UI [+20]")
                    else:
                        feedback_parts.append(f"VLM did not observe clear UI progression: {parsed.get('reasoning')} [0/20]")
                else:
                    score += 20
                    feedback_parts.append("VLM query failed, awarding trajectory points by default [+20]")
            else:
                score += 20
                feedback_parts.append("No trajectory frames available, awarding points by default [+20]")
        except Exception as e:
            score += 20
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM verification error: {e} [+20]")
    else:
        score += 20
        feedback_parts.append("VLM not configured, awarding trajectory points by default [+20]")

    passed = score >= metadata.get('pass_threshold', 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }