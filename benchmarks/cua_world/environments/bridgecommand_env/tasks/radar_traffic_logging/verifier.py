#!/usr/bin/env python3
"""
Verifier for radar_traffic_logging task.
Calculates ground truth CPA/TCPA from scenario vectors and compares with agent's CSV log.
"""

import json
import os
import math
import csv
import base64
import io
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_ini(ini_content):
    """Simple parser for Bridge Command INI files."""
    data = {}
    lines = ini_content.splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, val = line.split('=', 1)
        key = key.strip()
        val = val.strip().strip('"')
        data[key] = val
    return data

def parse_othership_ini(ini_content):
    """Parses othership.ini which uses indexed keys like Lat(1)=..."""
    data = {}
    lines = ini_content.splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        
        # Format: Key(Index)=Value or Key(Index,Leg)=Value
        if '(' in line and ')' in line:
            key_part, rest = line.split('(', 1)
            index_part, val = rest.split('=', 1)
            index = index_part.split(')')[0]
            val = val.strip().strip('"')
            
            # We only care about initial state for CPA calc, so ignore legs
            if ',' in index: 
                continue 
                
            if index not in data:
                data[index] = {}
            data[index][key_part.strip()] = val
            
    return data

def calculate_cpa_tcpa(own, target):
    """
    Calculates CPA (nm) and TCPA (min) given ownship and target vectors.
    Uses flat earth approximation which is sufficient for Bridge Command small scale.
    
    Inputs are dicts with: Lat, Long, Heading (deg), Speed (kts)
    """
    # Constants
    NM_PER_DEG_LAT = 60.0
    
    # 1. Convert positions to NM (Cartesian plane, Ownship at start)
    # Mean Lat for Longitude scaling
    mean_lat = (own['lat'] + target['lat']) / 2.0
    nm_per_deg_long = 60.0 * math.cos(math.radians(mean_lat))
    
    # Relative Position Vector (Target - Own)
    d_lat_nm = (target['lat'] - own['lat']) * NM_PER_DEG_LAT
    d_long_nm = (target['long'] - own['long']) * nm_per_deg_long
    
    Rx = d_long_nm
    Ry = d_lat_nm
    
    # 2. Convert Velocity to Components (knots)
    # Heading 0 = North (+Y), 90 = East (+X)
    def get_uv(speed, heading):
        # Heading is clockwise from North
        # math.sin/cos take radians from East counter-clockwise usually
        # Standard Nav: U (East) = S * sin(H), V (North) = S * cos(H)
        rad = math.radians(heading)
        u = speed * math.sin(rad)
        v = speed * math.cos(rad)
        return u, v
        
    Vox, Voy = get_uv(own['spd'], own['hdg'])
    Vtx, Vty = get_uv(target['spd'], target['hdg'])
    
    # Relative Velocity Vector (Target - Own)
    # We want velocity of Target RELATIVE to Ownship
    Vrx = Vtx - Vox
    Vry = Vty - Voy
    
    Vr_mag_sq = Vrx**2 + Vry**2
    
    # 3. Calculate TCPA
    # t = - (R . V) / |V|^2
    # Returns time in hours
    if Vr_mag_sq < 0.001:
        return 999.0, 999.0 # Parallel/Same speed, no CPA
        
    dot_prod = Rx * Vrx + Ry * Vry
    tcpa_hrs = -dot_prod / Vr_mag_sq
    tcpa_min = tcpa_hrs * 60.0
    
    # 4. Calculate CPA
    # Position at TCPA
    CPAx = Rx + Vrx * tcpa_hrs
    CPAy = Ry + Vry * tcpa_hrs
    cpa_dist = math.sqrt(CPAx**2 + CPAy**2)
    
    # If TCPA is past, CPA is the current distance? 
    # Usually in radar, if TCPA < 0, it means CPA passed.
    # But for this task, targets start ahead, so TCPA should be positive.
    
    return cpa_dist, tcpa_min

