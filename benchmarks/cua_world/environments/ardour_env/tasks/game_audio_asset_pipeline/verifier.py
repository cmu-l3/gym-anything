#!/usr/bin/env python3
"""
Verifier for game_audio_asset_pipeline task.
Occupation: Sound Designer / Sound Engineering Technician
Industry: Video Game Development

Checks that the agent organized the DAW session with specific track names,
precise range markers defining game assets, correct gain staging,
exported WAV files, and a written asset manifest document.
"""

import math
import os
import re
import sys
import tempfile
import json
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
SAMPLE_RATE = 44100
TOLERANCE_SAMPLES = int(SAMPLE_RATE * 1.0)  # 1 second tolerance


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_gain_db(route):
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') in ('gaincontrol', 'gain'):
            try:
                val = float(ctrl.get('value', '1.0'))
                if val <= 0:
                    return -120.0
                return 20 * math.log10(val)
            except (ValueError, TypeError):
                return 0.0
    return 0.0

def count_regions(root):
    return sum(1 for _ in root.iter('Region'))

def get_range_markers(root):
    """Get markers that have both start and end, and start != end."""
    ranges = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        start = int(loc.get('start', '0'))
        end = int(loc.get('end', '0'))
        
        # In Ardour, range markers have end > start
        if end > start:
            ranges.append({
                'name': loc.get('name', ''),
                'start': start,
                'end': end
            })
    return ranges


# ---------- Main verifier ----------

def verify_game_audio_asset_pipeline(traj, env_info, task_info):
    """
    Multi-criterion verifier.
    1. Track names (Music, Dialogue)                  (15 pts)
    2. Range markers present (5 of 6)                 (20 pts)
    3. Range positions accurate (within 1s)           (15 pts)
    4. Gain levels (-6 dB Music, 0 dB Dialogue)       (15 pts)
    5. Exported WAV files                             (20 pts)
    6. Asset manifest                                 (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []
    
    metadata = task_info.get('metadata', {})
    asset_specs = metadata.get('asset_specifications', {})
    gain_targets = metadata.get('gain_targets_db', {})

    # ---- Read Export JSON ----
    export_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    export_json_path.close()
    
    export_data = {}
    try:
        copy_from_env("/tmp/game_audio_asset_pipeline_result.json", export_json_path.name)
        with open(export_json_path.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read export JSON: {e}")
    finally:
        if os.path.exists(export_json_path.name):
            os.unlink(export_json_path.name)

    # ---- Read Session XML ----
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    session_exists = export_data.get('session_file_exists', False)
    root = None
    if session_exists:
        try:
            copy_from_env(session_remote, tmp_xml.name)
            if os.path.getsize(tmp_xml.name) > 0:
                tree = ET.parse(tmp_xml.name)
                root = tree.getroot()
        except Exception as e:
            logger.warning(f"XML parse error: {e}")
        finally:
            if os.path.exists(tmp_xml.name):
                os.unlink(tmp_xml.name)

    if root is None:
        return {"passed": False, "score": 0.0, "feedback": "Session file missing or invalid XML."}

    # Verify regions exist (Anti-gaming: ensure audio imported)
    if count_regions(root) == 0:
        return {"passed": False, "score": 0.0, "feedback": "No audio regions in session. Import the source audio."}

    # ================================================================
    # CRITERION 1: Track Names (15 pts)
    # ================================================================
    routes = get_audio_routes(root)
    music_route = None
    dialogue_route = None
    
    for r in routes:
        name_lower = r.get('name', '').lower()
        if 'music' in name_lower:
            music_route = r
        if 'dialogue' in name_lower or 'voice' in name_lower or 'narration' in name_lower:
            dialogue_route = r

    if music_route and dialogue_route:
        score += 15.0
        feedback.append("PASS: Both Music and Dialogue tracks identified.")
    elif music_route or dialogue_route:
        score += 8.0
        feedback.append("PARTIAL: Only one of the required tracks (Music/Dialogue) identified.")
    else:
        feedback.append("FAIL: Required tracks not named correctly.")

    # ================================================================
    # CRITERION 2 & 3: Range Markers (20 pts Presence + 15 pts Position)
    # ================================================================
    ranges = get_range_markers(root)
    
    def normalize_name(n):
        return re.sub(r'[^a-z0-9]', '', n.lower())

    found_assets = 0
    accurate_positions = 0
    
    for expected_key, expected_data in asset_specs.items():
        expected_norm = normalize_name(expected_key)
        
        # Find matching range
        matched_range = None
        for rm in ranges:
            if normalize_name(rm['name']) == expected_norm or expected_norm in normalize_name(rm['name']):
                matched_range = rm
                break
                
        if matched_range:
            found_assets += 1
            # Check position accuracy
            start_diff = abs(matched_range['start'] - expected_data['start'])
            end_diff = abs(matched_range['end'] - expected_data['end'])
            
            if start_diff <= TOLERANCE_SAMPLES and end_diff <= TOLERANCE_SAMPLES:
                accurate_positions += 1

    # Score presence (max 20)
    if found_assets >= 5:
        score += 20.0
    elif found_assets > 0:
        score += (found_assets / 5.0) * 20.0
        
    feedback.append(f"Range markers found: {found_assets}/6")
    
    # Score position accuracy (max 15)
    if accurate_positions >= 5:
        score += 15.0
    elif accurate_positions > 0:
        score += (accurate_positions / 5.0) * 15.0
        
    feedback.append(f"Accurate range positions: {accurate_positions}/6")

    # ================================================================
    # CRITERION 4: Gain Levels (15 pts)
    # ================================================================
    gain_pts = 0.0
    if music_route:
        m_gain = get_route_gain_db(music_route)
        tgt = gain_targets['music']
        if tgt['min'] <= m_gain <= tgt['max']:
            gain_pts += 7.5
            feedback.append(f"Music gain valid ({m_gain:.1f} dB)")
        else:
            feedback.append(f"Music gain out of bounds ({m_gain:.1f} dB)")
            
    if dialogue_route:
        d_gain = get_route_gain_db(dialogue_route)
        tgt = gain_targets['dialogue']
        if tgt['min'] <= d_gain <= tgt['max']:
            gain_pts += 7.5
            feedback.append(f"Dialogue gain valid ({d_gain:.1f} dB)")
        else:
            feedback.append(f"Dialogue gain out of bounds ({d_gain:.1f} dB)")
            
    score += gain_pts

    # ================================================================
    # CRITERION 5: Exported WAV Files (20 pts)
    # ================================================================
    wav_files = export_data.get('wav_files', [])
    valid_exports = 0
    
    for expected_key in asset_specs.keys():
        expected_norm = normalize_name(expected_key)
        
        for w in wav_files:
            if w['size'] > 500 and w['created_during_task']:
                w_norm = normalize_name(w['name'].replace('.wav', ''))
                if w_norm == expected_norm or expected_norm in w_norm:
                    valid_exports += 1
                    break
                    
    if valid_exports >= 5:
        score += 20.0
    elif valid_exports > 0:
        score += (valid_exports / 5.0) * 20.0
        
    feedback.append(f"Valid WAV exports: {valid_exports}/6")

    # ================================================================
    # CRITERION 6: Asset Manifest (15 pts)
    # ================================================================
    manifest_exists = export_data.get('manifest_exists', False)
    manifest_content = export_data.get('manifest_content', '').lower()
    
    if manifest_exists:
        if len(manifest_content.strip()) > 10:
            # Check content quality
            cat_check = 'music' in manifest_content and 'dialogue' in manifest_content
            
            asset_mentions = 0
            for expected_key in asset_specs.keys():
                if expected_key.replace('_', ' ') in manifest_content or expected_key.replace('_', '') in normalize_name(manifest_content):
                    asset_mentions += 1
                    
            if cat_check and asset_mentions >= 4:
                score += 15.0
                feedback.append("PASS: Asset manifest exists and contains correct details.")
            else:
                score += 8.0
                feedback.append(f"PARTIAL: Manifest exists but lacks details (Cats: {cat_check}, Assets: {asset_mentions}/6).")
        else:
            score += 5.0
            feedback.append("PARTIAL: Manifest file created but is empty/too short.")
    else:
        feedback.append("FAIL: Asset manifest not found.")

    # ================================================================
    # FINAL VERDICT
    # ================================================================
    threshold = metadata.get('pass_threshold', 55)
    passed = score >= threshold
    
    return {
        "passed": passed,
        "score": round(score, 1),
        "feedback": " | ".join(feedback)
    }