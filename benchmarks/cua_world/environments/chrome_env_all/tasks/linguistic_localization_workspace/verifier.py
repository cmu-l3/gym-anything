#!/usr/bin/env python3
"""
Verifier for linguistic_localization_workspace@1
Verifies:
1. Bookmark folders and categorization
2. Custom search engines (SQLite)
3. Language and bilingual spellcheck settings (Preferences)
4. Auto-translate globally disabled (Preferences)
5. Project assets downloaded
6. VLM Trajectory (Interacted with Settings)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_json_from_env(copy_from_env, filepath):
    """Safely copy and parse a JSON file from the container."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(filepath, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            with open(tmp.name, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception as e:
        logger.error(f"Failed to parse JSON {filepath}: {e}")
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
    return {}

def read_text_from_env(copy_from_env, filepath):
    """Safely copy and read a text file from the container."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    tmp.close()
    try:
        copy_from_env(filepath, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            with open(tmp.name, 'r', encoding='utf-8') as f:
                return f.read()
    except Exception as e:
        logger.error(f"Failed to read text {filepath}: {e}")
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
    return ""

def verify_localization_workspace(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch State Data
    bookmarks = parse_json_from_env(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks")
    prefs = parse_json_from_env(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences")
    result_json = parse_json_from_env(copy_from_env, "/tmp/task_result.json")
    search_engines_txt = read_text_from_env(copy_from_env, "/tmp/search_engines.txt")

    # --- Criterion 1 & 2 & 3: Bookmarks (30 pts) ---
    bookmark_bar = bookmarks.get("roots", {}).get("bookmark_bar", {}).get("children", [])
    
    cat_folder, med_folder, dict_folder = None, None, None
    top_level_personal = 0
    
    for item in bookmark_bar:
        if item.get("type") == "folder":
            name = item.get("name", "").strip()
            if name == "CAT & Platforms": cat_folder = item
            elif name == "Medical Terminology": med_folder = item
            elif name == "Dictionaries & Reference": dict_folder = item
        elif item.get("type") == "url":
            url = item.get("url", "").lower()
            if any(p in url for p in metadata.get('personal_domains', [])):
                top_level_personal += 1

    folders_found = sum([1 for f in (cat_folder, med_folder, dict_folder) if f])
    folder_score = folders_found * 5
    score += folder_score
    feedback_parts.append(f"Bookmark Folders: {folders_found}/3 found ({folder_score}/15 pts)")
    
    # Categorization Check
    def count_matches(folder, domain_list):
        if not folder: return 0
        matches = 0
        for child in folder.get("children", []):
            if child.get("type") == "url":
                url = child.get("url", "").lower()
                if any(d in url for d in domain_list):
                    matches += 1
        return matches

    cat_matches = count_matches(cat_folder, metadata.get('cat_domains', []))
    med_matches = count_matches(med_folder, metadata.get('med_domains', []))
    dict_matches = count_matches(dict_folder, metadata.get('dict_domains', []))
    
    total_matches = cat_matches + med_matches + dict_matches
    cat_score = int((total_matches / 18) * 10) # Max 10 pts
    score += cat_score
    feedback_parts.append(f"Bookmark Categorization: {total_matches}/18 correct ({cat_score}/10 pts)")
    
    # Personal bookmarks cleared
    if top_level_personal == 0:
        score += 5
        feedback_parts.append("Personal Bookmarks: Cleared from top-level (5/5 pts)")
    else:
        feedback_parts.append(f"Personal Bookmarks: {top_level_personal} still at top-level (0/5 pts)")

    # --- Criterion 4: Search Engines (10 pts) ---
    proz_found = "proz" in search_engines_txt and "proz.com/search" in search_engines_txt
    ling_found = "ling" in search_engines_txt and "linguee.com/english-spanish" in search_engines_txt
    
    se_score = (5 if proz_found else 0) + (5 if ling_found else 0)
    score += se_score
    feedback_parts.append(f"Search Engines: Proz={proz_found}, Ling={ling_found} ({se_score}/10 pts)")

    # --- Criterion 5: Language & Spellcheck (10 pts) ---
    accept_langs = prefs.get("intl", {}).get("accept_languages", "")
    spell_dicts = prefs.get("spellcheck", {}).get("dictionaries", [])
    spell_enabled = prefs.get("browser", {}).get("enable_spellchecking", True)
    
    has_spanish_lang = "es" in accept_langs.lower()
    has_bilingual_spell = any("es" in d.lower() for d in spell_dicts) and any("en" in d.lower() for d in spell_dicts)
    
    lang_score = (5 if has_spanish_lang else 0) + (5 if (has_bilingual_spell and spell_enabled) else 0)
    score += lang_score
    feedback_parts.append(f"Language & Spellcheck: ES Lang={has_spanish_lang}, Bilingual Spell={has_bilingual_spell} ({lang_score}/10 pts)")

    # --- Criterion 6: Auto-Translate Disabled (CRITICAL - 10 pts) ---
    # By default it's True. We need it explicitly set to False.
    translate_enabled = prefs.get("translate", {}).get("enabled", True)
    auto_translate_disabled = (translate_enabled is False)
    
    if auto_translate_disabled:
        score += 10
        feedback_parts.append("Auto-Translate: Successfully Disabled (10/10 pts)")
    else:
        feedback_parts.append("Auto-Translate: STILL ENABLED (0/10 pts) [CRITICAL FAILURE]")

    # --- Criterion 7: Files Downloaded (10 pts) ---
    tmx_exists = result_json.get("tmx_exists", False)
    pdf_exists = result_json.get("pdf_exists", False)
    tmx_valid = result_json.get("tmx_created_during_task", False)
    pdf_valid = result_json.get("pdf_created_during_task", False)
    
    download_score = (5 if (tmx_exists and tmx_valid) else 0) + (5 if (pdf_exists and pdf_valid) else 0)
    score += download_score
    feedback_parts.append(f"Downloads: TMX={tmx_valid}, PDF={pdf_valid} ({download_score}/10 pts)")

    # --- Criterion 8: VLM Trajectory Check (20 pts) ---
    vlm_score = 0
    if query_vlm := env_info.get("query_vlm"):
        frames = sample_trajectory_frames(traj, n=5) + [get_final_screenshot(traj)]
        frames = [f for f in frames if f] # Filter Nones
        
        prompt = """Review these frames from a Chrome browser session.
Did the user interact with Chrome Settings (such as looking at Languages, Translation, or Search Engine settings) OR use the Bookmark Manager?
Respond in JSON:
{
    "settings_or_bookmarks_accessed": true/false,
    "reasoning": "What visual evidence supports this"
}"""
        if frames:
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_res.get("parsed", {})
                if parsed.get("settings_or_bookmarks_accessed", False):
                    vlm_score = 20
                    feedback_parts.append(f"VLM: Workflow detected ({vlm_score}/20 pts)")
                else:
                    feedback_parts.append("VLM: Workflow not detected (0/20 pts)")
            except Exception as e:
                feedback_parts.append(f"VLM Error: {e}")
    
    score += vlm_score

    # --- Final Assessment ---
    # Pass requires >= 70 score AND Auto-translate disabled AND at least one file downloaded
    key_criteria_met = auto_translate_disabled and (tmx_valid or pdf_valid)
    passed = (score >= 70) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }