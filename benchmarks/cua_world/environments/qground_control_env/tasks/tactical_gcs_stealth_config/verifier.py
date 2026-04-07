#!/usr/bin/env python3
"""Verifier for tactical_gcs_stealth_config task.

Checks:
1. RTSP URL = 'rtsp://10.0.5.50:8554/tactical_feed' (30 pts)
2. VideoSource contains 'RTSP' (15 pts)
3. MapProvider contains 'Esri' (15 pts)
4. muteAudio is true (15 pts)
5. qgcTheme is 1 / Outdoor (15 pts)
6. App closed by agent (10 pts)

Total: 100 pts. Pass >= 75 pts.
"""

import json
import os
import tempfile

def verify_tactical_gcs_stealth_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read export result: {e}'}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    details = {}

    ini_data = result.get('ini_data', {})
    
    # 1. RTSP URL (30 pts)
    rtsp = ini_data.get('rtspUrl', '')
    details['rtspUrl'] = rtsp
    if rtsp == 'rtsp://10.0.5.50:8554/tactical_feed':
        score += 30
        feedback.append("RTSP URL correct (+30)")
    elif rtsp:
        feedback.append(f"RTSP URL incorrect ('{rtsp}') (+0/30)")
    else:
        feedback.append("RTSP URL not set (+0/30)")
        
    # 2. VideoSource (15 pts)
    vsrc = ini_data.get('VideoSource', '')
    details['VideoSource'] = vsrc
    if 'rtsp' in vsrc.lower():
        score += 15
        feedback.append("Video Source set to RTSP (+15)")
    else:
        feedback.append(f"Video Source not RTSP ('{vsrc}') (+0/15)")
        
    # 3. MapProvider (15 pts)
    mprov = ini_data.get('MapProvider', '')
    details['MapProvider'] = mprov
    if 'esri' in mprov.lower():
        score += 15
        feedback.append("Map Provider set to Esri (+15)")
    else:
        feedback.append(f"Map Provider not Esri ('{mprov}') (+0/15)")
        
    # 4. muteAudio (15 pts)
    mute = ini_data.get('muteAudio', '')
    details['muteAudio'] = mute
    if mute.lower() == 'true':
        score += 15
        feedback.append("Audio Muted (+15)")
    else:
        feedback.append(f"Audio not muted ('{mute}') (+0/15)")
        
    # 5. qgcTheme (15 pts)
    theme = ini_data.get('qgcTheme', '')
    details['qgcTheme'] = theme
    if theme == '1' or theme.lower() == 'light' or theme.lower() == 'outdoor':
        score += 15
        feedback.append("Theme set to Outdoor/Light (+15)")
    else:
        feedback.append(f"Theme not Outdoor/Light ('{theme}') (+0/15)")
        
    # 6. App closed by agent (10 pts)
    closed = result.get('app_closed_by_agent', False)
    details['app_closed_by_agent'] = closed
    if closed:
        score += 10
        feedback.append("App cleanly closed by agent (+10)")
    else:
        feedback.append("App was left running (+0/10)")

    # Ensure it's not just a blank "do nothing" (e.g., if somehow the default state passed checks)
    if score == 0:
        feedback.append("No correct settings found.")
        
    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }