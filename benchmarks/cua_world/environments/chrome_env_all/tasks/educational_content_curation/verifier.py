#!/usr/bin/env python3
"""
Verifier for Educational Content Curation Task (educational_content_curation@1)
Task: Configure shared classroom Chrome browser per Digital Learning Environment spec

Verification Strategy:
- Copy Chrome Bookmarks and Preferences files from container
- Check 7 criteria (100 points total):
  1. Subject-area bookmark folders exist (20 pts)
  2. Bookmarks correctly categorized into folders (10 pts)
  3. Restricted folder with blocked sites (10 pts)
  4. Educational search shortcuts configured (15 pts)
  5. Homepage and startup pages (15 pts)
  6. Content safety settings (15 pts)
  7. Download and authentication settings (15 pts)
- Pass threshold: score >= 70
"""

import logging
import sys
import os
import json
import tempfile
from typing import Dict, List, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'utils'))
try:
    from chrome_verification_utils import (
        parse_bookmarks,
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False

    def parse_bookmarks(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)

    def parse_preferences(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)

    def cleanup_verification_temp():
        pass


# ============================================================
# Domain mappings for categorization verification
# ============================================================

MATH_SCIENCE_DOMAINS = [
    "khanacademy.org",
    "desmos.com",
    "geogebra.org",
    "phet.colorado.edu",
    "wolframalpha.com",
    "nasa.gov",
    "nationalgeographic.org",
    "sciencebuddies.org",
    "ck12.org",
]

CLASSROOM_TOOLS_DOMAINS = [
    "classroom.google.com",
    "quizlet.com",
    "kahoot.com",
    "edpuzzle.com",
    "padlet.com",
    "canva.com",
    "flip.com",
    "nearpod.com",
    "seesaw.me",
    "classdojo.com",
]

RESTRICTED_DOMAINS = [
    "reddit.com",
    "tiktok.com",
    "x.com",
    "twitch.tv",
    "discord.com",
]

# Folder name patterns for flexible matching
FOLDER_PATTERNS = {
    "math_science": ["math", "science"],
    "language_arts": ["language", "arts"],
    "social_civics": ["social", "civics"],
    "classroom": ["classroom", "tools"],
    "restricted": ["restricted", "teacher"],
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for educational_content_curation@1.

    Checks 7 criteria across bookmarks and preferences for a total of 100 points.
    Pass threshold: score >= 70.

    Args:
        traj: Agent trajectory (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information

    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Extract Bookmarks and Preferences from container
        bookmarks_data = _copy_json_from_env(
            copy_from_env,
            [
                "/home/ga/.config/google-chrome/Default/Bookmarks",
                "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
                "/tmp/bookmarks_export.json",
            ],
            "Bookmarks"
        )

        prefs_data = _copy_json_from_env(
            copy_from_env,
            [
                "/home/ga/.config/google-chrome/Default/Preferences",
                "/home/ga/.config/google-chrome-cdp/Default/Preferences",
                "/tmp/preferences_export.json",
            ],
            "Preferences"
        )

        # Run all 7 criteria checks
        scores = {}
        feedback_parts = []

        feedback_parts.append("=" * 60)
        feedback_parts.append("EDUCATIONAL CONTENT CURATION VERIFICATION")
        feedback_parts.append("=" * 60)

        # Criterion 1: Subject-area bookmark folders (20 pts)
        s1, f1 = _check_bookmark_folders(bookmarks_data)
        scores["bookmark_folders"] = s1
        feedback_parts.append(f"\n1. SUBJECT-AREA BOOKMARK FOLDERS ({s1}/20 pts):")
        feedback_parts.extend(["   " + line for line in f1])

        # Criterion 2: Bookmarks correctly categorized (10 pts)
        s2, f2 = _check_bookmark_categorization(bookmarks_data)
        scores["bookmark_categorization"] = s2
        feedback_parts.append(f"\n2. BOOKMARK CATEGORIZATION ({s2}/10 pts):")
        feedback_parts.extend(["   " + line for line in f2])

        # Criterion 3: Restricted folder with blocked sites (10 pts)
        s3, f3 = _check_restricted_folder(bookmarks_data)
        scores["restricted_folder"] = s3
        feedback_parts.append(f"\n3. RESTRICTED FOLDER ({s3}/10 pts):")
        feedback_parts.extend(["   " + line for line in f3])

        # Criterion 4: Educational search shortcuts (15 pts)
        s4, f4 = _check_search_shortcuts(prefs_data)
        scores["search_shortcuts"] = s4
        feedback_parts.append(f"\n4. EDUCATIONAL SEARCH SHORTCUTS ({s4}/15 pts):")
        feedback_parts.extend(["   " + line for line in f4])

        # Criterion 5: Homepage and startup (15 pts)
        s5, f5 = _check_homepage_startup(prefs_data)
        scores["homepage_startup"] = s5
        feedback_parts.append(f"\n5. HOMEPAGE AND STARTUP ({s5}/15 pts):")
        feedback_parts.extend(["   " + line for line in f5])

        # Criterion 6: Content safety settings (15 pts)
        s6, f6 = _check_content_safety(prefs_data)
        scores["content_safety"] = s6
        feedback_parts.append(f"\n6. CONTENT SAFETY SETTINGS ({s6}/15 pts):")
        feedback_parts.extend(["   " + line for line in f6])

        # Criterion 7: Download and auth settings (15 pts)
        s7, f7 = _check_download_auth_settings(prefs_data)
        scores["download_auth"] = s7
        feedback_parts.append(f"\n7. DOWNLOAD AND AUTH SETTINGS ({s7}/15 pts):")
        feedback_parts.extend(["   " + line for line in f7])

        # Calculate final score
        total_score = sum(scores.values())
        passed = total_score >= 70

        feedback_parts.append("\n" + "=" * 60)
        feedback_parts.append(f"TOTAL SCORE: {total_score}/100")
        feedback_parts.append(f"PASS THRESHOLD: 70")
        feedback_parts.append(f"RESULT: {'PASSED' if passed else 'FAILED'}")
        feedback_parts.append("=" * 60)

        cleanup_verification_temp()

        return {
            "passed": passed,
            "score": total_score,
            "feedback": "\n".join(feedback_parts),
            "details": scores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


# ============================================================
# Helper: copy JSON file from container
# ============================================================

def _copy_json_from_env(copy_from_env, paths: List[str], label: str) -> Optional[Dict]:
    """
    Try to copy and parse a JSON file from multiple container paths.

    Args:
        copy_from_env: Function to copy files from container
        paths: List of container paths to try
        label: Human-readable label for logging

    Returns:
        Parsed JSON dict, or None if all attempts fail
    """
    for container_path in paths:
        temp_file = None
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            temp_path = temp_file.name
            temp_file.close()

            logger.info(f"Trying to copy {label} from: {container_path}")
            copy_from_env(container_path, temp_path)

            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                with open(temp_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                logger.info(f"Successfully loaded {label} from: {container_path}")
                os.unlink(temp_path)
                return data

        except Exception as e:
            logger.debug(f"Failed to copy {label} from {container_path}: {e}")
        finally:
            if temp_file and os.path.exists(temp_file.name):
                try:
                    os.unlink(temp_file.name)
                except OSError:
                    pass

    logger.warning(f"Could not retrieve {label} from any known location")
    return None


# ============================================================
# Helper: find folders on the bookmark bar
# ============================================================

def _get_bookmark_bar_children(bookmarks_data: Optional[Dict]) -> List[Dict]:
    """Return children of the bookmark bar, or empty list."""
    if not bookmarks_data:
        return []
    try:
        return bookmarks_data.get('roots', {}).get('bookmark_bar', {}).get('children', [])
    except Exception:
        return []


def _find_folder_flexible(children: List[Dict], keywords: List[str]) -> Optional[Dict]:
    """
    Find a folder whose name contains ALL of the given keywords (case-insensitive).

    Args:
        children: Bookmark bar children list
        keywords: List of keywords that must all appear in the folder name

    Returns:
        The folder dict if found, else None
    """
    for child in children:
        if child.get('type') != 'folder':
            continue
        name_lower = child.get('name', '').lower()
        if all(kw in name_lower for kw in keywords):
            return child
    return None


def _get_urls_in_folder(folder: Dict) -> List[str]:
    """Return all URLs (lowercased) inside a folder (non-recursive)."""
    urls = []
    for child in folder.get('children', []):
        if child.get('type') == 'url':
            urls.append(child.get('url', '').lower())
    return urls


def _count_domain_matches(urls: List[str], domains: List[str]) -> int:
    """Count how many of the given domains appear in the URL list."""
    matched = 0
    for domain in domains:
        if any(domain in url for url in urls):
            matched += 1
    return matched


# ============================================================
# Criterion 1: Subject-area bookmark folders (20 pts)
# ============================================================

def _check_bookmark_folders(bookmarks_data: Optional[Dict]):
    """
    Check for at least 4 of the 5 required folders on the bookmark bar.
    Uses flexible matching (case-insensitive, partial match for key words).

    Award: 20 pts if >= 4 folders found, 4 pts per folder otherwise.
    """
    feedback = []

    if not bookmarks_data:
        return 0, ["Could not access bookmarks file"]

    children = _get_bookmark_bar_children(bookmarks_data)
    if not children:
        return 0, ["Bookmark bar is empty"]

    found_count = 0
    for label, keywords in FOLDER_PATTERNS.items():
        folder = _find_folder_flexible(children, keywords)
        if folder:
            found_count += 1
            feedback.append(f"Found folder: '{folder.get('name')}' (matches {label})")
        else:
            feedback.append(f"Missing folder for: {label} (keywords: {keywords})")

    if found_count >= 4:
        score = 20
        feedback.insert(0, f"Found {found_count}/5 required folders - PASS")
    else:
        score = found_count * 4  # 4 pts per folder
        feedback.insert(0, f"Found {found_count}/5 required folders (need >= 4) - PARTIAL")

    logger.info(f"Criterion 1 - Bookmark folders: {found_count}/5 found, score={score}")
    return score, feedback


# ============================================================
# Criterion 2: Bookmarks correctly categorized (10 pts)
# ============================================================

def _check_bookmark_categorization(bookmarks_data: Optional[Dict]):
    """
    Check that at least 6 math/science bookmarks are in the math/science folder
    AND at least 6 classroom tools are in the classroom tools folder.

    Award: 5 pts for math/science >= 6, 5 pts for classroom tools >= 6.
    """
    feedback = []

    if not bookmarks_data:
        return 0, ["Could not access bookmarks file"]

    children = _get_bookmark_bar_children(bookmarks_data)
    score = 0

    # Check math/science folder
    math_folder = _find_folder_flexible(children, FOLDER_PATTERNS["math_science"])
    if math_folder:
        urls = _get_urls_in_folder(math_folder)
        math_count = _count_domain_matches(urls, MATH_SCIENCE_DOMAINS)
        feedback.append(f"Math/Science folder: {math_count}/{len(MATH_SCIENCE_DOMAINS)} expected bookmarks found")
        if math_count >= 6:
            score += 5
            feedback.append("  -> Math/Science categorization: PASS")
        else:
            feedback.append(f"  -> Need >= 6 math/science bookmarks (found {math_count})")
    else:
        feedback.append("Math/Science folder not found - cannot check categorization")

    # Check classroom tools folder
    tools_folder = _find_folder_flexible(children, FOLDER_PATTERNS["classroom"])
    if tools_folder:
        urls = _get_urls_in_folder(tools_folder)
        tools_count = _count_domain_matches(urls, CLASSROOM_TOOLS_DOMAINS)
        feedback.append(f"Classroom Tools folder: {tools_count}/{len(CLASSROOM_TOOLS_DOMAINS)} expected bookmarks found")
        if tools_count >= 6:
            score += 5
            feedback.append("  -> Classroom Tools categorization: PASS")
        else:
            feedback.append(f"  -> Need >= 6 classroom tools bookmarks (found {tools_count})")
    else:
        feedback.append("Classroom Tools folder not found - cannot check categorization")

    logger.info(f"Criterion 2 - Bookmark categorization: score={score}")
    return score, feedback


# ============================================================
# Criterion 3: Restricted folder with blocked sites (10 pts)
# ============================================================

def _check_restricted_folder(bookmarks_data: Optional[Dict]):
    """
    Check that the restricted folder contains at least 3 of the 5 blocked sites.

    Award: 10 pts if >= 3 restricted sites found.
    """
    feedback = []

    if not bookmarks_data:
        return 0, ["Could not access bookmarks file"]

    children = _get_bookmark_bar_children(bookmarks_data)

    restricted_folder = _find_folder_flexible(children, FOLDER_PATTERNS["restricted"])
    if not restricted_folder:
        return 0, ["Restricted folder not found on bookmark bar"]

    urls = _get_urls_in_folder(restricted_folder)
    restricted_count = _count_domain_matches(urls, RESTRICTED_DOMAINS)

    found_sites = []
    missing_sites = []
    for domain in RESTRICTED_DOMAINS:
        if any(domain in url for url in urls):
            found_sites.append(domain)
        else:
            missing_sites.append(domain)

    feedback.append(f"Restricted folder: {restricted_count}/{len(RESTRICTED_DOMAINS)} blocked sites found")
    if found_sites:
        feedback.append(f"  Found: {', '.join(found_sites)}")
    if missing_sites:
        feedback.append(f"  Missing: {', '.join(missing_sites)}")

    if restricted_count >= 3:
        score = 10
        feedback.append("  -> Restricted folder: PASS")
    else:
        score = 0
        feedback.append("  -> Need >= 3 restricted sites in folder")

    logger.info(f"Criterion 3 - Restricted folder: {restricted_count}/5, score={score}")
    return score, feedback


# ============================================================
# Criterion 4: Educational search shortcuts (15 pts)
# ============================================================

def _check_search_shortcuts(prefs_data: Optional[Dict]):
    """
    Check Preferences for search engines with keywords 'learn', 'wiki', 'pbs'.
    Award 5 pts per engine found.
    """
    feedback = []
    expected_keywords = ["learn", "wiki", "pbs"]

    if not prefs_data:
        return 0, ["Could not access Preferences file"]

    score = 0
    found_keywords = []

    # Search engines can be in multiple locations in Preferences
    # Check default_search_provider_data for custom search engines
    # Also check the search engines list under various paths
    search_engines = _extract_search_engines(prefs_data)

    for kw in expected_keywords:
        found = False
        for engine in search_engines:
            engine_keyword = engine.get('keyword', '').lower().strip()
            engine_short_name = engine.get('short_name', '').lower()
            if engine_keyword == kw or kw in engine_keyword:
                found = True
                feedback.append(f"Found search shortcut: keyword='{engine_keyword}' name='{engine.get('short_name', '')}'")
                break
        if found:
            score += 5
            found_keywords.append(kw)
        else:
            feedback.append(f"Missing search shortcut with keyword: '{kw}'")

    feedback.insert(0, f"Found {len(found_keywords)}/3 educational search shortcuts")

    logger.info(f"Criterion 4 - Search shortcuts: {len(found_keywords)}/3, score={score}")
    return score, feedback


def _extract_search_engines(prefs_data: Dict) -> List[Dict]:
    """
    Extract search engine entries from Chrome Preferences.
    Searches multiple known locations in the Preferences JSON structure.
    """
    engines = []

    # Location 1: default_search_provider_data.template_url_data (single or list)
    dsp = prefs_data.get('default_search_provider_data', {})
    template = dsp.get('template_url_data', {})
    if isinstance(template, dict) and template:
        engines.append(template)
    elif isinstance(template, list):
        engines.extend(template)

    # Location 2: search_provider_overrides (list of engines)
    overrides = prefs_data.get('search_provider_overrides', [])
    if isinstance(overrides, list):
        engines.extend(overrides)

    # Location 3: custom_search_engines or similar
    # Some Chrome versions store additional engines here
    custom = prefs_data.get('custom_search_engines', [])
    if isinstance(custom, list):
        engines.extend(custom)

    # Location 4: Nested under default_search_provider_data as a list
    prepopulated = dsp.get('prepopulated_engines', [])
    if isinstance(prepopulated, list):
        engines.extend(prepopulated)

    # Location 5: keywords section
    keywords_cache = prefs_data.get('keywords', {})
    if isinstance(keywords_cache, dict):
        for key, val in keywords_cache.items():
            if isinstance(val, dict):
                engines.append(val)

    # Location 6: Search engines stored via Omnibox
    omni = prefs_data.get('omnibox', {})
    if isinstance(omni, dict):
        recent = omni.get('recent_search_engines', [])
        if isinstance(recent, list):
            engines.extend(recent)

    return engines


# ============================================================
# Criterion 5: Homepage and startup pages (15 pts)
# ============================================================

def _check_homepage_startup(prefs_data: Optional[Dict]):
    """
    Homepage contains 'classroom.google.com' (5 pts).
    Startup pages include classroom.google.com (5 pts) and khanacademy.org (5 pts).
    """
    feedback = []
    score = 0

    if not prefs_data:
        return 0, ["Could not access Preferences file"]

    # Check homepage
    homepage = prefs_data.get('homepage', '')
    if 'classroom.google.com' in homepage.lower():
        score += 5
        feedback.append(f"Homepage set to: {homepage} - PASS")
    else:
        feedback.append(f"Homepage: '{homepage}' (expected classroom.google.com)")

    # Check startup pages
    # restore_on_startup: 4 means open specific URLs
    session = prefs_data.get('session', {})
    startup_urls = session.get('startup_urls', [])
    restore_mode = session.get('restore_on_startup', 0)

    # Also check alternate locations
    if not startup_urls:
        startup_urls = prefs_data.get('startup_urls', [])

    startup_urls_lower = [url.lower() for url in startup_urls]
    feedback.append(f"Startup URLs configured: {startup_urls}")
    feedback.append(f"Restore on startup mode: {restore_mode}")

    if any('classroom.google.com' in url for url in startup_urls_lower):
        score += 5
        feedback.append("Startup includes classroom.google.com - PASS")
    else:
        feedback.append("Startup missing classroom.google.com")

    if any('khanacademy.org' in url for url in startup_urls_lower):
        score += 5
        feedback.append("Startup includes khanacademy.org - PASS")
    else:
        feedback.append("Startup missing khanacademy.org")

    logger.info(f"Criterion 5 - Homepage/startup: score={score}")
    return score, feedback


# ============================================================
# Criterion 6: Content safety settings (15 pts)
# ============================================================

def _check_content_safety(prefs_data: Optional[Dict]):
    """
    Third-party cookies blocked (5 pts).
    Default notification blocking (5 pts).
    Safe browsing enhanced mode (5 pts).
    """
    feedback = []
    score = 0

    if not prefs_data:
        return 0, ["Could not access Preferences file"]

    # Check third-party cookies (cookie_controls_mode: 1 = block third-party)
    profile = prefs_data.get('profile', {})
    cookie_mode = profile.get('cookie_controls_mode', 0)

    # Also check alternate location
    if cookie_mode == 0:
        cookie_mode = prefs_data.get('cookie_controls_mode', 0)

    if cookie_mode == 1:
        score += 5
        feedback.append(f"Third-party cookies blocked (mode={cookie_mode}) - PASS")
    else:
        feedback.append(f"Third-party cookies not blocked (mode={cookie_mode}, expected 1)")

    # Check notification blocking
    # default_content_setting_values.notifications: 2 = block
    content_settings = profile.get('default_content_setting_values', {})
    notif_setting = content_settings.get('notifications', 1)

    # Also check alternate location
    if notif_setting == 1:
        alt_content = prefs_data.get('profile', {}).get('content_settings', {})
        alt_defaults = alt_content.get('exceptions', {}).get('notifications', {})
        # If no alternate, stick with original
        pass

    if notif_setting == 2:
        score += 5
        feedback.append(f"Notifications blocked by default (setting={notif_setting}) - PASS")
    else:
        feedback.append(f"Notifications not blocked (setting={notif_setting}, expected 2)")

    # Check safe browsing enhanced
    safebrowsing = prefs_data.get('safebrowsing', {})
    sb_enhanced = safebrowsing.get('enhanced', False)

    if sb_enhanced is True:
        score += 5
        feedback.append("Safe Browsing enhanced mode enabled - PASS")
    else:
        feedback.append(f"Safe Browsing enhanced mode not enabled (enhanced={sb_enhanced})")

    logger.info(f"Criterion 6 - Content safety: score={score}")
    return score, feedback


# ============================================================
# Criterion 7: Download and authentication settings (15 pts)
# ============================================================

def _check_download_auth_settings(prefs_data: Optional[Dict]):
    """
    Download path contains 'Student_Resources' (5 pts).
    prompt_for_download true (3 pts).
    Password saving disabled (4 pts).
    Autofill disabled (3 pts).
    """
    feedback = []
    score = 0

    if not prefs_data:
        return 0, ["Could not access Preferences file"]

    # Check download directory
    download = prefs_data.get('download', {})
    dl_path = download.get('default_directory', '')

    if 'student_resources' in dl_path.lower():
        score += 5
        feedback.append(f"Download directory: {dl_path} - PASS")
    else:
        feedback.append(f"Download directory: '{dl_path}' (expected path containing 'Student_Resources')")

    # Check prompt_for_download
    prompt = download.get('prompt_for_download', False)
    if prompt is True:
        score += 3
        feedback.append("Prompt for download: enabled - PASS")
    else:
        feedback.append(f"Prompt for download: {prompt} (expected true)")

    # Check password saving disabled
    # Can be under credentials_enable_service or profile.password_manager_enabled
    pw_enabled = prefs_data.get('credentials_enable_service', True)
    pw_manager = prefs_data.get('profile', {}).get('password_manager_enabled', True)

    if pw_enabled is False or pw_manager is False:
        score += 4
        feedback.append(f"Password saving disabled (credentials={pw_enabled}, manager={pw_manager}) - PASS")
    else:
        feedback.append(f"Password saving still enabled (credentials={pw_enabled}, manager={pw_manager})")

    # Check autofill disabled
    autofill = prefs_data.get('autofill', {})
    profile_enabled = autofill.get('profile_enabled', True)
    cc_enabled = autofill.get('credit_card_enabled', True)

    if profile_enabled is False or cc_enabled is False:
        score += 3
        feedback.append(f"Autofill disabled (profile={profile_enabled}, credit_card={cc_enabled}) - PASS")
    else:
        feedback.append(f"Autofill still enabled (profile={profile_enabled}, credit_card={cc_enabled})")

    logger.info(f"Criterion 7 - Download/auth: score={score}")
    return score, feedback
