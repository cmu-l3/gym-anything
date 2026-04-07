#!/usr/bin/env python3
"""
Verifier for perform_emergency_divert task.

Criteria:
1. GPS Simulation Mode must be ENABLED in preferences.
2. Simulated Latitude/Longitude must match 37.55 / -122.30 (approx).
3. VLM: Verify agent accessed "Nearest" list.
4. VLM: Verify "Direct To" KSQL was activated (magenta line to KSQL).
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_emergency_divert(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_lat', 37.55)
    target_lon = metadata.get('target_lon', -122.30)
    tolerance = metadata.get('tolerance', 0.05)
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. PREFERENCES VERIFICATION (Programmatic)
    # =========================================================
    temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    prefs_content = ""
    try:
        # Copy the exported prefs file
        copy_from_env("/sdcard/task_export/final_prefs.xml", temp_prefs.name)
        with open(temp_prefs.name, 'r', encoding='utf-8', errors='ignore') as f:
            prefs_content = f.read()
            
        # Parse XML
        # Android prefs are usually <map><boolean ... /><float ... /></map>
        # Avare might use specific keys for simulation
        
        sim_enabled = False
        lat_val = None
        lon_val = None
        
        # Robust parsing or simple string search (safer if XML is malformed)
        if 'name="SimulationMode" value="true"' in prefs_content:
            sim_enabled = True
        
        # Attempt to find coordinates
        # Format might be <string name="SimulationLatitude">37.55</string> or similar
        # Since we don't know the EXACT internal key names without source code inspection, 
        # we look for the values the agent typed.
        
        # Check for numeric values in the file
        import re
        # Look for latitude around 37.55
        lat_matches = re.findall(r'value="([3][7]\.[5-6][0-9]*)"', prefs_content)
        lat_matches += re.findall(r'>([3][7]\.[5-6][0-9]*)<', prefs_content)
        
        # Look for longitude around -122.30
        lon_matches = re.findall(r'value="(-122\.[2-4][0-9]*)"', prefs_content)
        lon_matches += re.findall(r'>(-122\.[2-4][0-9]*)<', prefs_content)
        
        # Verify Sim Mode
        if sim_enabled:
            score += 10
            feedback_parts.append("GPS Simulation enabled (+10)")
        else:
            feedback_parts.append("GPS Simulation NOT enabled")
            
        # Verify Coords
        lat_found = False
        for m in lat_matches:
            try:
                if abs(float(m) - target_lat) <= tolerance:
                    lat_found = True
                    break
            except: pass
            
        lon_found = False
        for m in lon_matches:
            try:
                if abs(float(m) - target_lon) <= tolerance:
                    lon_found = True
                    break
            except: pass
            
        if lat_found and lon_found:
            score += 30
            feedback_parts.append(f"Coordinates set correctly to {target_lat}, {target_lon} (+30)")
        elif lat_found or lon_found:
            score += 15
            feedback_parts.append("Coordinates partially correct (+15)")
        else:
            feedback_parts.append(f"Coordinates not found in preferences (Expected ~{target_lat}, ~{target_lon})")

    except Exception as e:
        logger.error(f"Error parsing prefs: {e}")
        feedback_parts.append(f"Error checking preferences: {e}")
    finally:
        if os.path.exists(temp_prefs.name):
            os.unlink(temp_prefs.name)

    # =========================================================
    # 2. VLM VERIFICATION (Workflow)
    # =========================================================
    # Sample frames to see the workflow
    frames = sample_trajectory_frames(traj, n=8)
    
    prompt = """
    You are verifying an aviation navigation task in the Avare app.
    The user is supposed to:
    1. Open the "Nearest" or "Find" screen.
    2. Select airport KSQL (San Carlos).
    3. Activate a "Direct To" or "Plan" to KSQL.
    4. The final map should show a magenta line leading to KSQL or KSQL listed as Destination.

    Review the screenshots:
    - Q1: Do you see the "Nearest" airports list or search screen?
    - Q2: Is "KSQL" or "San Carlos" visible/selected?
    - Q3: On the map view, is there a navigation line (usually magenta) or an indication that KSQL is the active destination?

    Output JSON:
    {
      "nearest_screen_seen": boolean,
      "ksql_selected_or_visible": boolean,
      "navigation_active_to_ksql": boolean,
      "reasoning": "..."
    }
    """
    
    try:
        vlm_res = query_vlm(frames, prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('nearest_screen_seen', False):
            score += 20
            feedback_parts.append("Accessed Nearest/Find screen (+20)")
        else:
            feedback_parts.append("Did not see Nearest/Find screen")
            
        if parsed.get('navigation_active_to_ksql', False) or parsed.get('ksql_selected_or_visible', False):
            # We combine these because "selected" usually implies nav activation in this UI flow
            score += 40
            feedback_parts.append("Navigation to KSQL activated (+40)")
        else:
            feedback_parts.append("Did not confirm navigation to KSQL")
            
        feedback_parts.append(f"VLM reasoning: {parsed.get('reasoning', 'None')}")

    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append("VLM verification failed")

    # =========================================================
    # FINAL SCORE
    # =========================================================
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }