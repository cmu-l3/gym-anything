#!/usr/bin/env python3
import json
import os
import tempfile
import configparser
import io
import re

def verify_heavy_weather_watchkeeping(traj, env_info, task_info):
    """
    Verification for heavy_weather_watchkeeping@1
    
    Checks:
    1. Scenario creation (directory & INI files)
    2. Environmental parameters (Wind, Sea State, Visibility)
    3. Own ship configuration (Type, Speed, Location)
    4. Traffic configuration (Count, Types)
    5. Radar configuration (ARPA, Range)
    6. Documents (Keywords)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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
    
    # Helper to parse fake INI (Bridge Command INIs don't always have sections)
    def parse_bc_ini(content):
        # Add a dummy section header if none exists to use ConfigParser
        if not content: return {}
        content_str = "[root]\n" + content
        cp = configparser.ConfigParser(strict=False, inline_comment_prefixes=(';',))
        try:
            cp.read_string(content_str)
            return dict(cp['root'])
        except Exception:
            # Fallback: simple regex parsing for key=value
            data = {}
            for line in content.splitlines():
                if '=' in line:
                    key, val = line.split('=', 1)
                    data[key.strip()] = val.strip().strip('"')
            return data

    # === CHECK 1: Scenario Existence (10 pts) ===
    if result.get('scenario_exists'):
        score += 10
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Parse files
    env_data = parse_bc_ini(result.get('environment_ini', ''))
    own_data = parse_bc_ini(result.get('ownship_ini', ''))
    oth_data = parse_bc_ini(result.get('othership_ini', ''))
    bc5_data = parse_bc_ini(result.get('bc5_ini', ''))
    
    # === CHECK 2: Environment (20 pts) ===
    env_score = 0
    
    # Setting
    if "English Channel" in env_data.get('setting', '') or "English Channel East" in env_data.get('setting', ''):
        env_score += 4
    
    # Wind Speed (Force 8 = 34-40 kts, task asked for 38)
    try:
        wind = float(env_data.get('windspeed', 0))
        if 34.0 <= wind <= 45.0:
            env_score += 4
        else:
            feedback.append(f"Wind speed {wind} out of Force 8 range (34-45)")
    except: pass
    
    # Wind Direction (SW = 225, task asked for 240)
    try:
        wdir = float(env_data.get('winddirection', 0))
        if 200 <= wdir <= 280:
            env_score += 2
    except: pass
    
    # Weather (Sea State) - task asked for 8.0
    try:
        weather = float(env_data.get('weather', 0))
        if weather >= 7.0:
            env_score += 3
        else:
            feedback.append(f"Weather {weather} too calm for gale")
    except: pass
    
    # Visibility - task asked for 3.0
    try:
        vis = float(env_data.get('visibilityrange', 99))
        if 1.0 <= vis <= 5.0:
            env_score += 4
        else:
            feedback.append(f"Visibility {vis} incorrect (expected 1.0-5.0)")
    except: pass

    # Time - Night
    try:
        time = float(env_data.get('starttime', 12))
        if 0 <= time <= 5 or time >= 21:
            env_score += 3
    except: pass
    
    score += env_score
    feedback.append(f"Environment Score: {env_score}/20")

    # === CHECK 3: Own Ship (15 pts) ===
    own_score = 0
    if "Atlantic Pioneer" in own_data.get('shipname', ''):
        own_score += 5
    
    # Speed - Reduced (<10 kts, task asked 6)
    try:
        spd = float(own_data.get('initialspeed', 20))
        if 3.0 <= spd <= 9.0:
            own_score += 5
        else:
            feedback.append(f"Own ship speed {spd} not appropriate (expected 3-9)")
    except: pass
    
    # Location (Channel East bounds: ~50-51N, 0-2E)
    try:
        lat = float(own_data.get('initiallat', 0))
        lon = float(own_data.get('initiallong', 0))
        if 50.0 <= lat <= 51.5 and -1.0 <= lon <= 2.0:
            own_score += 5
        else:
            feedback.append(f"Own ship pos ({lat},{lon}) outside English Channel East")
    except: pass
    
    score += own_score
    feedback.append(f"Own Ship Score: {own_score}/15")

    # === CHECK 4: Traffic (15 pts) ===
    # Check count
    try:
        num = int(oth_data.get('number', 0))
        if num == 3:
            score += 15
        elif num > 0:
            score += 5
            feedback.append(f"Wrong vessel count: {num} (expected 3)")
        else:
            feedback.append("No traffic vessels found")
    except: pass

    # === CHECK 5: Radar Config (20 pts) ===
    radar_score = 0
    if bc5_data.get('arpa_on') == '1': radar_score += 5
    if bc5_data.get('full_radar') == '1': radar_score += 5
    if bc5_data.get('radar_range_resolution') == '256': radar_score += 5
    if bc5_data.get('max_radar_range') == '48': radar_score += 5
    
    score += radar_score
    feedback.append(f"Radar Score: {radar_score}/20")

    # === CHECK 6: Documents (20 pts) ===
    doc_score = 0
    
    # Briefing
    brief_content = result.get('briefing_content', '').lower()
    if result.get('briefing_exists'):
        # Keywords: force 8, gale, sw, visibility
        if 'force 8' in brief_content or 'force eight' in brief_content or 'gale' in brief_content:
            doc_score += 5
        if 'sw' in brief_content or 'south' in brief_content:
            doc_score += 2.5
        if 'vis' in brief_content:
            doc_score += 2.5
            
    # Standing Orders
    orders_content = result.get('orders_content', '').lower()
    if result.get('orders_exists'):
        # Keywords: master, rule 6, rule 19, cpa
        if 'master' in orders_content: doc_score += 2.5
        if 'rule 6' in orders_content or 'speed' in orders_content: doc_score += 2.5
        if 'rule 19' in orders_content or 'restricted' in orders_content: doc_score += 2.5
        if 'cpa' in orders_content: doc_score += 2.5
        
    score += doc_score
    feedback.append(f"Document Score: {doc_score}/20")

    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }