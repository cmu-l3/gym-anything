#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_world_catalog_scenario_suite(traj, env_info, task_info):
    """
    Verify the World Catalog and Scenario Suite task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON
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
    feedback_parts = []
    task_start = result.get('task_start', 0)
    available_worlds = set(result.get('available_worlds', []))
    
    # --- PART 1: World Catalog (20 pts) ---
    catalog = result['documents']['world_catalog']
    if catalog['exists']:
        # Anti-gaming: modified after start
        if catalog['mtime'] > task_start:
            score += 5
            feedback_parts.append("World catalog created")
            
            content = catalog.get('content', '')
            # Check for author role
            if "Librarian" in content:
                score += 5
                feedback_parts.append("Catalog has correct author role")
            
            # Check for at least 3 real worlds
            found_worlds = 0
            for world in available_worlds:
                if world in content:
                    found_worlds += 1
            
            if found_worlds >= 3:
                score += 10
                feedback_parts.append(f"Catalog lists {found_worlds} valid worlds")
            else:
                feedback_parts.append(f"Catalog lists only {found_worlds} valid worlds (need 3)")
        else:
            feedback_parts.append("World catalog file is stale (pre-dates task)")
    else:
        feedback_parts.append("World catalog file missing")

    # --- PART 2: Scenarios (50 pts total) ---
    used_worlds = set()
    
    # Scenario 1: Open Water (15 pts)
    s1 = result['scenarios']['s1']
    if s1['exists'] and s1.get('environment') and s1.get('ownship'):
        s1_score = 0
        env = s1['environment']
        own = s1['ownship']
        other = s1.get('othership', {})
        
        # Check World uniqueness
        w1 = env.get('Setting', '')
        if w1: used_worlds.add(w1)
        
        # Check Ship
        if "Pacific Trader" in own.get('ShipName', ''): s1_score += 3
        
        # Check Weather (3.0 - 5.0)
        try:
            w = float(env.get('Weather', -1))
            if 3.0 <= w <= 5.0: s1_score += 3
        except: pass
        
        # Check Vessel Count (2)
        try:
            # Check explicitly for 'Number' key if parsed, or count Type entries
            count = int(other.get('Number', 0))
            # Fallback if parser handled it as dict of Types
            if count == 0 and 'Type' in other: count = len(other['Type'])
            if count == 2: s1_score += 3
        except: pass

        # Basic structure
        s1_score += 6
        
        score += s1_score
        feedback_parts.append(f"Scenario 1 score: {s1_score}/15")
    else:
        feedback_parts.append("Scenario 1 missing or incomplete")

    # Scenario 2: Coastal (15 pts)
    s2 = result['scenarios']['s2']
    if s2['exists'] and s2.get('environment') and s2.get('ownship'):
        s2_score = 0
        env = s2['environment']
        own = s2['ownship']
        other = s2.get('othership', {})
        
        w2 = env.get('Setting', '')
        if w2: used_worlds.add(w2)
        
        if "Dorado Star" in own.get('ShipName', ''): s2_score += 3
        
        # Time (06-08)
        try:
            t = float(env.get('StartTime', -1))
            if 6.0 <= t <= 8.0: s2_score += 3
        except: pass
        
        # Count (3)
        try:
            count = int(other.get('Number', 0))
            if count == 3: s2_score += 3
        except: pass
        
        s2_score += 6
        score += s2_score
        feedback_parts.append(f"Scenario 2 score: {s2_score}/15")

    # Scenario 3: Restricted Viz (20 pts)
    s3 = result['scenarios']['s3']
    if s3['exists'] and s3.get('environment') and s3.get('ownship'):
        s3_score = 0
        env = s3['environment']
        own = s3['ownship']
        other = s3.get('othership', {})
        
        w3 = env.get('Setting', '')
        if w3: used_worlds.add(w3)
        
        if "Northern Express" in own.get('ShipName', ''): s3_score += 3
        
        # Visibility (0.5 - 1.5)
        try:
            v = float(env.get('VisibilityRange', -1))
            if 0.5 <= v <= 1.5: s3_score += 4
        except: pass
        
        # Count (3)
        try:
            count = int(other.get('Number', 0))
            if count == 3: s3_score += 3
        except: pass
        
        s3_score += 10
        score += s3_score
        feedback_parts.append(f"Scenario 3 score: {s3_score}/20")

    # Check Worlds Distinctness
    real_used_worlds = [w for w in used_worlds if w in available_worlds]
    if len(real_used_worlds) == 3:
        # All 3 scenarios use valid, distinct worlds
        pass # points already distributed implicitly by successfully creating them? 
             # Let's add a bonus for distinctness if needed, but score is tight.
             # Actually, if w1=w2, set size is < 3.
             if len(used_worlds) < 3:
                 score -= 10
                 feedback_parts.append("PENALTY: Scenarios do not use 3 distinct worlds")
    else:
         feedback_parts.append(f"Warning: {len(real_used_worlds)} valid worlds used")

    # --- PART 3: Curriculum & Config (30 pts) ---
    
    # Curriculum Mapping (15 pts)
    curr = result['documents']['curriculum']
    if curr['exists'] and curr['mtime'] > task_start:
        curr_score = 5 # Exist
        content = curr.get('content', '').lower()
        if 'stcw' in content: curr_score += 5
        if 'pilotage' in content and 'restricted' in content: curr_score += 5
        score += curr_score
        feedback_parts.append(f"Curriculum mapping: {curr_score}/15")
    else:
        feedback_parts.append("Curriculum mapping missing")

    # Config (15 pts)
    conf = result.get('config', {})
    conf_score = 0
    if str(conf.get('arpa_on', '0')) == '1': conf_score += 3
    if str(conf.get('full_radar', '0')) == '1': conf_score += 4
    if str(conf.get('radar_range_resolution', '0')) == '256': conf_score += 4
    if str(conf.get('max_radar_range', '0')) == '72': conf_score += 4
    
    score += conf_score
    feedback_parts.append(f"Config: {conf_score}/15")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }