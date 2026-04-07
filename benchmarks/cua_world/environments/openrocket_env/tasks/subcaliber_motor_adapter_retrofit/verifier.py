#!/usr/bin/env python3
"""
Verifier for subcaliber_motor_adapter_retrofit task.

Checks:
1. Original mount preserved: The base large inner tube was not deleted or shrunk (15 pts)
2. 29mm adapter tube exists: A new inner tube with ~14.5mm inner radius exists (25 pts)
3. Adapter rings added: At least 2 new centering rings were added (15 pts)
4. Motor configured in adapter: The new adapter tube acts as a motor mount (15 pts)
5. Altitude constraint met: Up-to-date simulation apogee is >150m and <1000m (20 pts)
6. Verification report: adapter_report.txt exists with required details (10 pts)

Pass threshold: 70 points
"""

import os
import zipfile
import tempfile
import json
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    """Safely parse the OpenRocket zip/xml structure."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        return ET.fromstring(xml_bytes.decode('utf-8')), None
    except Exception as e:
        return None, str(e)

def verify_subcaliber_motor_adapter_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    # Read metadata from export_result.sh
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)
            
    ork_exists = res.get("ork_exists", False)
    report_exists = res.get("report_exists", False)
    baseline_rings = res.get("baseline_rings", 2)
    
    score = 0
    feedback = []
    
    if not ork_exists:
        return {"passed": False, "score": 0, "feedback": "Target output .ork file not found at the expected path."}
        
    # Extract ORK file for deep inspection
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env("/home/ga/Documents/rockets/adapted_dual_deploy.ork", tmp_ork.name)
        ork_root, err = _parse_ork(tmp_ork.name)
    except Exception as e:
        err = str(e)
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)
            
    if not ork_root:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output .ork: {err}"}
        
    # Analyze components
    original_preserved = False
    adapter_exists = False
    adapter_is_mount = False
    
    for it in ork_root.iter('innertube'):
        try:
            r = float(it.findtext('innerradius', '0'))
        except (ValueError, TypeError):
            r = 0.0
            
        # Standard high-power mount from base model (typically 38mm or 54mm diam) -> r > 0.018m
        if r >= 0.018:
            original_preserved = True
            
        # Target 29mm diam -> r = 0.0145m. Tolerance: 0.0140 to 0.0150
        if 0.0140 <= r <= 0.0150:
            adapter_exists = True
            # Validate length requirement
            try:
                length = float(it.findtext('length', '0'))
                if length < 0.110: # small buffer under 120mm requested
                    adapter_exists = False
            except:
                pass
            
            # Check if this adapter was activated as a motor mount
            if it.find('motormount') is not None:
                adapter_is_mount = True
                
    if original_preserved:
        score += 15
        feedback.append("Original motor mount preserved [15/15]")
    else:
        feedback.append("Original motor mount missing/modified (must remain intact) [0/15]")
        
    if adapter_exists:
        score += 25
        feedback.append("29mm adapter tube found with correct dimensions [25/25]")
    else:
        feedback.append("29mm adapter tube not found (check inner diameter and length) [0/25]")
        
    if adapter_is_mount:
        score += 15
        feedback.append("Adapter tube configured as a motor mount [15/15]")
    else:
        feedback.append("Adapter tube not configured as a motor mount [0/15]")
        
    # Analyze Centering Rings
    current_rings = len(list(ork_root.iter('centeringring')))
    if current_rings >= baseline_rings + 2:
        score += 15
        feedback.append(f"Adapter centering rings added (total: {current_rings}, baseline: {baseline_rings}) [15/15]")
    else:
        feedback.append(f"Not enough centering rings added (total: {current_rings}, expected >= {baseline_rings+2}) [0/15]")
        
    # Analyze Flight Data for altitude compliance
    sims = ork_root.find('simulations')
    alt_met = False
    max_alt = 0.0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        alt = float(fd.get('maxaltitude', '0'))
                        max_alt = max(max_alt, alt)
                        if 150 < alt < 1000:
                            alt_met = True
                    except (ValueError, TypeError):
                        pass
                        
    if alt_met:
        score += 20
        feedback.append(f"Simulation apogee compliant ({max_alt:.1f}m inside 150m-1000m limits) [20/20]")
    elif max_alt > 0:
        feedback.append(f"Simulation apogee ({max_alt:.1f}m) outside 150m-1000m limits [0/20]")
    else:
        feedback.append("No up-to-date simulation with flight data found [0/20]")
        
    # Analyze text report
    if report_exists:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env("/home/ga/Documents/exports/adapter_report.txt", tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            if "29" in content:
                score += 10
                feedback.append("Verification report valid [10/10]")
            else:
                feedback.append("Verification report missing key required content ('29') [0/10]")
        except Exception:
            feedback.append("Failed to read report [0/10]")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback.append("Verification report missing [0/10]")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }