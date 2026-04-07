#!/usr/bin/env python3
"""
Verifier for design_asset_workspace@1

Checks:
1. Chrome flags configured correctly (Local State) (20 pts)
2. Design resource files downloaded (File System) (20 pts)
3. Custom search engine shortcuts (Preferences) (15 pts)
4. Bookmark folders with correct contents (Bookmarks) (15 pts)
5. No loose bookmarks on bar (Bookmarks) (10 pts)
6. Homepage and startup (Preferences) (10 pts)
7. Download directory and password settings (Preferences) (10 pts)
8. VLM Trajectory Check: Verify agent performed work, not just copying/injecting data
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected Configuration Constants
EXPECTED_FLAGS = [
    "enable-experimental-web-platform-features@1",
    "enable-gpu-rasterization@1",
    "smooth-scrolling@2",
    "enable-quic@2"
]
EXPECTED_SEARCH_KEYWORDS = ["dribbble", "gfonts", "icons"]

DESIGN_TOOLS_DOMAINS = [
    "figma.com", "color.adobe.com", "canva.com", "sketch.com", "invisionapp.com",
    "zeplin.io", "abstract.com", "principleformac.com", "framer.com", "webflow.com",
    "spline.design", "rive.app"
]

INSPIRATION_DOMAINS = [
    "dribbble.com", "behance.net", "awwwards.com", "siteinspire.com",
    "muz.li", "designspiration.com", "pinterest.com", "unsplash.com"
]

VLM_PROMPT = """You are auditing a web design workflow task.
The agent was asked to configure Chrome settings, set Chrome flags (chrome://flags), download files from a local server, and organize bookmarks.

Review these trajectory frames and determine:
1. Is there visual evidence the agent opened Chrome Settings or Chrome Flags?
2. Is there visual evidence the agent accessed the local file server (http://localhost:8080) or downloaded files?
3. Did the agent interact with the Bookmark Manager or the Bookmark Bar?

Respond in JSON:
{
    "accessed_settings_or_flags": true/false,
    "downloaded_files": true/false,
    "organized_bookmarks": true/false,
    "confidence": "high/medium/low"
}
"""

def _extract_file(copy_from_env, container_path: str, local_suffix: str) -> str:
    """Helper to copy a file from the container to a temporary file."""
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=local_suffix)
    temp_file.close()
    try:
        copy_from_env(container_path, temp_file.name)
        if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
            return temp_file.name
    except Exception as e:
        logger.warning(f"Failed to copy {container_path}: {e}")
    
    if os.path.exists(temp_file.name):
        os.unlink(temp_file.name)
    return ""

def _parse_json_file(filepath: str) -> Dict:
    if not filepath or not os.path.exists(filepath):
        return {}
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error parsing JSON from {filepath}: {e}")
        return {}

def _search_json_for_keywords(data, keywords):
    """Recursively search JSON structures for specific keywords (used for search engines)."""
    found = set()
    if isinstance(data, dict):
        for k, v in data.items():
            if isinstance(v, str) and v in keywords:
                found.add(v)
            found.update(_search_json_for_keywords(v, keywords))
    elif isinstance(data, list):
        for item in data:
            if isinstance(item, str) and item in keywords:
                found.add(item)
            found.update(_search_json_for_keywords(item, keywords))
    return found

def verify_design_workspace(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Extract Chrome State Files
    local_state_path = _extract_file(copy_from_env, "/home/ga/.config/google-chrome/Local State", ".json")
    prefs_path = _extract_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Preferences", ".json")
    bookmarks_path = _extract_file(copy_from_env, "/home/ga/.config/google-chrome/Default/Bookmarks", ".json")
    
    local_state = _parse_json_file(local_state_path)
    prefs = _parse_json_file(prefs_path)
    bookmarks = _parse_json_file(bookmarks_path)

    # ---------------------------------------------------------
    # Criterion 1: Chrome Flags (20 pts)
    # ---------------------------------------------------------
    c1_score = 0
    enabled_labs = local_state.get("browser", {}).get("enabled_labs_experiments", [])
    if not enabled_labs:
        # Sometimes it's at the root depending on Chrome version
        enabled_labs = local_state.get("enabled_labs_experiments", [])
    
    found_flags = []
    for flag in EXPECTED_FLAGS:
        if flag in enabled_labs:
            c1_score += 5
            found_flags.append(flag)
    
    score += c1_score
    feedback.append(f"Flags check ({c1_score}/20): Found {len(found_flags)}/4 expected flags.")

    # ---------------------------------------------------------
    # Criterion 2: Downloaded Files (20 pts)
    # ---------------------------------------------------------
    c2_score = 0
    # Copy files to verify content
    json_path = _extract_file(copy_from_env, "/home/ga/projects/design-assets/brand_color_palette.json", ".json")
    svg_path = _extract_file(copy_from_env, "/home/ga/projects/design-assets/icon_sprite_sheet.svg", ".svg")
    pdf_path = _extract_file(copy_from_env, "/home/ga/projects/design-assets/typography_guide.pdf", ".pdf")

    # Check JSON
    if json_path:
        content = _parse_json_file(json_path)
        if "colors" in content:
            c2_score += 7
    # Check SVG
    if svg_path:
        with open(svg_path, 'r') as f:
            if "<svg" in f.read().lower():
                c2_score += 7
    # Check PDF
    if pdf_path:
        with open(pdf_path, 'rb') as f:
            header = f.read(4)
            if header == b'%PDF':
                c2_score += 6

    score += c2_score
    feedback.append(f"Downloads check ({c2_score}/20): Validated file contents.")

    # ---------------------------------------------------------
    # Criterion 3: Search Engines (15 pts)
    # ---------------------------------------------------------
    c3_score = 0
    found_keywords = _search_json_for_keywords(prefs, EXPECTED_SEARCH_KEYWORDS)
    c3_score += len(found_keywords) * 5
    score += c3_score
    feedback.append(f"Search engines ({c3_score}/15): Found {len(found_keywords)}/3 custom keywords.")

    # ---------------------------------------------------------
    # Criterion 4 & 5: Bookmarks Organization (25 pts)
    # ---------------------------------------------------------
    c4_score = 0
    c5_score = 0
    
    bookmark_bar = bookmarks.get("roots", {}).get("bookmark_bar", {}).get("children", [])
    
    loose_urls = 0
    design_tools_count = 0
    inspiration_count = 0

    for item in bookmark_bar:
        if item.get("type") == "url":
            loose_urls += 1
        elif item.get("type") == "folder":
            name = item.get("name", "").lower()
            children_urls = [c.get("url", "") for c in item.get("children", []) if c.get("type") == "url"]
            
            if "design tools" in name:
                for url in children_urls:
                    if any(domain in url for domain in DESIGN_TOOLS_DOMAINS):
                        design_tools_count += 1
            elif "inspiration" in name:
                for url in children_urls:
                    if any(domain in url for domain in INSPIRATION_DOMAINS):
                        inspiration_count += 1

    # C4: Folder contents
    if design_tools_count >= 10:
        c4_score += 8
    elif design_tools_count >= 5:
        c4_score += 4
        
    if inspiration_count >= 6:
        c4_score += 7
    elif inspiration_count >= 3:
        c4_score += 3

    # C5: Loose bookmarks
    if loose_urls == 0:
        c5_score += 10
    elif loose_urls <= 2:
        c5_score += 5

    score += (c4_score + c5_score)
    feedback.append(f"Bookmark Folders ({c4_score}/15): Design({design_tools_count}), Inspiration({inspiration_count}).")
    feedback.append(f"Loose Bookmarks ({c5_score}/10): {loose_urls} loose items found.")

    # ---------------------------------------------------------
    # Criterion 6: Homepage & Startup (10 pts)
    # ---------------------------------------------------------
    c6_score = 0
    # Homepage
    homepage = prefs.get("homepage", "")
    if "figma.com" in homepage:
        c6_score += 5
    
    # Startup
    startup = prefs.get("session", {}).get("restore_on_startup", 0)
    if startup == 1:
        c6_score += 5
        
    score += c6_score
    feedback.append(f"Homepage/Startup ({c6_score}/10).")

    # ---------------------------------------------------------
    # Criterion 7: Download Dir & Password (10 pts)
    # ---------------------------------------------------------
    c7_score = 0
    dl_dir = prefs.get("download", {}).get("default_directory", "")
    if "projects/design-assets" in dl_dir:
        c7_score += 4
        
    prompt = prefs.get("download", {}).get("prompt_for_download", False)
    if prompt is True:
        c7_score += 3
        
    pwd_enabled = prefs.get("profile", {}).get("password_manager_enabled", True)
    cred_service = prefs.get("credentials_enable_service", True)
    if not pwd_enabled or not cred_service:
        c7_score += 3
        
    score += c7_score
    feedback.append(f"Download/Security Settings ({c7_score}/10).")

    # ---------------------------------------------------------
    # Cleanup Temp Files
    # ---------------------------------------------------------
    for p in [local_state_path, prefs_path, bookmarks_path, json_path, svg_path, pdf_path]:
        if p and os.path.exists(p):
            try:
                os.unlink(p)
            except:
                pass

    # ---------------------------------------------------------
    # VLM Verification (Anti-gaming check)
    # ---------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    if final:
        frames.append(final)
        
    if frames:
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            vlm_actions = sum([
                parsed.get("accessed_settings_or_flags", False),
                parsed.get("downloaded_files", False),
                parsed.get("organized_bookmarks", False)
            ])
            if vlm_actions == 0 and score > 40:
                # Agent achieved score without doing any UI actions? Flag as cheating.
                logger.warning("VLM detected no UI actions corresponding to high score. Potential manipulation.")
                feedback.append("VLM WARNING: High score but no UI interactions detected.")
                # We do not explicitly fail them here to prevent false positives from VLM, 
                # but in strict mode we could set passed=False.

    # Final Decision
    # Need 70 points, AND at least one of the major criteria > 0
    major_work_done = (c1_score > 0) or (c2_score > 0) or (c4_score > 0)
    passed = (score >= 70) and major_work_done

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }