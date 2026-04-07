#!/usr/bin/env python3
"""
Verifier for voiceover_comping_assembly task.
Checks that the agent created a composite VO track seamlessly assembling 
three different snippets from three different original take files.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_voiceover_comping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()

    try:
        copy_from_env("/tmp/vo_comping_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Result file not accessible: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if not result.get('session_exists'):
        return {"passed": False, "score": 0.0, "feedback": "Session file missing or invalid."}

    routes = result.get('routes', [])
    
    # Try Optional VLM Verification (Trajectory checks)
    vlm_score = 0
    vlm_feedback = "VLM not available"
    vlm_used = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        if traj:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            prompt = """You are evaluating an agent performing an audio comping task in Ardour DAW.
The agent needs to slice segments from multiple audio tracks, create a new composite track, and arrange the slices chronologically.

Look at the sequence of screenshots.
Did the agent actively work in the Ardour interface (e.g., selecting regions, using the slice/cut tool, dragging clips, adding tracks)?
Does the final screenshot show an arranged sequence of audio clips on a single track?

Respond in JSON format:
{
    "active_editing_observed": true/false,
    "arranged_clips_visible": true/false,
    "reasoning": "brief explanation"
}"""
            res = query_vlm(images=frames + [final], prompt=prompt)
            if res and res.get("success"):
                vlm_used = True
                parsed = res.get("parsed", {})
                if parsed.get("active_editing_observed") and parsed.get("arranged_clips_visible"):
                    vlm_score = 25
                    vlm_feedback = "VLM confirmed editing process"
                else:
                    vlm_score = 10
                    vlm_feedback = f"VLM partial confirmation: {parsed.get('reasoning')}"
    except ImportError:
        pass

    # Dynamic point distribution based on VLM availability
    pts_target = 10
    pts_sources = 15 if vlm_used else 25
    pts_sequence = 15 if vlm_used else 20
    pts_cuts = 15 if vlm_used else 20
    pts_gapless = 10 if vlm_used else 15
    pts_muted = 10
    
    # 1. Target Track Created
    comp_route = None
    for r in routes:
        name = r['name'].lower()
        if 'final' in name or 'comp' in name or 'vo' in name:
            comp_route = r
            break
            
    if not comp_route:
        # Fallback to the track with the most regions
        unmuted_routes = [r for r in routes if not r['muted'] and len(r['regions']) >= 3]
        if unmuted_routes:
            unmuted_routes.sort(key=lambda x: len(x['regions']), reverse=True)
            comp_route = unmuted_routes[0]
            
    if comp_route:
        score += pts_target
        feedback.append(f"Target track identified: '{comp_route['name']}'")
    else:
        feedback.append("Could not identify 'Final VO' or 'Comp' track")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        
    # 2. Region Sources Correct & Correct Sequence
    regions = [reg for reg in comp_route['regions'] if reg['length'] > 0]
    
    # Collect consecutive regions from the same source file taking into consideration sub-regions
    sources_in_order = []
    for reg in regions:
        src = reg['source_file'].lower()
        if 'take' in src:
            if not sources_in_order or sources_in_order[-1]['src'] != src:
                sources_in_order.append({'src': src, 'reg': reg})
                
    actual_sources = [s['src'] for s in sources_in_order]
    
    if len(actual_sources) >= 3:
        seq_found = False
        start_idx = -1
        for i in range(len(actual_sources) - 2):
            if 'take2' in actual_sources[i] and 'take1' in actual_sources[i+1] and 'take3' in actual_sources[i+2]:
                seq_found = True
                start_idx = i
                break
                
        if seq_found:
            score += (pts_sources + pts_sequence)
            feedback.append("Correct region sequence (Take 2 -> Take 1 -> Take 3)")
            
            # 3. Correct Cut Timecodes (Slice correctness)
            reg1 = sources_in_order[start_idx]['reg']
            reg2 = sources_in_order[start_idx+1]['reg']
            reg3 = sources_in_order[start_idx+2]['reg']
            
            t1 = reg1['true_start']
            t2 = reg2['true_start']
            t3 = reg3['true_start']
            
            tol = 44100  # 1 second tolerance
            if abs(t1 - 0) <= tol and abs(t2 - 176400) <= tol and abs(t3 - 529200) <= tol:
                score += pts_cuts
                feedback.append("Correct cut timecodes extracted")
            else:
                feedback.append(f"Cut timecodes incorrect: {t1}, {t2}, {t3}")
                
            # 4. Gapless Assembly
            pos1 = reg1['position']
            len1 = reg1['length']
            pos2 = reg2['position']
            len2 = reg2['length']
            pos3 = reg3['position']
            
            gap1 = abs(pos2 - (pos1 + len1))
            gap2 = abs(pos3 - (pos2 + len2))
            
            if gap1 <= tol and gap2 <= tol:
                score += pts_gapless
                feedback.append("Gapless assembly achieved")
            else:
                feedback.append(f"Gaps found between regions: {gap1}, {gap2} samples")
                
        else:
            feedback.append(f"Region sequence incorrect. Found: {actual_sources}")
    else:
        feedback.append(f"Not enough regions found on track. Sources: {actual_sources}")
        
    # 5. Source Tracks Muted
    unmuted_take_tracks = []
    for r in routes:
        if r == comp_route:
            continue
        if 'take' in r['name'].lower() and not r['muted']:
            if r['regions']:
                unmuted_take_tracks.append(r['name'])
                
    if not unmuted_take_tracks:
        score += pts_muted
        feedback.append("Source tracks properly muted/deleted")
    else:
        feedback.append(f"Source tracks left playing: {unmuted_take_tracks}")
        
    # Assign VLM points if used
    if vlm_used:
        score += vlm_score
        feedback.append(vlm_feedback)
        
    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}