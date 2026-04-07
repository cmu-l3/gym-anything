#!/usr/bin/env python3
"""
Verifier for Developer Workflow Audit Task (developer_workflow_audit@1)

Task: Configure browser per team development workflow standard, including:
- Bookmark organization into Development/Reference/Personal folders with sub-folders
- Custom search engine shortcuts (gh, so, mdn, pypi)
- Homepage and startup configuration
- Cookie/privacy settings
- Download directory configuration

Verification Strategy:
- Copy Bookmarks and Preferences files from container
- Parse JSON and verify 7 criteria across bookmarks and settings
- Award partial credit per criterion
- Total: 100 points, pass threshold: 70
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

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


# Domain classification for bookmark verification
DEV_SOURCE_CONTROL_DOMAINS = ['github.com']
DEV_DOCUMENTATION_DOMAINS = ['docs.python.org', 'developer.mozilla.org', 'kubernetes.io', 'docs.aws.amazon.com']
DEV_PACKAGE_REGISTRY_DOMAINS = ['npmjs.com', 'pypi.org', 'pkg.go.dev', 'crates.io', 'hub.docker.com', 'registry.terraform.io']
DEV_DEVOPS_DOMAINS = ['grafana.com', 'prometheus.io', 'jenkins.io']
DEV_PROJECT_MGMT_DOMAINS = ['jira.atlassian.com', 'confluence.atlassian.com']

REFERENCE_DOMAINS = ['stackoverflow.com']

PERSONAL_DOMAINS = [
    'youtube.com', 'netflix.com', 'spotify.com', 'reddit.com',
    'twitter.com', 'instagram.com', 'amazon.com', 'ebay.com',
    'yelp.com', 'tripadvisor.com', 'espn.com', 'weather.com',
    'craigslist.org', 'pinterest.com', 'tumblr.com', 'twitch.tv'
]

EXPECTED_SEARCH_ENGINES = {
    'gh': 'github.com',
    'so': 'stackoverflow.com',
    'mdn': 'developer.mozilla.org',
    'pypi': 'pypi.org'
}

EXPECTED_DEV_SUBFOLDERS = [
    'Source Control', 'Documentation', 'Package Registries', 'DevOps', 'Project Management'
]


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for developer_workflow_audit@1.

    Checks 7 criteria (100 points total):
    1. Development folder with sub-folders (20 pts)
    2. Reference folder exists (10 pts)
    3. Personal folder with personal bookmarks (15 pts)
    4. Custom search engines (15 pts)
    5. Homepage and startup (15 pts)
    6. Cookie/privacy settings (10 pts)
    7. Download directory (15 pts)

    Pass threshold: score >= 70
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Retrieve Bookmarks and Preferences from container
        bookmarks_data = get_file_from_container(copy_from_env, "Bookmarks")
        prefs_data = get_file_from_container(copy_from_env, "Preferences")

        # Run all 7 verification criteria
        scores = {}
        feedback_parts = []

        feedback_parts.append("=" * 60)
        feedback_parts.append("DEVELOPER WORKFLOW AUDIT VERIFICATION")
        feedback_parts.append("=" * 60)

        # Criterion 1: Development folder with sub-folders (20 pts)
        c1_score, c1_feedback = check_development_folder(bookmarks_data)
        scores['development_folder'] = c1_score
        feedback_parts.append(f"\n[1] Development Folder Structure ({c1_score}/20 pts):")
        feedback_parts.append(f"    {c1_feedback}")

        # Criterion 2: Reference folder (10 pts)
        c2_score, c2_feedback = check_reference_folder(bookmarks_data)
        scores['reference_folder'] = c2_score
        feedback_parts.append(f"\n[2] Reference Folder ({c2_score}/10 pts):")
        feedback_parts.append(f"    {c2_feedback}")

        # Criterion 3: Personal folder (15 pts)
        c3_score, c3_feedback = check_personal_folder(bookmarks_data)
        scores['personal_folder'] = c3_score
        feedback_parts.append(f"\n[3] Personal Folder ({c3_score}/15 pts):")
        feedback_parts.append(f"    {c3_feedback}")

        # Criterion 4: Custom search engines (15 pts)
        c4_score, c4_feedback = check_search_engines(prefs_data)
        scores['search_engines'] = c4_score
        feedback_parts.append(f"\n[4] Custom Search Engines ({c4_score}/15 pts):")
        feedback_parts.append(f"    {c4_feedback}")

        # Criterion 5: Homepage and startup (15 pts)
        c5_score, c5_feedback = check_homepage_startup(prefs_data)
        scores['homepage_startup'] = c5_score
        feedback_parts.append(f"\n[5] Homepage & Startup ({c5_score}/15 pts):")
        feedback_parts.append(f"    {c5_feedback}")

        # Criterion 6: Cookie/privacy settings (10 pts)
        c6_score, c6_feedback = check_cookie_privacy(prefs_data)
        scores['cookie_privacy'] = c6_score
        feedback_parts.append(f"\n[6] Cookie & Privacy ({c6_score}/10 pts):")
        feedback_parts.append(f"    {c6_feedback}")

        # Criterion 7: Download directory (15 pts)
        c7_score, c7_feedback = check_download_config(prefs_data)
        scores['download_config'] = c7_score
        feedback_parts.append(f"\n[7] Download Configuration ({c7_score}/15 pts):")
        feedback_parts.append(f"    {c7_feedback}")

        # Calculate total
        total_score = sum(scores.values())
        passed = total_score >= 70

        feedback_parts.append("\n" + "=" * 60)
        feedback_parts.append(f"TOTAL SCORE: {total_score}/100")
        if passed:
            feedback_parts.append("RESULT: PASSED")
        else:
            feedback_parts.append("RESULT: FAILED (need >= 70)")
        feedback_parts.append("=" * 60)

        feedback = "\n".join(feedback_parts)

        # Cleanup
        cleanup_verification_temp()

        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback,
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


def get_file_from_container(copy_from_env, filename: str) -> Optional[Dict[str, Any]]:
    """
    Copy a Chrome profile file (Bookmarks or Preferences) from container and parse it.

    Tries multiple possible locations for the file.

    Args:
        copy_from_env: Function to copy files from container
        filename: 'Bookmarks' or 'Preferences'

    Returns:
        Parsed JSON dict or None if retrieval failed
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        possible_paths = [
            f"/home/ga/.config/google-chrome-cdp/Default/{filename}",
            f"/home/ga/.config/google-chrome/Default/{filename}",
            f"/home/ga/.config/chromium/Default/{filename}"
        ]

        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy {filename} from: {container_path}")
                copy_from_env(container_path, temp_path)

                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    logger.info(f"Successfully loaded {filename} from: {container_path}")
                    os.unlink(temp_path)
                    return data

            except Exception as e:
                logger.debug(f"Failed to copy {filename} from {container_path}: {e}")
                continue

        # Clean up temp file if all attempts failed
        if os.path.exists(temp_path):
            os.unlink(temp_path)

        logger.warning(f"Could not retrieve {filename} from any known location")
        return None

    except Exception as e:
        logger.error(f"Error getting {filename}: {e}")
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except Exception:
                pass
        return None


def get_all_bookmarks_recursive(node, collected=None) -> List[Dict[str, Any]]:
    """
    Recursively collect all URL bookmarks from a bookmark tree node.

    Args:
        node: A bookmark tree node (dict with 'type', 'children', etc.)
        collected: Accumulator list

    Returns:
        List of bookmark dicts with type='url'
    """
    if collected is None:
        collected = []

    if isinstance(node, dict):
        if node.get('type') == 'url':
            collected.append(node)
        elif node.get('type') == 'folder':
            for child in node.get('children', []):
                get_all_bookmarks_recursive(child, collected)
        elif 'roots' in node:
            for root_name, root_data in node['roots'].items():
                get_all_bookmarks_recursive(root_data, collected)
        elif 'children' in node:
            for child in node['children']:
                get_all_bookmarks_recursive(child, collected)
    elif isinstance(node, list):
        for item in node:
            get_all_bookmarks_recursive(item, collected)

    return collected


def url_matches_domain(url: str, domain: str) -> bool:
    """Check if a URL belongs to the given domain."""
    url_lower = url.lower().replace('http://', '').replace('https://', '').rstrip('/')
    domain_lower = domain.lower()
    # Match exact domain or domain with path
    return url_lower == domain_lower or url_lower.startswith(domain_lower + '/') or url_lower.startswith('www.' + domain_lower)


def find_folder_on_bar(bookmarks_data: Dict, folder_name: str) -> Optional[Dict]:
    """Find a folder by name on the bookmark bar (case-insensitive)."""
    if not bookmarks_data:
        return None
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])
    for child in children:
        if child.get('type') == 'folder' and child.get('name', '').lower() == folder_name.lower():
            return child
    return None


def find_subfolder(folder: Dict, subfolder_name: str) -> Optional[Dict]:
    """Find a sub-folder by name within a folder (case-insensitive)."""
    if not folder:
        return None
    for child in folder.get('children', []):
        if child.get('type') == 'folder' and child.get('name', '').lower() == subfolder_name.lower():
            return child
    return None


def count_matching_bookmarks_in_node(node: Dict, domains: List[str]) -> int:
    """Count how many bookmarks in a node (recursively) match any of the given domains."""
    all_bookmarks = get_all_bookmarks_recursive(node)
    count = 0
    for bookmark in all_bookmarks:
        url = bookmark.get('url', '')
        for domain in domains:
            if url_matches_domain(url, domain):
                count += 1
                break
    return count


# ============================================================
# CRITERION 1: Development folder with sub-folders (20 pts)
# ============================================================
def check_development_folder(bookmarks_data: Optional[Dict]) -> Tuple[int, str]:
    """
    Check for 'Development' folder on bookmark bar with at least 3 of 5 expected
    sub-folders. Also verify that relevant bookmarks are inside the sub-folders.

    Max: 20 points
    - Folder exists: 5 pts
    - Each valid sub-folder with relevant bookmarks: 3 pts each (max 15 pts for 5)
    """
    if not bookmarks_data:
        return 0, "Could not access bookmarks file"

    dev_folder = find_folder_on_bar(bookmarks_data, 'Development')
    if dev_folder is None:
        return 0, "'Development' folder not found on bookmark bar"

    score = 5
    details = ["'Development' folder found"]

    # Check each expected sub-folder
    subfolder_checks = {
        'Source Control': DEV_SOURCE_CONTROL_DOMAINS,
        'Documentation': DEV_DOCUMENTATION_DOMAINS,
        'Package Registries': DEV_PACKAGE_REGISTRY_DOMAINS,
        'DevOps': DEV_DEVOPS_DOMAINS,
        'Project Management': DEV_PROJECT_MGMT_DOMAINS
    }

    subfolders_found = 0
    for subfolder_name, expected_domains in subfolder_checks.items():
        subfolder = find_subfolder(dev_folder, subfolder_name)
        if subfolder is not None:
            matching = count_matching_bookmarks_in_node(subfolder, expected_domains)
            if matching > 0:
                score += 3
                subfolders_found += 1
                details.append(f"  Sub-folder '{subfolder_name}': found with {matching} matching bookmark(s)")
            else:
                details.append(f"  Sub-folder '{subfolder_name}': found but no matching bookmarks inside")
        else:
            details.append(f"  Sub-folder '{subfolder_name}': NOT found")

    # Cap at 20
    score = min(score, 20)
    details.insert(1, f"  {subfolders_found}/5 sub-folders with content found")

    return score, " | ".join(details)


# ============================================================
# CRITERION 2: Reference folder (10 pts)
# ============================================================
def check_reference_folder(bookmarks_data: Optional[Dict]) -> Tuple[int, str]:
    """
    Check for 'Reference' folder on bookmark bar containing Stack Overflow bookmarks.

    Max: 10 points
    - Folder exists: 5 pts
    - Contains Stack Overflow bookmark(s): 5 pts
    """
    if not bookmarks_data:
        return 0, "Could not access bookmarks file"

    ref_folder = find_folder_on_bar(bookmarks_data, 'Reference')
    if ref_folder is None:
        return 0, "'Reference' folder not found on bookmark bar"

    score = 5
    details = ["'Reference' folder found"]

    so_count = count_matching_bookmarks_in_node(ref_folder, REFERENCE_DOMAINS)
    if so_count > 0:
        score += 5
        details.append(f"Contains {so_count} Stack Overflow bookmark(s)")
    else:
        details.append("No Stack Overflow bookmarks found inside")

    return score, " | ".join(details)


# ============================================================
# CRITERION 3: Personal folder with personal bookmarks (15 pts)
# ============================================================
def check_personal_folder(bookmarks_data: Optional[Dict]) -> Tuple[int, str]:
    """
    Check for 'Personal' folder containing at least 12 of 18 personal bookmarks.
    Also verify personal bookmarks are NOT left loose on the bookmark bar.

    Max: 15 points
    - Folder exists: 3 pts
    - Contains >= 12 personal bookmarks: 7 pts (proportional)
    - No personal bookmarks loose on bar: 5 pts
    """
    if not bookmarks_data:
        return 0, "Could not access bookmarks file"

    personal_folder = find_folder_on_bar(bookmarks_data, 'Personal')
    if personal_folder is None:
        return 0, "'Personal' folder not found on bookmark bar"

    score = 3
    details = ["'Personal' folder found"]

    # Count personal bookmarks inside the Personal folder
    personal_in_folder = count_matching_bookmarks_in_node(personal_folder, PERSONAL_DOMAINS)
    details.append(f"{personal_in_folder}/18 personal bookmarks inside folder")

    # Award proportional points for bookmarks in folder (up to 7 pts)
    if personal_in_folder >= 12:
        score += 7
    elif personal_in_folder >= 6:
        score += int(7 * personal_in_folder / 12)
    elif personal_in_folder > 0:
        score += int(7 * personal_in_folder / 12)

    # Check that personal bookmarks are NOT left loose on the bookmark bar
    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    loose_personal = 0
    for child in bookmark_bar.get('children', []):
        if child.get('type') == 'url':
            url = child.get('url', '')
            for domain in PERSONAL_DOMAINS:
                if url_matches_domain(url, domain):
                    loose_personal += 1
                    break

    if loose_personal == 0:
        score += 5
        details.append("No personal bookmarks left loose on bar")
    else:
        details.append(f"{loose_personal} personal bookmark(s) still loose on bar")

    return min(score, 15), " | ".join(details)


# ============================================================
# CRITERION 4: Custom search engines (15 pts)
# ============================================================
def check_search_engines(prefs_data: Optional[Dict]) -> Tuple[int, str]:
    """
    Check Preferences for custom search engines with keywords 'gh', 'so', 'mdn', 'pypi'.

    Max: 15 points
    - ~3 pts per engine found (floor), up to 15 for all 4
    """
    if not prefs_data:
        return 0, "Could not access Preferences file"

    # Search engines can be stored in multiple places in Chrome Preferences
    # Common locations: 'search_provider_overrides', 'default_search_provider_data',
    # or within a list structure
    found_keywords = set()
    details = []

    # Strategy 1: Check in default_search_provider_data template_url_data
    search_engines_list = []

    # Look in several known locations where Chrome stores custom search engines
    # Location: preferences -> search_provider_overrides (list)
    overrides = prefs_data.get('search_provider_overrides', [])
    if isinstance(overrides, list):
        search_engines_list.extend(overrides)

    # Location: preferences -> default_search_provider -> list_of_search_engines
    dsp = prefs_data.get('default_search_provider', {})
    if isinstance(dsp, dict):
        engines = dsp.get('list', [])
        if isinstance(engines, list):
            search_engines_list.extend(engines)

    # Location: preferences -> search_engines (sometimes used by modern Chrome)
    se = prefs_data.get('search_engines', [])
    if isinstance(se, list):
        search_engines_list.extend(se)

    # Location: Look anywhere in the prefs dict for keyword matches
    prefs_str = json.dumps(prefs_data).lower()

    for keyword, expected_domain in EXPECTED_SEARCH_ENGINES.items():
        # Check structured data first
        for engine in search_engines_list:
            if isinstance(engine, dict):
                eng_keyword = str(engine.get('keyword', '')).lower()
                eng_short_name = str(engine.get('short_name', '')).lower()
                eng_url = str(engine.get('url', '')).lower()
                if eng_keyword == keyword or (expected_domain in eng_url and eng_keyword):
                    found_keywords.add(keyword)
                    break

        # Fallback: check if keyword appears in the raw prefs JSON in a search context
        if keyword not in found_keywords:
            # Look for the keyword as a search engine keyword value
            keyword_pattern = f'"keyword":"{keyword}"'
            keyword_pattern_spaced = f'"keyword": "{keyword}"'
            if keyword_pattern in prefs_str or keyword_pattern_spaced in prefs_str:
                found_keywords.add(keyword)

    num_found = len(found_keywords)
    # Award ~3 pts per engine found, but distribute 15 pts across 4 engines
    # 3 pts each for first 3, 6 pts for last = actually, simpler: floor(15 * found / 4)
    score = (num_found * 15) // 4  # 0, 3, 7, 11, 15

    # Adjust so 4 found = 15
    if num_found == 4:
        score = 15
    elif num_found == 3:
        score = 11
    elif num_found == 2:
        score = 7
    elif num_found == 1:
        score = 3

    for kw in EXPECTED_SEARCH_ENGINES:
        status = "found" if kw in found_keywords else "NOT found"
        details.append(f"'{kw}': {status}")

    return score, f"{num_found}/4 search engines configured | " + " | ".join(details)


# ============================================================
# CRITERION 5: Homepage and startup (15 pts)
# ============================================================
def check_homepage_startup(prefs_data: Optional[Dict]) -> Tuple[int, str]:
    """
    Check homepage contains 'github.com' (8 pts) and startup set to restore
    previous session (restore_on_startup = 1) (7 pts).

    Max: 15 points
    """
    if not prefs_data:
        return 0, "Could not access Preferences file"

    score = 0
    details = []

    # Check homepage
    homepage = prefs_data.get('homepage', '')
    if 'github.com' in homepage.lower():
        score += 8
        details.append(f"Homepage set to '{homepage}' (contains github.com)")
    else:
        details.append(f"Homepage is '{homepage}' (expected github.com)")

    # Check restore_on_startup
    # Can be under 'session.restore_on_startup' or 'restore_on_startup'
    restore_val = None
    session = prefs_data.get('session', {})
    if isinstance(session, dict):
        restore_val = session.get('restore_on_startup')
    if restore_val is None:
        restore_val = prefs_data.get('restore_on_startup')

    if restore_val == 1:
        score += 7
        details.append("Startup: restore previous session (1)")
    else:
        details.append(f"Startup restore_on_startup = {restore_val} (expected 1)")

    return score, " | ".join(details)


# ============================================================
# CRITERION 6: Cookie/privacy settings (10 pts)
# ============================================================
def check_cookie_privacy(prefs_data: Optional[Dict]) -> Tuple[int, str]:
    """
    Check third-party cookies blocked (5 pts) and DNT enabled (5 pts).

    Max: 10 points
    """
    if not prefs_data:
        return 0, "Could not access Preferences file"

    score = 0
    details = []

    # Check third-party cookie blocking
    # cookie_controls_mode: 0=allow all, 1=block third-party, 2=block in incognito
    cookie_mode = None
    profile = prefs_data.get('profile', {})
    if isinstance(profile, dict):
        cookie_mode = profile.get('cookie_controls_mode')
    if cookie_mode is None:
        cookie_mode = prefs_data.get('cookie_controls_mode')

    # Also check default_content_setting_values.cookies
    # In some Chrome versions, blocking third-party cookies can be reflected differently
    content_settings = {}
    if isinstance(profile, dict):
        content_settings = profile.get('default_content_setting_values', {})

    if cookie_mode == 1:
        score += 5
        details.append("Third-party cookies: BLOCKED")
    else:
        # Also accept if cookies content setting indicates blocking (value 2 = block)
        cookie_content = content_settings.get('cookies')
        if cookie_content == 2:
            score += 5
            details.append("Third-party cookies: BLOCKED (via content settings)")
        else:
            details.append(f"Third-party cookies: NOT blocked (cookie_controls_mode={cookie_mode})")

    # Check Do Not Track
    dnt = prefs_data.get('enable_do_not_track')
    if dnt is True:
        score += 5
        details.append("Do Not Track: ENABLED")
    else:
        details.append(f"Do Not Track: DISABLED (enable_do_not_track={dnt})")

    return score, " | ".join(details)


# ============================================================
# CRITERION 7: Download directory (15 pts)
# ============================================================
def check_download_config(prefs_data: Optional[Dict]) -> Tuple[int, str]:
    """
    Check download path contains 'projects/downloads' (8 pts) and
    prompt_for_download is true (7 pts).

    Max: 15 points
    """
    if not prefs_data:
        return 0, "Could not access Preferences file"

    score = 0
    details = []

    download = prefs_data.get('download', {})
    if not isinstance(download, dict):
        download = {}

    # Check download directory
    download_dir = download.get('default_directory', '')
    if 'projects/downloads' in download_dir:
        score += 8
        details.append(f"Download dir: '{download_dir}' (contains projects/downloads)")
    else:
        details.append(f"Download dir: '{download_dir}' (expected path with projects/downloads)")

    # Check prompt_for_download
    prompt = download.get('prompt_for_download')
    if prompt is True:
        score += 7
        details.append("Prompt for download: ENABLED")
    else:
        details.append(f"Prompt for download: {prompt} (expected true)")

    return score, " | ".join(details)
