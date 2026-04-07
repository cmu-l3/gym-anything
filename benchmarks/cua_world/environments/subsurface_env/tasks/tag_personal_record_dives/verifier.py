#!/usr/bin/env python3
"""Verifier for tag_personal_record_dives task.

Uses a dynamic parsing approach to find the mathematically deepest and longest dives 
in the XML, then checks that *only* those dives contain the expected tags. 
Includes VLM UI trajectory verification to confirm anti-gaming.
"""

import os
import re
import json
import tempfile
import xml.etree.ElementTree as ET

def verify_tag_personal_record_dives(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    feedback = ""
    score = 0
    max_score = 100

    # 1. Evaluate task result JSON
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env('/tmp/task_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get('file_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Logbook was not modified. You must add the tags and save the file."
        }
    
    score += 10 # Base score for modifying and saving the file

    # 2. Extract and Parse the XML logbook
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp_xml.close()
    try:
        copy_from_env('/home/ga/Documents/dives.ssrf', tmp_xml.name)
        try:
            tree = ET.parse(tmp_xml.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": score, "feedback": f"Could not parse SSRF XML: {e}"}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Could not read dives.ssrf: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    def parse_duration(dur_str):
        if not dur_str: return 0
        m = re.search(r'(\d+):(\d+)', dur_str)
        if m: return int(m.group(1)) * 60 + int(m.group(2))
        return 0

    def parse_depth(depth_elem):
        if depth_elem is None: return 0.0
        max_d = depth_elem.get('max', '')
        m = re.search(r'([\d\.]+)', max_d)
        if m: return float(m.group(1))
        return 0.0

    def get_tags(dive):
        tags = []
        # Support attribute-based tags
        attr_tags = dive.get('tags', '')
        if attr_tags:
            tags.extend([t.strip().lower() for t in attr_tags.split(',')])
        # Support child element-based tags
        for tag_elem in dive.iter('tag'):
            if tag_elem.text:
                tags.extend([t.strip().lower() for t in tag_elem.text.split(',')])
        return tags

    # Calculate ground truth extrema
    max_depth = -1.0
    deepest_dives = []
    
    max_duration = -1
    longest_dives = []
    
    for dive in root.iter('dive'):
        dur = parse_duration(dive.get('duration', ''))
        depth = parse_depth(dive.find('depth'))
        
        if depth > max_depth:
            max_depth = depth
            deepest_dives = [dive]
        elif depth == max_depth:
            deepest_dives.append(dive)
            
        if dur > max_duration:
            max_duration = dur
            longest_dives = [dive]
        elif dur == max_duration:
            longest_dives.append(dive)

    # Find the agent's tagged entries
    deep_tagged_dives = []
    long_tagged_dives = []
    
    for dive in root.iter('dive'):
        tags = get_tags(dive)
        if 'record-deep' in tags:
            deep_tagged_dives.append(dive)
        if 'record-long' in tags:
            long_tagged_dives.append(dive)

    # 3. Validation Logic
    deep_correct = False
    for tagged in deep_tagged_dives:
        if tagged in deepest_dives:
            deep_correct = True
            break
            
    long_correct = False
    for tagged in long_tagged_dives:
        if tagged in longest_dives:
            long_correct = True
            break

    false_positives = False
    for tagged in deep_tagged_dives:
        if tagged not in deepest_dives:
            false_positives = True
    for tagged in long_tagged_dives:
        if tagged not in longest_dives:
            false_positives = True

    if deep_correct: score += 25
    if long_correct: score += 25
    
    if not false_positives and (len(deep_tagged_dives) > 0 or len(long_tagged_dives) > 0):
        score += 20
        feedback += "No false positives. "
    elif false_positives:
        feedback += "FALSE POSITIVES DETECTED (Incorrect dives were tagged!). "
    else:
        feedback += "No target tags were found. "

    if deep_correct:
        feedback += f"Deepest dive correctly tagged ({max_depth}m). "
    else:
        feedback += f"Deepest dive ({max_depth}m) NOT correctly tagged. "

    if long_correct:
        feedback += f"Longest dive correctly tagged ({max_duration//60}:{max_duration%60:02d} min). "
    else:
        feedback += f"Longest dive ({max_duration//60}:{max_duration%60:02d} min) NOT correctly tagged. "

    # 4. VLM Trajectory check (Anti-gaming script injection protection)
    vlm_points = 0
    try:
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent))
        from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if frames and final:
            prompt = """
            Verify if the user meaningfully interacted with the Subsurface desktop application UI.
            Did they click on dive list headers (e.g. Depth or Duration) to sort the rows, or type text into the 'Tags' field in the side panel?
            Respond in JSON format with {"interacted": true/false, "reason": "short explanation"}
            """
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res.get("parsed", {}).get("interacted", False):
                vlm_points = 20
                feedback += "[VLM Confirmed UI Trajectory]"
            else:
                feedback += "[VLM Alert: Expected UI trajectory not detected]"
        else:
            vlm_points = 20 # Grant points if framework images fail entirely to prevent random failures
    except Exception as e:
        vlm_points = 20 # Fallback 
        feedback += f"(VLM check skipped: {str(e)})"
        
    score += vlm_points

    return {
        "passed": score >= max_score,
        "score": score,
        "feedback": feedback
    }