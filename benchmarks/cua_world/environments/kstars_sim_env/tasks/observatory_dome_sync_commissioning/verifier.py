#!/usr/bin/env python3
"""
Verifier for observatory_dome_sync_commissioning task.

Criteria (100 pts total, pass >= 60):
1. Dome Simulator Executed (10 pts)
2. Slaving Evidence (15 pts)
3. CSV Formatting (10 pts)
4. Dome Sync Accuracy (20 pts)
5. Temporal & Geographic Truth (45 pts - 15 pts per target)

Mathematically, failing the Temporal/Geographic truth check (meaning the agent faked the CSV without actually doing the slews at the right location/time) limits the max score to 55 points, resulting in an automatic failure.
"""

import base64
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_observatory_dome_sync_commissioning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}
        
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)
    
    # 1. Dome Simulator Executed (10 pts)
    if result.get('dome_running', False):
        score += 10
        feedback.append("Dome simulator driver was executed")
    else:
        feedback.append("Dome simulator driver (indi_simulator_dome) not detected")
        
    # 2. Slaving Evidence (15 pts)
    evidence_exists = result.get('evidence_exists', False)
    evidence_mtime = result.get('evidence_mtime', 0)
    if evidence_exists and evidence_mtime > task_start:
        score += 15
        feedback.append("Slaving evidence screenshot exists and is new")
    elif evidence_exists:
        score += 5
        feedback.append("Slaving evidence screenshot exists but predates task")
    else:
        feedback.append("Slaving evidence screenshot not found")
        
    # 3. CSV Formatting (10 pts)
    csv_exists = result.get('csv_exists', False)
    csv_mtime = result.get('csv_mtime', 0)
    csv_b64 = result.get('csv_content_b64', '')
    
    csv_lines = []
    if csv_exists and csv_mtime > task_start and csv_b64:
        try:
            csv_text = base64.b64decode(csv_b64).decode('utf-8', errors='ignore')
            csv_lines = [line.strip() for line in csv_text.strip().split('\n') if line.strip()]
        except Exception:
            pass
            
    header_valid = False
    data_rows = []
    if csv_lines:
        header = csv_lines[0].lower()
        if "target" in header and "timestamp" in header and "telescope_az" in header and "dome_az" in header:
            header_valid = True
            
        data_rows = csv_lines[1:]
        
    if header_valid and len(data_rows) >= 3:
        score += 10
        feedback.append("CSV format and row count valid")
    elif csv_exists:
        feedback.append("CSV exists but formatting/row count is incorrect")
    else:
        feedback.append("CSV report not found or not updated")
        
    # Process rows
    parsed_data = []
    for row in data_rows:
        parts = row.split(',')
        if len(parts) >= 4:
            target = parts[0].strip().lower()
            ts_str = parts[1].strip()
            try:
                tel_az = float(parts[2].strip())
                dom_az = float(parts[3].strip())
                parsed_data.append({
                    "target": target,
                    "timestamp": ts_str,
                    "tel_az": tel_az,
                    "dom_az": dom_az
                })
            except ValueError:
                continue
                
    # 4. Dome Sync Accuracy (20 pts)
    sync_passed = 0
    if parsed_data:
        for d in parsed_data:
            diff = abs(d['tel_az'] - d['dom_az'])
            diff = min(diff, 360 - diff)
            if diff < 1.0:
                sync_passed += 1
                
        if sync_passed >= 3:
            score += 20
            feedback.append("Dome perfectly synced to telescope azimuth")
        elif sync_passed > 0:
            score += 6 * sync_passed
            feedback.append(f"Dome synced to telescope for {sync_passed} target(s)")
    else:
        feedback.append("Could not read azimuth data from CSV")
        
    # 5. Temporal & Geographic Truth (45 pts)
    truth_score = 0
    try:
        from astropy.time import Time
        from astropy.coordinates import SkyCoord, EarthLocation, AltAz
        import astropy.units as u
        
        siding_spring = EarthLocation(lat=-31.2722*u.deg, lon=149.0661*u.deg, height=1165*u.m)
        
        target_skycoords = {
            "sirius": SkyCoord("06h45m09s", "-16d42m58s", frame='icrs'),
            "canopus": SkyCoord("06h23m57s", "-52d41m44s", frame='icrs'),
            "alpha centauri": SkyCoord("14h39m36s", "-60d50m02s", frame='icrs')
        }
        
        for d in parsed_data:
            target_key = None
            for k in target_skycoords.keys():
                if k in d['target']:
                    target_key = k
                    break
                    
            if not target_key:
                continue
                
            try:
                # Basic formatting standardizer
                ts_clean = d['timestamp'].replace('Z', '').replace(' UTC', '').strip()
                if ' ' in ts_clean and 'T' not in ts_clean:
                    ts_clean = ts_clean.replace(' ', 'T')
                obs_time = Time(ts_clean, format='isot', scale='utc')
            except ValueError:
                try:
                    obs_time = Time(d['timestamp'], format='iso', scale='utc')
                except Exception:
                    continue
                    
            aa_frame = AltAz(obstime=obs_time, location=siding_spring)
            target_sc = target_skycoords[target_key]
            aa_coord = target_sc.transform_to(aa_frame)
            true_az = aa_coord.az.deg
            
            tel_az = d['tel_az']
            az_diff = abs(tel_az - true_az)
            az_diff = min(az_diff, 360 - az_diff)
            
            if az_diff <= 2.0:
                truth_score += 15.0
                
        if truth_score > 0:
            score += int(truth_score)
            feedback.append(f"Geographic/Temporal truth verified for {int(truth_score/15)} target(s)")
        else:
            feedback.append("Geographic/Temporal truth failed (check site Lat/Lon and timestamp)")
            
    except ImportError:
        feedback.append("Astropy not available for truth verification")
        
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }