#!/usr/bin/env python3
"""
Verifier for two_stage_booster_retrofit task.

Scoring breakdown (100 points total):
  10 pts - File 'two_stage_upgrade.ork' is saved correctly (post-task start)
  25 pts - Multi-stage structure found (XML contains >= 2 <stage> elements)
  15 pts - Booster stage contains a <bodytube> component
  20 pts - Booster stage contains a fin set (required for initial aerodynamic stability)
  15 pts - At least one simulation run successfully ('uptodate' status)
  15 pts - Staging report exists with relevant motor setup and performance keywords

Pass threshold: 65 points, requiring both Multi-Stage Structure and Booster Fins.
"""

import os
import re
import tempfile
import zipfile
import json
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

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

def verify_two_stage_booster_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/two_stage_upgrade.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/staging_report.txt')
    
    score = 0
    feedback_parts = []
    
    # ---- Read Exported JSON Result ----
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env('/tmp/two_stage_result.json', tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        res_data = {}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)
            
    ork_exists = res_data.get('ork_exists', False)
    ork_mtime = res_data.get('ork_mtime', 0)
    task_start_ts = res_data.get('task_start_ts', 0)
    report_exists = res_data.get('report_exists', False)
    report_size = res_data.get('report_size', 0)
    
    if not ork_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Saved rocket file 'two_stage_upgrade.ork' not found."
        }
        
    # Check 1: File created/modified anti-gaming
    if ork_mtime >= task_start_ts and task_start_ts > 0:
        score += 10
        feedback_parts.append("File created/modified correctly [10/10 pts]")
    else:
        feedback_parts.append("File timestamp invalid or missing [0/10 pts]")
        
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
            "score": score,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"
        }
        
    # ---- Analyze Stages ----
    stages = list(ork_root.iter('stage'))
    has_fins = False
    
    if len(stages) >= 2:
        score += 25
        feedback_parts.append(f"Multi-stage structure found ({len(stages)} stages) [25/25 pts]")
        
        # Analyze booster (usually the last stage in the hierarchy tree)
        booster = stages[-1]
        
        # Check for body tube in booster
        if list(booster.iter('bodytube')):
            score += 15
            feedback_parts.append("Booster contains a body tube [15/15 pts]")
        else:
            feedback_parts.append("Booster missing body tube [0/15 pts]")
            
        # Check for fins in booster
        for fin_type in ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset', 'tubefinset']:
            if list(booster.iter(fin_type)):
                has_fins = True
                break
                
        if has_fins:
            score += 20
            feedback_parts.append("Booster contains a fin set [20/20 pts]")
        else:
            feedback_parts.append("Booster missing fin set [0/20 pts]")
            
    else:
        feedback_parts.append(f"Rocket has only {len(stages)} stage(s) [0/25 pts]")
        feedback_parts.append("Booster missing body tube [0/15 pts]")
        feedback_parts.append("Booster missing fin set [0/20 pts]")
        
    # ---- Simulation Check ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                
    if uptodate_count >= 1:
        score += 15
        feedback_parts.append(f"{uptodate_count} uptodate simulation(s) [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations [0/15 pts]")
        
    # ---- Report Check ----
    if report_exists and report_size > 50:
        tmp_rep = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_rep.close()
        try:
            copy_from_env(report_vm_path, tmp_rep.name)
            with open(tmp_rep.name, 'r', errors='ignore') as f:
                content = f.read().lower()
                
            has_motor = bool(re.search(r'[a-z]\d{1,2}-\d|\bmotor\b|\bengine\b', content))
            has_alt = bool(re.search(r'\b(?:apogee|altitude|meters|feet|m|ft)\b', content))
            has_delay = bool(re.search(r'\b0\s*-?\s*sec|\bzero\b|\bdelay\b', content))
            
            if has_motor and has_alt:
                score += 15
                feedback_parts.append("Report has required keywords [15/15 pts]")
            else:
                score += 5
                feedback_parts.append("Report exists but missing key information [5/15 pts]")
        except Exception as e:
            score += 5
            feedback_parts.append("Report exists but couldn't be parsed [5/15 pts]")
        finally:
            if os.path.exists(tmp_rep.name):
                os.unlink(tmp_rep.name)
    else:
        feedback_parts.append("Staging report missing or too small [0/15 pts]")
        
    # Key criteria: Passed only if multi-stage structure created, fins added, and reaching passing threshold
    key_criteria_met = len(stages) >= 2 and has_fins
    passed = (score >= 65) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }