#!/usr/bin/env python3
"""
Verifier for osw_delete_amazon_cookies task.
Ported from OSWorld task 7b6c7e24-c58a-49fc-a5bb-d57b80e5b4c3.

Checks that all .amazon.com cookies have been deleted from Chrome.
OSWorld metric: is_cookie_deleted (domains)
OSWorld getter: cookie_data (reads Chrome Cookies SQLite DB)
"""

import json
import os
import sqlite3
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def compare_urls(domain1, domain2):
    """Simple domain comparison — checks if one contains the other."""
    d1 = domain1.strip('.').lower()
    d2 = domain2.strip('.').lower()
    return d1 in d2 or d2 in d1


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function available"}

    temp_dir = tempfile.mkdtemp()
    feedback = []

    try:
        # Copy Cookies SQLite DB from Chrome profile
        cookies_path = os.path.join(temp_dir, "Cookies")
        cookies_loaded = False

        candidate_paths = [
            "/home/ga/.config/google-chrome-cdp/Default/Cookies",
            "/home/ga/.config/google-chrome/Default/Cookies",
        ]

        for candidate in candidate_paths:
            try:
                copy_from_env(candidate, cookies_path)
                if os.path.exists(cookies_path) and os.path.getsize(cookies_path) > 0:
                    feedback.append(f"Loaded Cookies from {candidate}")
                    cookies_loaded = True
                    break
            except Exception as e:
                feedback.append(f"Could not load from {candidate}: {e}")
                continue

        if not cookies_loaded:
            # If no Cookies file exists at all, cookies are deleted — PASS
            return {
                "passed": True,
                "score": 100,
                "feedback": "No Cookies file found — all cookies deleted — PASS\n" + "\n".join(feedback)
            }

        # Query the Cookies SQLite DB — mirrors OSWorld cookie_data getter
        conn = sqlite3.connect(cookies_path)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM cookies")
        cookies = cursor.fetchall()
        conn.close()

        # Check for .amazon.com cookies — mirrors OSWorld is_cookie_deleted metric
        # Cookie data format: column index 1 is host_key (domain)
        amazon_domains = [".amazon.com"]
        found_amazon = False

        for cookie in cookies:
            cookie_domain = cookie[1]  # host_key column
            for domain in amazon_domains:
                if compare_urls(domain, cookie_domain):
                    found_amazon = True
                    feedback.append(f"Found Amazon cookie: domain={cookie_domain}")
                    break

        if not found_amazon:
            return {
                "passed": True,
                "score": 100,
                "feedback": f"No .amazon.com cookies found ({len(cookies)} total cookies) — PASS\n" + "\n".join(feedback)
            }
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Amazon cookies still present — FAIL\n" + "\n".join(feedback)
            }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}
    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
