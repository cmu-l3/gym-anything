#!/usr/bin/env python3
"""
Verifier for competition_compliance_modification task.

4 injected violations:
  1. Drogue deploy event changed from 'apogee' to 'altitude'
  2. Main deploy altitude set to 500m (must be <=244m / 800ft)
  3. Fins shrunk to 15mm (unstable)
  4. All simulations reset to outdated

Scoring breakdown (100 points total):
  22 pts - Drogue deploy event restored to 'apogee'
  22 pts - Main deploy altitude <= 244m
  21 pts - Fin height >= 50mm (stability restored)
  20 pts - At least one simulation 'uptodate' (re-run after fixes)
  15 pts - Compliance memo exists with meaningful content

Pass threshold: 60 points
  Do-nothing max: 0 (all violations still present, no uptodate sims, no memo)
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


def verify_competition_compliance_modification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/compliance_check.ork')
    memo_vm_path = metadata.get('memo_vm_path', '/home/ga/Documents/exports/compliance_memo.txt')

    score = 0
    feedback_parts = []
    details = {}

    # ---- Copy .ork file from VM ----
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

    # ---- Violation 1: Drogue deploy event must be 'apogee' (22 pts) ----
    drogue_event = None
    main_deploy_alt = None
    for para in ork_root.iter('parachute'):
        name_el = para.find('name')
        name = name_el.text if name_el is not None else ''
        if 'drogue' in name.lower() or 'drouge' in name.lower():
            de = para.findtext('deployevent', '')
            drogue_event = de
        else:
            try:
                da = float(para.findtext('deployaltitude', '999'))
            except (ValueError, TypeError):
                da = 999.0
            main_deploy_alt = da

    details['drogue_deploy_event'] = drogue_event
    details['main_deploy_altitude'] = main_deploy_alt

    if drogue_event == 'apogee':
        score += 22
        feedback_parts.append("Drogue deploys at apogee [22/22 pts]")
    else:
        feedback_parts.append(f"Drogue deploys at '{drogue_event}' (should be apogee) [0/22 pts]")

    # ---- Violation 2: Main deploy altitude <= 244m (22 pts) ----
    if main_deploy_alt is not None and main_deploy_alt <= 244.0:
        score += 22
        feedback_parts.append(f"Main deploy altitude {main_deploy_alt:.0f}m <= 244m [22/22 pts]")
    elif main_deploy_alt is not None:
        feedback_parts.append(f"Main deploy altitude {main_deploy_alt:.0f}m > 244m [0/22 pts]")
    else:
        feedback_parts.append("Could not determine main deploy altitude [0/22 pts]")

    # ---- Violation 3: Fin height >= 50mm (21 pts) ----
    max_fin_height = 0.0
    for fin in ork_root.iter('trapezoidfinset'):
        try:
            h = float(fin.findtext('height', '0'))
            max_fin_height = max(max_fin_height, h)
        except (ValueError, TypeError):
            pass

    details['max_fin_height_m'] = max_fin_height
    if max_fin_height >= 0.050:
        score += 21
        feedback_parts.append(f"Fin height {max_fin_height*1000:.1f}mm >= 50mm [21/21 pts]")
    else:
        feedback_parts.append(f"Fin height {max_fin_height*1000:.1f}mm < 50mm [0/21 pts]")

    # ---- Violation 4: At least one uptodate simulation (20 pts) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1

    details['uptodate_sims'] = uptodate_count
    if uptodate_count >= 1:
        score += 20
        feedback_parts.append(f"{uptodate_count} uptodate sim(s) [20/20 pts]")
    else:
        feedback_parts.append("No uptodate simulations [0/20 pts]")

    # ---- Compliance memo (15 pts) ----
    tmp_memo = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_memo.close()
    memo_score = 0
    try:
        copy_from_env(memo_vm_path, tmp_memo.name)
        with open(tmp_memo.name, 'r', errors='replace') as f:
            memo_text = f.read()

        details['memo_size'] = len(memo_text)
        if len(memo_text) >= 100:
            memo_score = 5
            has_violation_ref = bool(re.search(
                r'violation|compliance|issue|finding|non-conform', memo_text, re.IGNORECASE
            ))
            has_fix_ref = bool(re.search(
                r'fix|correct|resolv|chang|modif|restor', memo_text, re.IGNORECASE
            ))
            has_multiple_items = bool(re.search(
                r'(1\.|2\.|3\.|4\.|\- |fin|parachute|deploy|simulation)',
                memo_text, re.IGNORECASE
            ))
            if has_violation_ref:
                memo_score += 4
            if has_fix_ref:
                memo_score += 3
            if has_multiple_items:
                memo_score += 3
        elif len(memo_text) >= 20:
            memo_score = 3
        score += memo_score
        feedback_parts.append(f"Compliance memo ({len(memo_text)} chars) [{memo_score}/15 pts]")
    except Exception:
        feedback_parts.append("Compliance memo not found [0/15 pts]")
    finally:
        if os.path.exists(tmp_memo.name):
            os.unlink(tmp_memo.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