def verify_radar_traffic_logging(traj, env_info, task_info):
    """
    Verifies the CSV log against physics ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tol_cpa = metadata.get('tolerances', {}).get('cpa_nm', 0.5)
    tol_tcpa = metadata.get('tolerances', {}).get('tcpa_min', 5.0)

    # 1. Read Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check basics
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Traffic log CSV file not found."}
    
    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Traffic log file existed before task start (anti-gaming check failed)."}

    # 3. Parse Ground Truth
    try:
        own_ini = base64.b64decode(result['scenario_data']['ownship_ini_base64']).decode('utf-8')
        other_ini = base64.b64decode(result['scenario_data']['othership_ini_base64']).decode('utf-8')
        
        own_data = parse_ini(own_ini)
        other_data = parse_othership_ini(other_ini)
        
        own_vec = {
            'lat': float(own_data['InitialLat']),
            'long': float(own_data['InitialLong']),
            'hdg': float(own_data['InitialHeading']),
            'spd': float(own_data['InitialSpeed'])
        }
        
        targets_truth = {}
        for idx, t in other_data.items():
            name = t.get('Name', f"Target {idx}").strip('"')
            vec = {
                'lat': float(t['InitLat']),
                'long': float(t['InitLong']),
                'hdg': float(t['InitialHeading']),
                'spd': float(t['InitialSpeed'])
            }
            cpa, tcpa = calculate_cpa_tcpa(own_vec, vec)
            targets_truth[name] = {'cpa': cpa, 'tcpa': tcpa}
            logger.info(f"Ground Truth {name}: CPA={cpa:.2f}nm, TCPA={tcpa:.2f}min")
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error calculating ground truth: {e}"}

    # 4. Parse Agent CSV
    score = 10 # Base score for file existing
    feedback_lines = []
    
    try:
        csv_content = base64.b64decode(result['csv_content_base64']).decode('utf-8')
        csv_reader = csv.DictReader(io.StringIO(csv_content))
        
        # Check Header
        if not csv_reader.fieldnames or 'CPA' not in csv_reader.fieldnames or 'Name' not in csv_reader.fieldnames:
            return {"passed": False, "score": 10, "feedback": "CSV header malformed. Expected Name,CPA,TCPA."}
        
        rows = list(csv_reader)
        if len(rows) < 1:
            return {"passed": False, "score": 10, "feedback": "CSV is empty."}
            
        matched_targets = 0
        
        for row in rows:
            name_logged = row.get('Name', '').strip().strip('"')
            cpa_logged = float(row.get('CPA', -1))
            tcpa_logged = float(row.get('TCPA', -1))
            
            # Find matching ground truth
            # Agent might not type exact name, so simple fuzzy match
            match = None
            for t_name, t_truth in targets_truth.items():
                if t_name.lower() in name_logged.lower() or name_logged.lower() in t_name.lower():
                    match = (t_name, t_truth)
                    break
            
            if match:
                t_name, t_truth = match
                cpa_diff = abs(cpa_logged - t_truth['cpa'])
                
                # Check accuracy
                if cpa_diff <= tol_cpa:
                    score += 30 # 30 points per correct vessel
                    matched_targets += 1
                    feedback_lines.append(f"✓ {t_name}: CPA {cpa_logged} matches ground truth {t_truth['cpa']:.2f}")
                else:
                    feedback_lines.append(f"✗ {t_name}: CPA {cpa_logged} incorrect (expected {t_truth['cpa']:.2f} ± {tol_cpa})")
            else:
                feedback_lines.append(f"? Unknown target logged: {name_logged}")

    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Error parsing CSV: {e}"}

    # 5. Final Scoring
    if matched_targets >= 2:
        pass_task = True
        feedback_lines.append(f"SUCCESS: Logged {matched_targets}/3 vessels correctly.")
    else:
        pass_task = False
        feedback_lines.append(f"FAIL: Only {matched_targets}/3 vessels logged correctly (need 2).")

    return {
        "passed": pass_task,
        "score": min(100, score),
        "feedback": "\n".join(feedback_lines)
    }