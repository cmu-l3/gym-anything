#!/usr/bin/env python3
"""
Verifier for airframe_expansion_restabilization task.

Scoring Breakdown (100 points total):
  20 pts - Transition component successfully bridges ~25.4mm to ~41.6mm
  15 pts - Payload Bay (BodyTube) and NoseCone correctly sized at ~41.6mm
  15 pts - Payload Mass component (>=50g) properly integrated
  20 pts - Stability Intervention confirmed (Fins enlarged, sweep increased, or ballast added)
  15 pts - At least one up-to-date simulation run successfully
  15 pts - Summary Report exists with altitude, motor, and stability margin

Pass threshold: 65 points
"""

import os
import re
import tempfile
import zipfile
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except Exception as e:
        return None, str(e)

def verify_airframe_expansion_restabilization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/payload_lofter.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/expansion_report.txt')

    score = 0
    feedback_parts = []

    # Copy files from VM
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
            
        copy_from_env(report_vm_path, tmp_report.name)
    except Exception as e:
        feedback_parts.append(f"File transfer error: {e}")

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve or parse rocket file"
        }

    # CRITERION 1: Transition correctly bridging 25.4mm to 41.6mm OD (radii 0.0127 to 0.0208)
    transition_ok = False
    for t in ork_root.iter('transition'):
        aft = float(t.findtext('aftradius', '0'))
        fore = float(t.findtext('foreradius', '0'))
        # Allow transition direction to be either way (Aft->Fore or Fore->Aft)
        if (abs(aft - 0.0127) < 0.003 and abs(fore - 0.0208) < 0.003) or \
           (abs(fore - 0.0127) < 0.003 and abs(aft - 0.0208) < 0.003):
            transition_ok = True
            break
            
    if transition_ok:
        score += 20
        feedback_parts.append("Transition expands airframe correctly [20/20]")
    else:
        feedback_parts.append("Valid Transition not found [0/20]")

    # CRITERION 2: Payload Bay & Nose at 41.6mm OD (radius 0.0208)
    bay_ok = False
    for bt in ork_root.iter('bodytube'):
        r = float(bt.findtext('radius', '0'))
        if abs(r - 0.0208) < 0.003:
            bay_ok = True
            break

    nose_ok = False
    for nc in ork_root.iter('nosecone'):
        r1 = float(nc.findtext('aftradius', '0'))
        r2 = float(nc.findtext('radius', '0'))
        if abs(r1 - 0.0208) < 0.003 or abs(r2 - 0.0208) < 0.003:
            nose_ok = True
            break
            
    # OpenRocket sometimes allows the NoseCone to purely inherit the radius
    if not nose_ok and len(list(ork_root.iter('nosecone'))) > 0 and bay_ok:
        nose_ok = True

    if bay_ok and nose_ok:
        score += 15
        feedback_parts.append("Expanded Payload Bay and NoseCone present [15/15]")
    else:
        feedback_parts.append("Expanded Payload Bay/Nose missing [0/15]")

    # CRITERION 3: Payload Mass (>=50g / 0.05kg)
    mass_ok = False
    for mc in ork_root.iter('masscomponent'):
        m = float(mc.findtext('mass', '0'))
        if m >= 0.045: # Tolerant to minor rounding
            mass_ok = True
            break
            
    if mass_ok:
        score += 15
        feedback_parts.append("Payload Mass (>=50g) present [15/15]")
    else:
        feedback_parts.append("Payload Mass missing or <50g [0/15]")

    # CRITERION 4: Stability Restored
    # The agent MUST compensate for the CP moving forward
    stability_restored = False
    max_fin_h = 0.0
    max_fin_sweep = 0.0
    
    for fin in ork_root.iter('trapezoidfinset'):
        max_fin_h = max(max_fin_h, float(fin.findtext('height', '0')))
        max_fin_sweep = max(max_fin_sweep, float(fin.findtext('sweep', '0')))

    # Original fin height is ~0.035m, sweep is ~0.020m
    if max_fin_h >= 0.040 or max_fin_sweep >= 0.025:
        stability_restored = True
        
    # Using entirely different fins constitutes an intervention
    if len(list(ork_root.iter('ellipticalfinset'))) > 0 or len(list(ork_root.iter('freeformfinset'))) > 0:
        stability_restored = True
        
    # Adding multiple mass components (e.g. payload + nose ballast)
    if len(list(ork_root.iter('masscomponent'))) >= 2:
        stability_restored = True

    # Heavily extending the booster body tube
    for bt in ork_root.iter('bodytube'):
        r = float(bt.findtext('radius', '0'))
        l = float(bt.findtext('length', '0'))
        if abs(r - 0.0127) < 0.003 and l > 0.32:
            stability_restored = True

    if stability_restored:
        score += 20
        feedback_parts.append("Stability intervention detected [20/20]")
    else:
        feedback_parts.append("No obvious stability intervention detected [0/20]")

    # CRITERION 5: Simulation Run
    sim_ok = False
    for sim in ork_root.iter('simulation'):
        if sim.get('status') == 'uptodate':
            sim_ok = True
            break
            
    if sim_ok:
        score += 15
        feedback_parts.append("Up-to-date simulation found [15/15]")
    else:
        feedback_parts.append("No up-to-date simulation [0/15]")

    # CRITERION 6: Report Valid
    report_ok = False
    if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 0:
        with open(tmp_report.name, 'r') as f:
            text = f.read().lower()
            
        has_motor = re.search(r'\b[a-g]\d{1,2}\b', text) or 'motor' in text
        has_apogee = re.search(r'\b\d+\s*(m|ft|meters|feet)\b', text) or 'apogee' in text or 'altitude' in text
        
        has_stability = False
        stab_matches = re.findall(r'(?:stability|margin|caliber|cal).*?([0-9]*\.[0-9]+)', text)
        if stab_matches:
            for m in stab_matches:
                try:
                    if float(m) >= 0.95: # >= 1.0 ideally, with minor tolerance
                        has_stability = True
                except:
                    pass
                    
        # Give fallback credit if they mentioned stability broadly in a text-heavy format
        if not has_stability and ('stability' in text or 'margin' in text):
            has_stability = True

        if has_motor and has_apogee and has_stability:
            report_ok = True
            
    if report_ok:
        score += 15
        feedback_parts.append("Report contains required metrics [15/15]")
    else:
        feedback_parts.append("Report missing or lacks required metrics [0/15]")

    # Cleanup temp files
    for p in [tmp_ork.name, tmp_report.name]:
        if os.path.exists(p):
            os.unlink(p)

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }