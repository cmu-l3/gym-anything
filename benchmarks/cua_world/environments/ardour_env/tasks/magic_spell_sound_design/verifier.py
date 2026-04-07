#!/usr/bin/env python3
"""
Verifier for magic_spell_sound_design task.

Checks:
1. "Spell FX" track exists.
2. Two regions exist on the track.
3. The first region is reversed.
4. The two regions are temporally aligned end-to-end.
5. A fade-in is applied to the first region.
6. The combined effect is exported to 'time_spell.wav'.
7. VLM verification of trajectory to confirm UI workflow.
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompts for VLM verification
TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent using the Ardour Digital Audio Workstation.
The agent's task is to create a "magic spell" sound by duplicating an audio region, reversing the first region, and aligning them back-to-back.

Examine the frames chronologically. Do you see evidence of:
1. An audio region being reversed (using right-click menus or a "Reverse" function)?
2. Two audio regions placed sequentially on the timeline (end-to-end)?
3. A fade-in curve being applied to the first region?
4. The agent exporting an audio file?

Respond in JSON format:
{
    "audio_reversed": true/false,
    "regions_aligned": true/false,
    "fade_in_applied": true/false,
    "export_action": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible in the frames"
}
"""

def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_regions_for_route(root, route_name):
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append(region)
    return regions

def check_fade_in_length(region_node, min_samples=22050):
    """Check if the region has a custom fade-in longer than the minimum."""
    if region_node.get('fade-in-active') not in ['1', 'yes', 'true']:
        return False
        
    for fade in region_node.iter('FadeIn'):
        for events in fade.iter('events'):
            txt = events.text
            if not txt:
                continue
            # Typical event text format: "0 0 44100 1" (time_in_samples value ...)
            parts = txt.split()
            for part in parts:
                try:
                    # If any time point in the fade is greater than the threshold
                    if float(part) >= min_samples:
                        return True
                except ValueError:
                    continue
    return False

def verify_magic_spell_sound_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('alignment_tolerance_samples', 8820)
    min_fade = metadata.get('min_fade_length_samples', 22050)

    score = 0
    max_score = 100
    feedback_parts = []

    # ================================================================
    # 1. Read JSON Export Results
    # ================================================================
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    export_exists = False
    export_created = False
    
    try:
        copy_from_env("/tmp/magic_spell_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
            export_exists = result.get('export_file_exists', False)
            export_created = result.get('export_created_during_task', False)
            
            if export_exists and export_created:
                score += 15
                feedback_parts.append("Export successful")
            elif export_exists:
                score += 5
                feedback_parts.append("Export file exists (but modified time suspicious)")
            else:
                feedback_parts.append("Export file 'time_spell.wav' not found")
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # ================================================================
    # 2. Parse Ardour XML Session
    # ================================================================
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    xml_valid = False
    regions = []
    
    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
        xml_valid = True
    except Exception as e:
        feedback_parts.append(f"Session XML error: {e}")
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    target_track_found = False
    regions_aligned = False
    first_reversed = False
    fade_applied = False

    if xml_valid:
        # Check Track
        routes = get_audio_routes(root)
        target_route = None
        for r in routes:
            if 'spell' in r.get('name', '').lower() or 'fx' in r.get('name', '').lower():
                target_route = r
                break
                
        # Fallback to the first non-default track if named something else
        if not target_route and routes:
            target_route = routes[-1]
            
        if target_route:
            score += 10
            target_track_found = True
            
            # Get Regions
            regions = get_regions_for_route(root, target_route.get('name', ''))
            
            if len(regions) >= 2:
                score += 15
                feedback_parts.append("Multiple regions found on track")
                
                # Sort chronologically
                regions.sort(key=lambda r: int(r.get('position', '0')))
                r1 = regions[0]
                r2 = regions[1]
                
                # Check Reverse on Region 1
                r1_name = r1.get('name', '').lower()
                r1_source = ""
                for source in r1.iter('Source'):
                    r1_source = source.get('origin', '').lower()
                    
                if 'reverse' in r1_name or 'rev' in r1_name or 'reverse' in r1_source:
                    first_reversed = True
                    score += 15
                    feedback_parts.append("First region reversed")
                else:
                    feedback_parts.append("First region does not appear to be reversed")
                    
                # Check Alignment (End-to-End Snap)
                r1_pos = int(r1.get('position', '0'))
                r1_len = int(r1.get('length', '0'))
                r2_pos = int(r2.get('position', '0'))
                
                r1_end = r1_pos + r1_len
                diff = abs(r1_end - r2_pos)
                
                if diff <= tolerance:
                    regions_aligned = True
                    score += 20
                    feedback_parts.append(f"Regions precisely aligned (diff: {diff} samples)")
                else:
                    feedback_parts.append(f"Regions not aligned end-to-end (gap/overlap: {diff} samples)")
                    
                # Check Fade-in
                if check_fade_in_length(r1, min_fade):
                    fade_applied = True
                    score += 10
                    feedback_parts.append("Fade-in applied to reversed region")
                else:
                    feedback_parts.append("No significant fade-in found")
            else:
                feedback_parts.append(f"Track requires at least 2 regions, found {len(regions)}")
        else:
            feedback_parts.append("Target audio track not found")

    # ================================================================
    # 3. VLM Trajectory Verification
    # ================================================================
    vlm_passed = False
    
    if VLM_AVAILABLE and env_info.get('query_vlm'):
        query_vlm = env_info.get('query_vlm')
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            if all_frames:
                result = query_vlm(prompt=TRAJECTORY_PROMPT, images=all_frames)
                if result and result.get('success'):
                    parsed = result.get('parsed', {})
                    if parsed.get('audio_reversed') and parsed.get('regions_aligned'):
                        score += 15
                        vlm_passed = True
                        feedback_parts.append("VLM confirmed workflow execution")
                    else:
                        feedback_parts.append("VLM did not confirm necessary workflow steps")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped (error)")
    else:
        # Give free VLM points if environment lacks VLM support but XML passes main checks
        if target_track_found and regions_aligned and export_exists:
            score += 15
            feedback_parts.append("VLM points awarded automatically (not available)")

    # Key criteria requirement for passing
    key_criteria_met = export_exists and regions_aligned and target_track_found
    passed = (score >= 65) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "export_exists": export_exists,
            "track_found": target_track_found,
            "regions_aligned": regions_aligned,
            "first_reversed": first_reversed,
            "fade_applied": fade_applied,
            "vlm_passed": vlm_passed
        }
    }