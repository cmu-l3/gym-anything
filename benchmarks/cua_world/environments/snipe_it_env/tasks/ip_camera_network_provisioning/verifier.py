#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def parse_mysql_G(text):
    data = {}
    for line in text.split('\n'):
        line = line.strip()
        if line.startswith('*'): continue
        if ':' in line:
            parts = line.split(':', 1)
            key = parts[0].strip()
            val = parts[1].strip()
            if val == 'NULL': val = None
            data[key] = val
    return data

def verify_ip_camera_network_provisioning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
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
            
    score = 0
    feedback = []
    
    cameras = result.get('cameras', {})
    loc_chicago_id = str(result.get('loc_chicago_id', ''))
    status_defective_id = str(result.get('status_defective_id', ''))
    
    manifest = {
        "CAM-0101": {"mac": "E0:CB:4E:AA:BB:01", "ip": "10.40.50.101", "notes": "Main Entrance"},
        "CAM-0102": {"mac": "E0:CB:4E:AA:BB:02", "ip": "10.40.50.102", "notes": "Loading Dock A"},
        "CAM-0103": {"mac": "E0:CB:4E:AA:BB:03", "ip": "10.40.50.103", "notes": "Loading Dock B"},
        "CAM-0104": {"mac": "E0:CB:4E:AA:BB:04", "ip": "10.40.50.104", "notes": "Breakroom"},
        "CAM-0105": {"mac": "E0:CB:4E:AA:BB:05", "ip": "10.40.50.105", "notes": "Server Room"},
    }
    
    def_cam = "CAM-0106"
    
    # Extract asset data
    def get_asset_data(tag):
        cam = cameras.get(tag, {})
        api_data = cam.get('api', {})
        db_raw = cam.get('db', '')
        db_data = parse_mysql_G(db_raw)
        
        # Determine checkout status
        assigned_to = api_data.get('assigned_to', {})
        loc_checkout = False
        
        if assigned_to and isinstance(assigned_to, dict) and assigned_to.get('type') == 'location':
            if assigned_to.get('name') == 'Chicago Facility':
                loc_checkout = True
        
        if not loc_checkout and db_data:
            if db_data.get('assigned_to') == loc_chicago_id and 'Location' in str(db_data.get('assigned_type', '')):
                loc_checkout = True
                
        is_checked_out = False
        if (assigned_to and isinstance(assigned_to, dict) and 'id' in assigned_to) or \
           (db_data and db_data.get('assigned_to') is not None):
            is_checked_out = True
            
        # Extract IP and MAC
        ip_val = ""
        mac_val = ""
        custom_fields = api_data.get('custom_fields', {})
        if isinstance(custom_fields, dict):
            for k, v in custom_fields.items():
                if isinstance(v, dict) and 'value' in v and v['value']:
                    if 'IP' in k:
                        ip_val = str(v['value'])
                    elif 'MAC' in k:
                        mac_val = str(v['value'])
                        
        if not ip_val or not mac_val:
            for k, v in db_data.items():
                if k.startswith('_snipeit_') and v:
                    if re.match(r'^\d{1,3}(\.\d{1,3}){3}$', v):
                        ip_val = v
                    elif re.match(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$', v):
                        mac_val = v
                        
        notes = str(api_data.get('notes') or db_data.get('notes') or "")
        
        status_label = api_data.get('status_label', {})
        status_name = ""
        if isinstance(status_label, dict):
            status_name = str(status_label.get('name', ''))
            
        return {
            "loc_checkout": loc_checkout,
            "is_checked_out": is_checked_out,
            "ip": ip_val,
            "mac": mac_val,
            "notes": notes,
            "status": status_name,
            "db_data": db_data
        }
        
    c1_count = 0
    c2_count = 0
    c3_count = 0
    c4_count = 0
    
    for tag, exp in manifest.items():
        data = get_asset_data(tag)
        
        if data['loc_checkout']: c1_count += 1
        if data['ip'] == exp['ip']: c2_count += 1
        if exp['mac'].lower() in data['mac'].lower(): c3_count += 1
        
        expected_note_prefix = exp['notes'].lower().split()[0]
        if expected_note_prefix in data['notes'].lower():
            c4_count += 1
            
    score += c1_count * 5
    feedback.append(f"C1: {c1_count}/5 functional cameras checked out to Chicago Facility (+{c1_count * 5})")
    
    score += c2_count * 3
    feedback.append(f"C2: {c2_count}/5 functional cameras have correct IP Address (+{c2_count * 3})")
    
    score += c3_count * 3
    feedback.append(f"C3: {c3_count}/5 functional cameras have correct MAC Address (+{c3_count * 3})")
    
    score += c4_count * 2
    feedback.append(f"C4: {c4_count}/5 functional cameras have deployment notes (+{c4_count * 2})")
    
    # Check Defective Camera CAM-0106
    def_data = get_asset_data(def_cam)
    c5_passed = False
    
    db_status = str(def_data['db_data'].get('status_id', ''))
    is_defective_status = 'Defective' in def_data['status'] or (status_defective_id and db_status == status_defective_id)
    
    if is_defective_status and not def_data['is_checked_out'] and not def_data['ip'] and not def_data['mac']:
        c5_passed = True
        score += 15
        feedback.append("C5: CAM-0106 is marked Defective, not checked out, and has empty network fields (+15)")
    else:
        errs = []
        if not is_defective_status: errs.append("not marked Defective")
        if def_data['is_checked_out']: errs.append("is checked out")
        if def_data['ip'] or def_data['mac']: errs.append("has network fields populated")
        feedback.append(f"C5: CAM-0106 failed: {', '.join(errs)} (+0)")
        
    if "DOA" in def_data['notes'].upper() or "cracked" in def_data['notes'].lower():
        score += 10
        feedback.append("C6: CAM-0106 has DOA notes (+10)")
    else:
        feedback.append("C6: CAM-0106 missing DOA notes (+0)")
        
    # C7: Anti-gaming
    initial_assets = int(result.get('initial_asset_count', 0))
    current_assets = int(result.get('current_asset_count', 0))
    if current_assets == initial_assets and current_assets > 0:
        score += 10
        feedback.append("C7: Asset count remained stable, no extra assets created (+10)")
    else:
        feedback.append(f"C7: Asset count changed from {initial_assets} to {current_assets} (+0)")

    # Allow passing if agent got most points and the defective workflow is correct
    key_criteria = (c1_count >= 4 and c2_count >= 4 and c5_passed)
    passed = score >= 75 and key_criteria
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }