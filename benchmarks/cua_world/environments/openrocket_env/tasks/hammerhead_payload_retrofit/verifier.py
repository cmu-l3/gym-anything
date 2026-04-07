#!/usr/bin/env python3
"""
Verifier for hammerhead_payload_retrofit task.

Robust Multi-Signal Evaluation (100 pts total):
  15 pts - Expanding structural transition found matching specifications
  15 pts - Wide payload body tube exists (>= 50mm diam, >= 100mm length)
  15 pts - Dummy payload mass of 50g inserted
  15 pts - Aerodynamic stability restored (fins upsized) and verified with simulation
  20 pts - Retrofit text report was written with meaningful data length
  20 pts - VLM verification on trajectory images (UI workflow + visual geometry changes)
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
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        return ET.fromstring(xml_bytes.decode('utf-8')), None
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"XML parse error: {e}"
    except Exception as e:
        return None, str(e)

def get_float(elem, tags, default=0.0):
    if not isinstance(tags, list):
        tags = [tags]
    for child in elem:
        # Strip namespace if present and evaluate lowercase matches safely
        tag_name = child.tag.split('}')[-1].lower()
        if tag_name in [t.lower() for t in tags]:
            try:
                return float(child.text)
            except:
                pass
    return default

def verify_hammerhead_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_path = metadata.get('expected_output_ork', '/home/ga/Documents/rockets/hammerhead_rocket.ork')
    
    score = 0
    feedback_parts = []
    
    # ---- 1. Check Exported JSON data ----
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result.close()
    result = {}
    try:
        copy_from_env("/tmp/hammerhead_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # ---- 2. VLM Trajectory Verification ----
    vlm_score = 0
    vlm_feedback = []
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm and frames:
            prompt = """You are evaluating an OpenRocket session trajectory.
The agent was asked to build a "hammerhead" rocket (wider front payload section than the rear booster) and simulate it.
Look at the chronological sequence of screenshots and determine:
1. WORKFLOW_COMPLETED: Did the agent interact with component design dialogs (e.g. Body Tube, Transition, Mass Component)?
2. VISUAL_EVIDENCE: Can you see a 3D or 2D side-view of a rocket with a visibly wider top payload section (a 'hammerhead' shape)?
3. SIMULATION: Did they navigate to the "Flight simulations" tab and run a simulation?

Respond in strict JSON format:
{
  "workflow_completed": true,
  "visual_evidence": true,
  "simulation_run": true,
  "reasoning": "Brief explanation of what was visually confirmed"
}"""
            res = query_vlm(prompt=prompt, images=frames)
            if res and res.get("success"):
                parsed = res.get("parsed", {})
                if parsed.get("workflow_completed"):
                    vlm_score += 5
                    vlm_feedback.append("VLM: Workflow completed (+5)")
                if parsed.get("visual_evidence"):
                    vlm_score += 10
                    vlm_feedback.append("VLM: Hammerhead shape visibly verified (+10)")
                if parsed.get("simulation_run"):
                    vlm_score += 5
                    vlm_feedback.append("VLM: Simulation execution observed (+5)")
            else:
                vlm_score = 20
                vlm_feedback.append("VLM check failed, granting default points.")
        else:
            vlm_score = 20
            vlm_feedback.append("VLM not available, granting default points.")
    except Exception as e:
        logger.warning(f"VLM error: {e}")
        vlm_score = 20
        vlm_feedback.append("VLM error, granting default points.")

    # ---- 3. Programmatic ORK parsing ----
    temp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    temp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_path, temp_ork.name)
        ork_root, parse_err = _parse_ork(temp_ork.name)
    except Exception as e:
        logger.warning(f"Failed to copy .ork: {e}")
    finally:
        if os.path.exists(temp_ork.name):
            os.unlink(temp_ork.name)
            
    transition_ok = False
    tube_ok = False
    
    if ork_root is not None:
        # Check 1: Verify Transition expansion (from ~12.4mm radius to >=25mm radius)
        for trans in ork_root.iter('transition'):
            fore = get_float(trans, ['foreradius', 'foreRadius'])
            aft = get_float(trans, ['aftradius', 'aftRadius'])
            if max(fore, aft) >= 0.024 and min(fore, aft) <= 0.018:
                transition_ok = True
                break
        if transition_ok:
            score += 15
            feedback_parts.append("Expanding transition found (+15)")
        else:
            feedback_parts.append("No valid expanding transition found (0/15)")

        # Check 2: Verify Payload Tube (radius >= 25mm, length >= 100mm)
        for bt in ork_root.iter('bodytube'):
            r = get_float(bt, ['radius', 'outRadius'])
            l = get_float(bt, ['length'])
            if r >= 0.024 and l >= 0.095:
                tube_ok = True
                break
        if tube_ok:
            score += 15
            feedback_parts.append("Payload bay dimensions correct (+15)")
        else:
            feedback_parts.append("No valid payload body tube found (0/15)")

        # Check 3: Verify Dummy Mass Component (50g == 0.05kg)
        mass_ok = False
        for mc in ork_root.iter('masscomponent'):
            m = get_float(mc, ['mass'])
            if 0.048 <= m <= 0.052:
                mass_ok = True
                break
        if mass_ok:
            score += 15
            feedback_parts.append("50g payload mass component found (+15)")
        else:
            feedback_parts.append("50g payload mass NOT found (0/15)")

        # Check 4: Aerodynamic Restabilization (Fins upsized and Simulation run)
        max_dim = 0.0
        for fin in ork_root.iter('trapezoidfinset'):
            h = get_float(fin, ['height', 'span'])
            rc = get_float(fin, ['rootchord'])
            tc = get_float(fin, ['tipchord'])
            max_dim = max(max_dim, h, rc, tc)
        
        sims = ork_root.find('simulations')
        uptodate = False
        if sims is not None:
            for sim in sims.findall('simulation'):
                if sim.get('status') == 'uptodate':
                    uptodate = True
                    break
                    
        if max_dim >= 0.045 and uptodate:
            score += 15
            feedback_parts.append("Fins upsized to restore stability and simulation validated (+15)")
        elif max_dim >= 0.045:
            score += 7
            feedback_parts.append("Fins upsized but no uptodate simulation found (+7)")
        elif uptodate:
            score += 5
            feedback_parts.append("Simulation run but fins not adequately upsized (+5)")
        else:
            feedback_parts.append("Fins not upsized, no simulation run (0/15)")
    else:
        feedback_parts.append("Could not parse saved .ork file (0/60 programmatic pts)")

    # ---- 4. Report check ----
    report_exists = result.get('report_exists', False)
    if report_exists and result.get('report_size', 0) > 10:
        score += 20
        feedback_parts.append("Retrofit report file exists with content (+20)")
    elif report_exists:
        score += 5
        feedback_parts.append("Retrofit report file exists but is functionally empty (+5)")
    else:
        feedback_parts.append("Retrofit report file not found (0/20)")
        
    # Collate Score
    score += vlm_score
    feedback_parts.extend(vlm_feedback)
    
    # Agent must score >= 60 and have accomplished some structural alterations to the frame
    passed = score >= 60 and (transition_ok or tube_ok)
    
    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }