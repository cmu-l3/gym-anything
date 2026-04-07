#!/usr/bin/env python3
"""
Verifier for compliance_research_workspace@1

Task: A regulatory affairs manager implements a Browser Configuration Standard
      that covers bookmark organization, search engine shortcuts, homepage/startup,
      privacy settings, download preferences, and autofill/password settings.

Verification Strategy:
  - Copy Bookmarks and Preferences files from the container
  - Check 7 criteria across all configuration areas
  - Award partial credit per criterion
  - Pass threshold: 70/100 points

Criteria (100 points total):
  1. Bookmark hierarchy created (20 pts)
  2. Bookmark sub-folders for Federal Agencies (10 pts)
  3. Custom search engines configured (15 pts)
  4. Homepage and startup pages (15 pts)
  5. Privacy settings configured (15 pts)
  6. Download directory configured (10 pts)
  7. Autofill/password disabled (15 pts)
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


# ---------------------------------------------------------------------------
# Helper: copy a file from the container, trying multiple paths
# ---------------------------------------------------------------------------

def _copy_file(copy_from_env, container_paths: List[str], suffix: str = '.json') -> Optional[str]:
    """
    Try to copy a file from the container using multiple candidate paths.
    Returns the local temp path on success, or None on failure.
    The caller is responsible for deleting the temp file.
    """
    temp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp.name
    temp.close()

    for cpath in container_paths:
        try:
            logger.info(f"Trying to copy from: {cpath}")
            copy_from_env(cpath, temp_path)
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                logger.info(f"Successfully copied from: {cpath}")
                return temp_path
        except Exception as e:
            logger.debug(f"Failed to copy from {cpath}: {e}")
            continue

    # All attempts failed
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    return None


# ---------------------------------------------------------------------------
# Helper: recursively collect all bookmark nodes from a subtree
# ---------------------------------------------------------------------------

def _collect_bookmarks_recursive(node: Dict, collected: Optional[List] = None) -> List[Dict]:
    """Walk the bookmark tree and collect every url-type node."""
    if collected is None:
        collected = []
    if isinstance(node, dict):
        if node.get('type') == 'url':
            collected.append(node)
        for child in node.get('children', []):
            _collect_bookmarks_recursive(child, collected)
    return collected


def _find_folder_case_insensitive(children: List[Dict], name: str) -> Optional[Dict]:
    """Find a folder among children by case-insensitive name match."""
    name_lower = name.lower()
    for child in children:
        if child.get('type') == 'folder' and child.get('name', '').lower() == name_lower:
            return child
    return None


# ---------------------------------------------------------------------------
# Main verify_task entry point
# ---------------------------------------------------------------------------

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for compliance_research_workspace@1.

    Returns dict with keys: passed, score, feedback, details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }

    try:
        # ----- Copy Bookmarks -----
        bookmarks_paths = [
            "/home/ga/.config/google-chrome/Default/Bookmarks",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/tmp/bookmarks_export.json"
        ]
        bookmarks_local = _copy_file(copy_from_env, bookmarks_paths, suffix='.json')
        bookmarks_data = None
        if bookmarks_local:
            try:
                bookmarks_data = parse_bookmarks(bookmarks_local)
            except Exception as e:
                logger.error(f"Error parsing bookmarks: {e}")
            finally:
                os.unlink(bookmarks_local)

        # ----- Copy Preferences -----
        prefs_paths = [
            "/home/ga/.config/google-chrome/Default/Preferences",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/tmp/chrome_preferences.json"
        ]
        prefs_local = _copy_file(copy_from_env, prefs_paths, suffix='.json')
        prefs_data = None
        if prefs_local:
            try:
                prefs_data = parse_preferences(prefs_local)
            except Exception as e:
                logger.error(f"Error parsing preferences: {e}")
            finally:
                os.unlink(prefs_local)

        # ----- Run criteria checks -----
        scores = {}
        feedback_parts = []

        feedback_parts.append("=" * 60)
        feedback_parts.append("BROWSER CONFIGURATION STANDARD COMPLIANCE VERIFICATION")
        feedback_parts.append("=" * 60)

        # Criterion 1: Bookmark hierarchy (20 pts)
        s1, fb1 = _check_bookmark_hierarchy(bookmarks_data)
        scores["bookmark_hierarchy"] = s1
        feedback_parts.append(f"\n1. BOOKMARK HIERARCHY ({s1}/20 pts)")
        feedback_parts.extend(fb1)

        # Criterion 2: Federal Agencies sub-folders (10 pts)
        s2, fb2 = _check_federal_subfolders(bookmarks_data)
        scores["federal_subfolders"] = s2
        feedback_parts.append(f"\n2. FEDERAL AGENCIES SUB-FOLDERS ({s2}/10 pts)")
        feedback_parts.extend(fb2)

        # Criterion 3: Custom search engines (15 pts)
        s3, fb3 = _check_search_engines(prefs_data)
        scores["search_engines"] = s3
        feedback_parts.append(f"\n3. CUSTOM SEARCH ENGINES ({s3}/15 pts)")
        feedback_parts.extend(fb3)

        # Criterion 4: Homepage and startup pages (15 pts)
        s4, fb4 = _check_homepage_startup(prefs_data)
        scores["homepage_startup"] = s4
        feedback_parts.append(f"\n4. HOMEPAGE AND STARTUP ({s4}/15 pts)")
        feedback_parts.extend(fb4)

        # Criterion 5: Privacy settings (15 pts)
        s5, fb5 = _check_privacy_settings(prefs_data)
        scores["privacy"] = s5
        feedback_parts.append(f"\n5. PRIVACY AND SECURITY ({s5}/15 pts)")
        feedback_parts.extend(fb5)

        # Criterion 6: Download directory (10 pts)
        s6, fb6 = _check_download_settings(prefs_data)
        scores["download"] = s6
        feedback_parts.append(f"\n6. DOWNLOAD PREFERENCES ({s6}/10 pts)")
        feedback_parts.extend(fb6)

        # Criterion 7: Autofill/password disabled (15 pts)
        s7, fb7 = _check_autofill_password(prefs_data)
        scores["autofill_password"] = s7
        feedback_parts.append(f"\n7. AUTOFILL AND PASSWORDS ({s7}/15 pts)")
        feedback_parts.extend(fb7)

        # ----- Final score -----
        total_score = sum(scores.values())
        passed = total_score >= 70

        feedback_parts.append("\n" + "=" * 60)
        feedback_parts.append(f"TOTAL SCORE: {total_score}/100")
        if passed:
            if total_score >= 95:
                feedback_parts.append("RESULT: EXCELLENT - Full compliance achieved!")
            elif total_score >= 85:
                feedback_parts.append("RESULT: PASSED - Strong compliance with minor gaps")
            else:
                feedback_parts.append("RESULT: PASSED - Met minimum compliance threshold")
        else:
            feedback_parts.append("RESULT: FAILED - Does not meet minimum compliance threshold (70)")
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


# ===================================================================
# Criterion 1: Bookmark hierarchy created (20 pts)
# Check for at least 4 of the 5 required top-level folders
# ===================================================================

def _check_bookmark_hierarchy(bookmarks_data: Optional[Dict]) -> tuple:
    feedback = []
    if not bookmarks_data:
        feedback.append("   Could not access bookmarks file")
        return 0, feedback

    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])

    required_folders = [
        "Federal Agencies",
        "Standards Bodies",
        "International",
        "Legislative Resources",
        "Consumer Protection"
    ]

    found_folders = []
    for req in required_folders:
        folder = _find_folder_case_insensitive(children, req)
        if folder is not None:
            found_folders.append(req)
            feedback.append(f"   Found folder: {folder.get('name')}")
        else:
            feedback.append(f"   MISSING folder: {req}")

    count = len(found_folders)
    if count >= 4:
        score = 20
    elif count == 3:
        score = 15
    elif count == 2:
        score = 10
    elif count == 1:
        score = 5
    else:
        score = 0

    feedback.append(f"   {count}/5 required folders found (need >= 4 for full credit)")
    return score, feedback


# ===================================================================
# Criterion 2: Federal Agencies sub-folders (10 pts)
# Inside "Federal Agencies" folder, check for FDA, EPA, OSHA, SEC
# sub-folders with relevant bookmarks inside each.
# ===================================================================

def _check_federal_subfolders(bookmarks_data: Optional[Dict]) -> tuple:
    feedback = []
    if not bookmarks_data:
        feedback.append("   Could not access bookmarks file")
        return 0, feedback

    bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
    children = bookmark_bar.get('children', [])

    federal_folder = _find_folder_case_insensitive(children, "Federal Agencies")
    if not federal_folder:
        feedback.append("   'Federal Agencies' folder not found on bookmark bar")
        return 0, feedback

    sub_children = federal_folder.get('children', [])

    # Map sub-folder name -> domain patterns to validate contents
    expected_subs = {
        "FDA": ["fda.gov"],
        "EPA": ["epa.gov"],
        "OSHA": ["osha.gov"],
        "SEC": ["sec.gov"],
    }

    valid_count = 0
    for sub_name, domain_patterns in expected_subs.items():
        sub_folder = _find_folder_case_insensitive(sub_children, sub_name)
        if sub_folder:
            # Check that at least one bookmark inside matches a domain pattern
            inner_bookmarks = _collect_bookmarks_recursive(sub_folder)
            has_match = False
            for bm in inner_bookmarks:
                url = bm.get('url', '').lower()
                if any(dp in url for dp in domain_patterns):
                    has_match = True
                    break
            if has_match:
                valid_count += 1
                feedback.append(f"   Sub-folder '{sub_name}' found with matching bookmarks")
            else:
                feedback.append(f"   Sub-folder '{sub_name}' found but no matching bookmarks inside")
        else:
            feedback.append(f"   MISSING sub-folder: {sub_name}")

    if valid_count >= 3:
        score = 10
    elif valid_count == 2:
        score = 6
    elif valid_count == 1:
        score = 3
    else:
        score = 0

    feedback.append(f"   {valid_count}/4 valid sub-folders (need >= 3 for full credit)")
    return score, feedback


# ===================================================================
# Criterion 3: Custom search engines (15 pts, 5 per engine)
# ===================================================================

def _check_search_engines(prefs_data: Optional[Dict]) -> tuple:
    feedback = []
    if not prefs_data:
        feedback.append("   Could not access Preferences file")
        return 0, feedback

    # Collect all search engine entries from known locations
    all_entries: List[Dict] = []

    # Location 1: search_provider_overrides
    overrides = prefs_data.get('search_provider_overrides', [])
    if isinstance(overrides, list):
        all_entries.extend(overrides)

    # Location 2: default_search_provider_data -> template_url_data
    dsp_data = prefs_data.get('default_search_provider_data', {})
    if isinstance(dsp_data, dict):
        tud = dsp_data.get('template_url_data', [])
        if isinstance(tud, list):
            all_entries.extend(tud)

    # Location 3: profile -> custom_search_providers
    profile = prefs_data.get('profile', {})
    if isinstance(profile, dict):
        csp = profile.get('custom_search_providers', [])
        if isinstance(csp, list):
            all_entries.extend(csp)

    expected_keywords = {"cfr": False, "fr": False, "edgar": False}
    score = 0

    for entry in all_entries:
        if not isinstance(entry, dict):
            continue
        keyword = entry.get('keyword', entry.get('shortcut', '')).lower().strip()
        if keyword in expected_keywords and not expected_keywords[keyword]:
            expected_keywords[keyword] = True
            score += 5
            short_name = entry.get('short_name', entry.get('name', 'unnamed'))
            feedback.append(f"   Found search engine: keyword='{keyword}', name='{short_name}'")

    for kw, found in expected_keywords.items():
        if not found:
            feedback.append(f"   MISSING search engine with keyword: {kw}")

    found_count = sum(expected_keywords.values())
    feedback.append(f"   {found_count}/3 search engines configured")
    return score, feedback


# ===================================================================
# Criterion 4: Homepage and startup pages (15 pts)
# Homepage containing federalregister.gov (5 pts)
# Startup URLs containing the 3 required pages (10 pts, partial)
# ===================================================================

def _check_homepage_startup(prefs_data: Optional[Dict]) -> tuple:
    feedback = []
    if not prefs_data:
        feedback.append("   Could not access Preferences file")
        return 0, feedback

    score = 0

    # --- Homepage check (5 pts) ---
    homepage = prefs_data.get('homepage', '')
    if 'federalregister.gov' in homepage.lower():
        score += 5
        feedback.append(f"   Homepage set correctly: {homepage}")
    else:
        feedback.append(f"   Homepage incorrect: '{homepage}' (expected federalregister.gov)")

    # --- Startup pages check (10 pts, partial credit) ---
    # Chrome stores startup URLs in session.startup_urls
    startup_urls = prefs_data.get('session', {}).get('startup_urls', [])
    if not isinstance(startup_urls, list):
        startup_urls = []

    # Also check restore_on_startup == 4 (open specific pages)
    restore_on_startup = prefs_data.get('session', {}).get('restore_on_startup', 1)

    expected_startup_domains = {
        "federalregister.gov": False,
        "regulations.gov": False,
        "ecfr.gov": False
    }

    for url in startup_urls:
        url_lower = url.lower()
        for domain in expected_startup_domains:
            if domain in url_lower:
                expected_startup_domains[domain] = True

    startup_found = sum(expected_startup_domains.values())
    # Award partial credit: ~3.3 pts per domain found
    startup_score = min(10, int((startup_found / 3.0) * 10))
    score += startup_score

    for domain, found in expected_startup_domains.items():
        status = "found" if found else "MISSING"
        feedback.append(f"   Startup URL {domain}: {status}")

    if restore_on_startup != 4 and startup_found > 0:
        feedback.append(f"   Note: restore_on_startup={restore_on_startup} (expected 4 for specific pages)")

    feedback.append(f"   {startup_found}/3 startup URLs configured")
    return score, feedback


# ===================================================================
# Criterion 5: Privacy settings (15 pts)
# Third-party cookies blocked (5 pts)
# DNT enabled (5 pts)
# Safe Browsing enhanced mode (5 pts)
# ===================================================================

def _check_privacy_settings(prefs_data: Optional[Dict]) -> tuple:
    feedback = []
    if not prefs_data:
        feedback.append("   Could not access Preferences file")
        return 0, feedback

    score = 0

    # --- Third-party cookies blocked (5 pts) ---
    # Check multiple possible locations
    block_3p = prefs_data.get('profile', {}).get('block_third_party_cookies', False)
    # Also check content settings
    cookie_setting = prefs_data.get('profile', {}).get('default_content_setting_values', {}).get('cookies', 1)
    # cookie_setting: 1=allow, 2=block, 4=block third-party
    cookies_blocked = block_3p is True or cookie_setting in (2, 4)

    if cookies_blocked:
        score += 5
        feedback.append("   Third-party cookies: BLOCKED")
    else:
        feedback.append("   Third-party cookies: NOT blocked")

    # --- Do Not Track (5 pts) ---
    dnt = prefs_data.get('enable_do_not_track', False)
    if dnt is True:
        score += 5
        feedback.append("   Do Not Track: ENABLED")
    else:
        feedback.append("   Do Not Track: DISABLED (should be enabled)")

    # --- Safe Browsing enhanced (5 pts) ---
    sb = prefs_data.get('safebrowsing', {})
    sb_enabled = sb.get('enabled', False)
    sb_enhanced = sb.get('enhanced', False)
    if sb_enhanced is True:
        score += 5
        feedback.append("   Safe Browsing enhanced: ENABLED")
    elif sb_enabled:
        feedback.append("   Safe Browsing enabled but NOT enhanced mode")
    else:
        feedback.append("   Safe Browsing: DISABLED")

    return score, feedback


# ===================================================================
# Criterion 6: Download directory configured (10 pts)
# Download path containing "Regulatory_Downloads" (5 pts)
# prompt_for_download is true (5 pts)
# ===================================================================

def _check_download_settings(prefs_data: Optional[Dict]) -> tuple:
    feedback = []
    if not prefs_data:
        feedback.append("   Could not access Preferences file")
        return 0, feedback

    score = 0
    download = prefs_data.get('download', {})

    # --- Download directory (5 pts) ---
    dl_dir = download.get('default_directory', '')
    if 'regulatory_downloads' in dl_dir.lower():
        score += 5
        feedback.append(f"   Download directory: {dl_dir}")
    else:
        feedback.append(f"   Download directory incorrect: '{dl_dir}' (expected Regulatory_Downloads)")

    # --- Prompt for download (5 pts) ---
    prompt = download.get('prompt_for_download', False)
    if prompt is True:
        score += 5
        feedback.append("   Prompt for download location: ENABLED")
    else:
        feedback.append("   Prompt for download location: DISABLED (should be enabled)")

    return score, feedback


# ===================================================================
# Criterion 7: Autofill and password disabled (15 pts)
# password_manager_enabled false (5 pts)
# autofill addresses disabled (5 pts)
# payment methods disabled (5 pts)
# ===================================================================

def _check_autofill_password(prefs_data: Optional[Dict]) -> tuple:
    feedback = []
    if not prefs_data:
        feedback.append("   Could not access Preferences file")
        return 0, feedback

    score = 0

    # --- Password manager disabled (5 pts) ---
    # Check multiple possible locations
    pw_enabled_profile = prefs_data.get('profile', {}).get('password_manager_enabled', True)
    pw_enabled_cred = prefs_data.get('credentials_enable_service', True)
    pw_disabled = (pw_enabled_profile is False) or (pw_enabled_cred is False)

    if pw_disabled:
        score += 5
        feedback.append("   Password saving: DISABLED")
    else:
        feedback.append("   Password saving: ENABLED (should be disabled)")

    # --- Autofill addresses disabled (5 pts) ---
    autofill = prefs_data.get('autofill', {})
    af_profile = autofill.get('profile_enabled', True)
    af_addresses = autofill.get('addresses_enabled', True)
    af_disabled = (af_profile is False) or (af_addresses is False)

    if af_disabled:
        score += 5
        feedback.append("   Autofill addresses: DISABLED")
    else:
        feedback.append("   Autofill addresses: ENABLED (should be disabled)")

    # --- Payment methods disabled (5 pts) ---
    cc_enabled = autofill.get('credit_card_enabled', True)
    payment_enabled = autofill.get('payment_methods_enabled', True)
    payment_disabled = (cc_enabled is False) or (payment_enabled is False)

    if payment_disabled:
        score += 5
        feedback.append("   Payment methods: DISABLED")
    else:
        feedback.append("   Payment methods: ENABLED (should be disabled)")

    return score, feedback
