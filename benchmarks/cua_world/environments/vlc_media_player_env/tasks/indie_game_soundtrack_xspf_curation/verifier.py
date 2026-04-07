#!/usr/bin/env python3
"""
Verifier for Indie Game Soundtrack XSPF Curation task.

Verifies:
1. Directory structure and copied files.
2. XSPF XML parsing validity.
3. Playlist-level metadata (title, creator).
4. Relative path usage in track <location> (CRITICAL).
5. Clean ID3 titles used instead of raw filenames.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import urllib.parse
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_tag_text(element, tag_name):
    """Helper to find tag text ignoring XML namespaces."""
    for child in element:
        # tag strings might be like '{http://xspf.org/ns/0/}title'
        if child.tag.endswith(tag_name):
            return child.text
    return None


def verify_indie_game_soundtrack_xspf_curation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tracks = metadata.get('expected_tracks', [])
    expected_filenames = [t['filename'] for t in expected_tracks]
    expected_titles = [t['title'] for t in expected_tracks]

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Read JSON Export
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criteria 1: Distribution Directory & Files (15 points)
    dir_exists = result.get('dir_exists', False)
    file_count = result.get('file_count', 0)
    symlink_count = result.get('symlink_count', 0)
    copied_files_str = result.get('copied_files', "")
    copied_files = [f.strip() for f in copied_files_str.split(',')] if copied_files_str else []

    if not dir_exists:
        feedback_parts.append("Directory 'tracks/' not found.")
    else:
        if symlink_count > 0:
            feedback_parts.append(f"Found {symlink_count} symlinks, expected actual files.")
        elif file_count == 12:
            # Check if they are the exact 12
            missing = [f for f in expected_filenames if f not in copied_files]
            if not missing:
                score += 15
                feedback_parts.append("Correct 12 tracks copied.")
            else:
                score += 5
                feedback_parts.append(f"12 tracks copied but missing some targets (e.g., {missing[0]}).")
        else:
            feedback_parts.append(f"Found {file_count} files in 'tracks/', expected 12.")

    # 2. Read XSPF Export
    xspf_exists = result.get('xspf_exists', False)
    if not xspf_exists:
        feedback_parts.append("XSPF file not found.")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    temp_xspf = tempfile.NamedTemporaryFile(delete=False, suffix='.xspf')
    try:
        copy_from_env("/tmp/soundtrack_export.xspf", temp_xspf.name)
        
        # Criteria 2: XSPF Validity (15 points)
        try:
            tree = ET.parse(temp_xspf.name)
            root = tree.getroot()
            score += 15
            feedback_parts.append("XSPF is valid XML.")
        except ET.ParseError:
            feedback_parts.append("XSPF is not valid XML.")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

        # Criteria 3: Playlist Metadata (15 points)
        pl_title = get_tag_text(root, 'title')
        pl_creator = get_tag_text(root, 'creator')
        
        meta_score = 0
        if pl_title and "Cyber-Neon" in pl_title:
            meta_score += 7.5
        if pl_creator and "Neon Syndicate" in pl_creator:
            meta_score += 7.5
            
        score += meta_score
        if meta_score == 15:
            feedback_parts.append("Playlist metadata correct.")
        elif meta_score > 0:
            feedback_parts.append("Playlist metadata partially correct.")
        else:
            feedback_parts.append("Playlist metadata missing or incorrect.")

        # Find the trackList
        trackList = None
        for child in root:
            if child.tag.endswith('trackList'):
                trackList = child
                break

        if not trackList:
            feedback_parts.append("No <trackList> found in XSPF.")
        else:
            tracks = []
            for child in trackList:
                if child.tag.endswith('track'):
                    tracks.append(child)
            
            # Criteria 4 & 5: Track Order, Relative Paths, Titles
            # Track Order (10 points)
            if len(tracks) == 12:
                order_correct = True
                relative_paths_correct = True
                titles_correct = True
                
                for i, track in enumerate(tracks):
                    loc = get_tag_text(track, 'location')
                    title = get_tag_text(track, 'title')
                    
                    if not loc:
                        relative_paths_correct = False
                        order_correct = False
                        continue
                        
                    # Decode URL encoding (e.g. file:tracks/01%20main...)
                    dec_loc = urllib.parse.unquote(loc)
                    
                    # Track Order check
                    if expected_filenames[i] not in dec_loc:
                        order_correct = False
                        
                    # Relative Paths check (20 points)
                    # Must NOT be absolute path
                    if dec_loc.startswith('/') or dec_loc.startswith('file:///') or 'home/ga' in dec_loc:
                        relative_paths_correct = False
                        
                    # Titles check (20 points)
                    if not title or expected_titles[i].lower() not in title.lower():
                        titles_correct = False

                if order_correct:
                    score += 10
                    feedback_parts.append("Track order correct.")
                else:
                    feedback_parts.append("Track order incorrect.")
                    
                if relative_paths_correct:
                    score += 20
                    feedback_parts.append("Relative paths correctly used.")
                else:
                    feedback_parts.append("Absolute paths detected (or invalid <location>).")
                    
                if titles_correct:
                    score += 20
                    feedback_parts.append("Clean ID3 titles used.")
                else:
                    feedback_parts.append("Clean ID3 titles not fully used (messy filenames detected).")
            else:
                feedback_parts.append(f"Found {len(tracks)} tracks in XSPF, expected 12.")

    finally:
        if os.path.exists(temp_xspf.name):
            os.unlink(temp_xspf.name)

    # VLM Trajectory Check (15 points)
    # Checks if the agent legitimately operated the system (file manager, text editor, or VLC GUI)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_prompt = """You are evaluating an agent's desktop trajectory.
The agent was asked to curate audio files by filtering 12 specific MP3s out of 25, copy them to a new folder, and construct an XSPF playlist with relative paths and clean metadata.
Did the agent perform meaningful file manipulation tasks? Look for:
1. File manager windows opening/moving files.
2. Text editor writing XML/XSPF content.
3. Media player (VLC) playlist manipulation.

Respond with valid JSON only:
{"meaningful_action": true/false}"""
                vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('meaningful_action'):
                        score += 5  # Bonus or core part of the total 100 (15+15+15+10+20+20 = 95, so we add 5 here for 100 max)
                        feedback_parts.append("VLM confirmed meaningful desktop actions.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Final decision
    passed = score >= 80  # Strict passing threshold because relative paths and exact metadata are key
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }