#!/usr/bin/env python3
"""
Verifier for Theatrical Lighting Booth Setup (theatrical_lighting_booth_setup@1)

Verifies:
1. Bookmark Archiving (Audio Sites)
2. Bookmark Organization (Lighting Sites by Categories)
3. Site Permissions (WebMIDI/SysEx for specific domains)
4. Chrome Experiments (Web Platform features)
5. Custom Search Engines (ETC and Rosco)
6. Download Directory and Prompt
"""

import os
import sys
import json
import sqlite3
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def copy_and_load_json(copy_from_env, container_path: str) -> dict:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load {container_path}: {e}")
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def copy_and_connect_sqlite(copy_from_env, container_path: str):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
    tmp.close()
    try:
        copy_from_env(container_path, tmp.name)
        return sqlite3.connect(tmp.name), tmp.name
    except Exception as e:
        logger.warning(f"Failed to load DB {container_path}: {e}")
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
        return None, None

def check_folders_and_bookmarks(bookmarks_json: dict, metadata: dict) -> tuple:
    bookmark_bar = bookmarks_json.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    
    archive_score = 0
    org_score = 0
    loose_score = 10
    feedback = []

    # Flatten tree to check loose vs folder
    folders = {child.get('name', '').lower(): child.get('children', []) 
               for child in bookmark_bar if child.get('type') == 'folder'}
    
    loose_bms = [c for c in bookmark_bar if c.get('type') == 'url']
    if len(loose_bms) > 0:
        loose_score = 0
        feedback.append(f"Found {len(loose_bms)} loose bookmarks on the bar. Should be 0.")

    # Check Archive
    archived = []
    for f_name, contents in folders.items():
        if 'archive' in f_name and 'acoustic' in f_name:
            archived = [c.get('url', '') for c in contents if c.get('type') == 'url']
            break
    
    audio_found = sum(1 for url in archived if any(d in url for d in metadata['audio_domains']))
    if audio_found >= 8:
        archive_score = 15
        feedback.append(f"Archive setup correctly ({audio_found}/10 audio bookmarks inside).")
    else:
        archive_score = int((audio_found / 10.0) * 15)
        feedback.append(f"Archive missing or incomplete ({audio_found}/10 audio bookmarks).")

    # Check Lighting Organization
    expected_org = {
        'fixtures': metadata['lighting_fixtures_domains'],
        'control': metadata['lighting_control_domains'],
        'gels': metadata['lighting_gels_domains'],
        'rigging': metadata['lighting_rigging_domains']
    }
    
    correct_lighting = 0
    for target_key, domains in expected_org.items():
        found = False
        for f_name, contents in folders.items():
            if target_key in f_name:
                found = True
                urls = [c.get('url', '') for c in contents if c.get('type') == 'url']
                correct_lighting += sum(1 for url in urls if any(d in url for d in domains))
                break
        if not found:
            feedback.append(f"Missing lighting folder related to: {target_key}")

    if correct_lighting >= 16:
        org_score = 20
        feedback.append(f"Lighting bookmarks organized successfully ({correct_lighting}/20).")
    else:
        org_score = int((correct_lighting / 20.0) * 20)
        feedback.append(f"Lighting organization incomplete ({correct_lighting}/20 correctly placed).")

    return archive_score, org_score, loose_score, feedback

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env missing."}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []

    # 1 & 2. Bookmarks Analysis (15 + 20 + 10 = 45 points)
    bms = copy_and_load_json(copy_from_env, "/tmp/Bookmarks.json")
    if bms:
        a_score, o_score, l_score, fb = check_folders_and_bookmarks(bms, metadata)
        score += (a_score + o_score + l_score)
        feedback_parts.extend(fb)
    else:
        feedback_parts.append("Failed to retrieve Bookmarks.")

    # 3. WebMIDI Permissions & Download Setup (20 + 10 = 30 points)
    prefs = copy_and_load_json(copy_from_env, "/tmp/Preferences.json")
    if prefs:
        # Check WebMIDI
        exceptions = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {})
        midi_sysex = exceptions.get('midi_sysex', {})
        
        malighting_ok = any('malighting.com' in k and v.get('setting') == 1 for k, v in midi_sysex.items())
        etc_ok = any('etcconnect.com' in k and v.get('setting') == 1 for k, v in midi_sysex.items())
        
        midi_score = 0
        if malighting_ok: midi_score += 10
        if etc_ok: midi_score += 10
        score += midi_score
        feedback_parts.append(f"WebMIDI Permissions score: {midi_score}/20")

        # Check Downloads
        dl_dir = prefs.get('download', {}).get('default_directory', '')
        prompt = prefs.get('download', {}).get('prompt_for_download', False)
        
        dl_score = 0
        if 'Lighting_Plots' in dl_dir: dl_score += 5
        if prompt: dl_score += 5
        score += dl_score
        feedback_parts.append(f"Download Management score: {dl_score}/10")
    else:
        feedback_parts.append("Failed to retrieve Preferences.")

    # 4. Chrome Experiments Flag (10 points)
    local_state = copy_and_load_json(copy_from_env, "/tmp/Local_State.json")
    if local_state:
        labs = local_state.get('browser', {}).get('enabled_labs_experiments', [])
        if any('enable-experimental-web-platform-features' in exp for exp in labs):
            score += 10
            feedback_parts.append("Web Platform features flag successfully enabled (10/10).")
        else:
            feedback_parts.append("Web Platform features flag NOT enabled (0/10).")
    else:
        feedback_parts.append("Failed to retrieve Local State.")

    # 5. Custom Search Engines (15 points)
    conn, db_path = copy_and_connect_sqlite(copy_from_env, "/tmp/Web_Data.db")
    search_score = 0
    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT keyword, url FROM keywords")
            rows = cursor.fetchall()
            
            etc_found = any(r[0] == 'etc' and 'etcconnect.com/Search.aspx' in r[1] for r in rows)
            rosco_found = any(r[0] == 'rosco' and 'rosco.com/en/search/site' in r[1] for r in rows)
            
            if etc_found: search_score += 7
            if rosco_found: search_score += 8
            
            score += search_score
            feedback_parts.append(f"Search Engines score: {search_score}/15")
        except Exception as e:
            feedback_parts.append(f"Error reading SQLite: {e}")
        finally:
            conn.close()
            if db_path and os.path.exists(db_path):
                os.unlink(db_path)
    else:
        feedback_parts.append("Failed to retrieve Web Data SQLite DB.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }