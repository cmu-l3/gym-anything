#!/usr/bin/env python3
"""
Verifier for booster_reconstruction_downsize task.

Scoring breakdown (100 points total):
  25 pts - Transition Component verified (~101.6mm to ~57.4mm)
  20 pts - New Booster Tube verified (~57.4mm OD, ~600mm length)
  25 pts - Stable Configuration (Stability margin >= 1.0 calibers)
  15 pts - Simulation Verification (At least one 'uptodate' simulation)
  15 pts - Reconstruction Memo (Exists with reasonable technical content)

Pass threshold: 60 points
"""

import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import json


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


def verify_booster_reconstruction_downsize(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Fetch result JSON from the export script
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/reconstruction_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export JSON: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    if not result.get('ork_exists', False):
        return {"passed": False, "score": 0, "feedback": "Rocket file not found."}

    ork_vm_path = result.get('ork_path')
    
    score = 0
    feedback_parts = []
    
    # ---- 1. Copy and Parse .ork file ----
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
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"}

    # ---- 2. Verify Transition (25 pts) ----
    # Expect ~50.8mm (0.0508m) forward radius, ~28.7mm (0.0287m) aft radius
    has_transition = False
    for trans in ork_root.iter('transition'):
        try:
            fr = float(trans.findtext('forwardradius', '0'))
            ar = float(trans.findtext('aftradius', '0'))
            # Allow 5mm tolerance
            if abs(fr - 0.0508) <= 0.005 and abs(ar - 0.0287) <= 0.005:
                has_transition = True
                break
            # Check upside down logic just in case
            if abs(ar - 0.0508) <= 0.005 and abs(fr - 0.0287) <= 0.005:
                has_transition = True
                break
        except (ValueError, TypeError):
            pass

    if has_transition:
        score += 25
        feedback_parts.append("Transition verified [25/25 pts]")
    else:
        feedback_parts.append("Correctly sized transition missing [0/25 pts]")

    # ---- 3. Verify New Booster Tube (20 pts) ----
    # Expect ~28.7mm (0.0287m) radius, ~600mm (0.600m) length
    has_booster = False
    for bt in ork_root.iter('bodytube'):
        try:
            r = float(bt.findtext('radius', '0'))
            l = float(bt.findtext('length', '0'))
            # Allow 5mm radius tolerance and 150mm length tolerance
            if abs(r - 0.0287) <= 0.005 and abs(l - 0.600) <= 0.150:
                has_booster = True
                break
        except (ValueError, TypeError):
            pass

    if has_booster:
        score += 20
        feedback_parts.append("New booster tube verified [20/20 pts]")
    else:
        feedback_parts.append("Correctly sized booster tube missing [0/20 pts]")

    # ---- 4. Verify Simulations and Stability (40 pts total) ----
    uptodate_count = 0
    stable_count = 0
    sims = ork_root.find('simulations')
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        stab = float(fd.get('stabilitymargin', '0'))
                        if stab >= 1.0:
                            stable_count += 1
                    except (ValueError, TypeError):
                        pass

    if uptodate_count > 0:
        score += 15
        feedback_parts.append(f"Simulation is uptodate [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations [0/15 pts]")

    if stable_count > 0:
        score += 25
        feedback_parts.append(f"Stable flight verified (margin >= 1.0) [25/25 pts]")
    else:
        feedback_parts.append("No stable simulations found [0/25 pts]")

    # ---- 5. Verify Memo (15 pts) ----
    memo_exists = result.get('memo_exists', False)
    if memo_exists:
        tmp_memo = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_memo.close()
        try:
            copy_from_env(result.get('memo_path'), tmp_memo.name)
            with open(tmp_memo.name, 'r') as f:
                content = f.read().lower()
                # Check for indicative context words
                keywords = ['57', '54', 'transition', 'stable', 'stability', 'motor']
                found_keywords = sum(1 for w in keywords if w in content)
                
                if len(content) > 20 and found_keywords >= 2:
                    score += 15
                    feedback_parts.append("Memo exists with technical content [15/15 pts]")
                elif len(content) > 0:
                    score += 5
                    feedback_parts.append("Memo exists but lacks detailed keywords [5/15 pts]")
                else:
                    feedback_parts.append("Memo is empty [0/15 pts]")
        except Exception:
            score += 10
            feedback_parts.append("Memo file exists (could not read contents) [10/15 pts]")
        finally:
            if os.path.exists(tmp_memo.name):
                os.unlink(tmp_memo.name)
    else:
        feedback_parts.append("Memo file missing [0/15 pts]")

    # Evaluate Pass condition
    key_criteria = has_transition and has_booster
    passed = (score >= 60) and key_criteria

    if not key_criteria and score >= 60:
        feedback_parts.append("FAILED: Core structural changes (transition + booster) not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }