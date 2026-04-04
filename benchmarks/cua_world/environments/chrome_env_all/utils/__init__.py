"""
Chrome verification utilities for gym-anything
"""

from .chrome_verification_utils import *

__all__ = [
    'get_chrome_profile_path',
    'copy_chrome_file',
    'get_active_tab_info_from_cdp',
    'parse_bookmarks',
    'get_bookmark_bar_folders',
    'get_bookmark_bar_urls',
    'get_folder_bookmarks',
    'parse_history',
    'parse_cookies',
    'parse_preferences',
    'get_font_size',
    'get_installed_extensions',
    'check_history_contains_keyword',
    'check_cookie_for_domain',
    'cleanup_verification_temp',
    'setup_chrome_verification',
    'verify_url_pattern',
    'verify_bookmarks_folders',
    'verify_bookmarks_urls',
]

