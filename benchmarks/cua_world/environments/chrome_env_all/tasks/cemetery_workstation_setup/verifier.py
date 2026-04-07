#!/usr/bin/env python3
"""
Verifier for cemetery_workstation_setup@1

Verification Criteria (100 pts total):
1. Bookmark Organization: Folders 'Vital Records & Archives' and 'Grounds & Vendors' exist, containing appropriate domains (20 pts)
2. Bookmark Sanitization: 0 personal domains anywhere in Bookmarks (15 pts)
3. History Sanitization: 0 personal domain entries in History, >= 30 work entries remaining (20 pts)
4. PDF Download Setting: plugins.always_open_pdf_externally == True (15 pts)
5. Download Directory: Contains 'Burial_Records' and prompt_for_download == True (10 pts)
6. Custom Search Engines: Keywords 'grave' and 'ssdi' configured (10 pts)
7. Startup Pages: session.restore_on_startup == 4, urls match findagrave and familysearch (10 pts)

Pass Threshold: 75 points. History and PDF settings strictly met.
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

def _copy_file_from_container(copy_from_env, container_path: str, suffix: str) -> str:
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_file.close()
    try:
        copy_from_env(container_path, temp_file.name)
        if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
            return temp_file.name
    except Exception as e:
        logger.error(f"Failed to copy {container_path}: {e}")
    
    if os.path.exists(temp_file.name):
        os.unlink(temp_file.name)
    return None

def _extract_all_urls(bookmark_node: dict) -> list:
    urls = []
    if bookmark_node.get('type') == 'url':
        urls.append(bookmark_node.get('url', ''))
    for child in bookmark_node.get('children', []):
        urls.extend(_extract_all_urls(child))
    return urls

def _find_folder(children: list, keywords: list) -> dict:
    for child in children:
        if child.get('type') == 'folder':
            name_lower = child.get('name', '').lower()
            if all(kw.lower() in name_lower for kw in keywords):
                return child
    return None

def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    vital_domains = metadata.get("vital_domains", [])
    grounds_domains = metadata.get("grounds_domains", [])
    personal_domains = metadata.get("personal_domains", [])

    score = 0
    feedback = []

    # 1. Fetch files
    bookmarks_path = _copy_file_from_container(copy_from_env, "/tmp/cemetery_export/Bookmarks", ".json")
    prefs_path = _copy_file_from_container(copy_from_env, "/tmp/cemetery_export/Preferences", ".json")
    history_path = _copy_file_from_container(copy_from_env, "/tmp/cemetery_export/History", ".sqlite")
    webdata_path = _copy_file_from_container(copy_from_env, "/tmp/cemetery_export/Web Data", ".sqlite")

    if not bookmarks_path or not prefs_path or not history_path:
        return {"passed": False, "score": 0, "feedback": "Failed to extract required Chrome profile files from the environment."}

    try:
        with open(bookmarks_path, 'r', encoding='utf-8') as f:
            bookmarks = json.load(f)
        with open(prefs_path, 'r', encoding='utf-8') as f:
            prefs = json.load(f)

        # -------------------------------------------------------------
        # Criterion 1: Bookmark Organization (20 pts)
        # -------------------------------------------------------------
        c1_score = 0
        bbar_children = bookmarks.get("roots", {}).get("bookmark_bar", {}).get("children", [])
        
        vital_folder = _find_folder(bbar_children, ["vital", "archives"])
        grounds_folder = _find_folder(bbar_children, ["grounds", "vendors"])

        if vital_folder and grounds_folder:
            c1_score += 10
            vital_urls = _extract_all_urls(vital_folder)
            grounds_urls = _extract_all_urls(grounds_folder)
            
            vital_matches = sum(1 for d in vital_domains if any(d in u.lower() for u in vital_urls))
            grounds_matches = sum(1 for d in grounds_domains if any(d in u.lower() for u in grounds_urls))
            
            if vital_matches >= 6 and grounds_matches >= 4:
                c1_score += 10
                feedback.append("✅ Bookmark Organization: Folders exist with properly categorized links.")
            else:
                c1_score += 5
                feedback.append(f"⚠️ Bookmark Organization: Folders found, but missing domains (Vital: {vital_matches}/12, Grounds: {grounds_matches}/8).")
        else:
            feedback.append("❌ Bookmark Organization: Required folders ('Vital Records & Archives' and 'Grounds & Vendors') not found.")
        score += c1_score

        # -------------------------------------------------------------
        # Criterion 2: Bookmark Sanitization (15 pts)
        # -------------------------------------------------------------
        c2_score = 0
        all_bookmark_urls = []
        for root in bookmarks.get("roots", {}).values():
            if isinstance(root, dict):
                all_bookmark_urls.extend(_extract_all_urls(root))
                
        personal_bm_found = sum(1 for d in personal_domains if any(d in u.lower() for u in all_bookmark_urls))
        if personal_bm_found == 0:
            c2_score = 15
            feedback.append("✅ Bookmark Sanitization: All personal bookmarks successfully deleted.")
        else:
            feedback.append(f"❌ Bookmark Sanitization: {personal_bm_found} personal domain bookmarks still exist.")
        score += c2_score

        # -------------------------------------------------------------
        # Criterion 3: History Sanitization (20 pts)
        # -------------------------------------------------------------
        c3_score = 0
        conn = sqlite3.connect(history_path)
        c = conn.cursor()
        c.execute("SELECT url FROM urls")
        history_urls = [row[0].lower() for row in c.fetchall()]
        conn.close()

        personal_history_count = sum(1 for d in personal_domains if any(d in u for u in history_urls))
        work_history_count = sum(1 for d in vital_domains + grounds_domains if any(d in u for u in history_urls))

        history_strictly_passed = False
        if personal_history_count == 0 and work_history_count >= 20:
            c3_score = 20
            history_strictly_passed = True
            feedback.append(f"✅ History Sanitization: Personal history purged, {work_history_count} work entries safely preserved.")
        elif personal_history_count == 0:
            c3_score = 5
            feedback.append("⚠️ History Sanitization: Personal history purged, but work history was also cleared (mass deletion detected).")
        else:
            feedback.append(f"❌ History Sanitization: {personal_history_count} personal history entries remain.")
        score += c3_score

        # -------------------------------------------------------------
        # Criterion 4: PDF Download Setting (15 pts)
        # -------------------------------------------------------------
        c4_score = 0
        pdf_externally = prefs.get("plugins", {}).get("always_open_pdf_externally", False)
        pdf_strictly_passed = False
        if pdf_externally is True:
            c4_score = 15
            pdf_strictly_passed = True
            feedback.append("✅ PDF Setting: PDFs configured to download externally.")
        else:
            feedback.append("❌ PDF Setting: 'Always open pdf externally' is not enabled.")
        score += c4_score

        # -------------------------------------------------------------
        # Criterion 5: Download Directory (10 pts)
        # -------------------------------------------------------------
        c5_score = 0
        dl_dir = prefs.get("download", {}).get("default_directory", "").lower()
        dl_prompt = prefs.get("download", {}).get("prompt_for_download", False)
        
        if "burial_records" in dl_dir:
            c5_score += 5
        if dl_prompt is True:
            c5_score += 5
            
        if c5_score == 10:
            feedback.append("✅ Download Configuration: Directory correct and prompt enabled.")
        else:
            feedback.append(f"⚠️ Download Configuration: Partial ({c5_score}/10). Dir='{dl_dir}', Prompt={dl_prompt}")
        score += c5_score

        # -------------------------------------------------------------
        # Criterion 6: Custom Search Engines (10 pts)
        # -------------------------------------------------------------
        c6_score = 0
        grave_found = False
        ssdi_found = False

        # Check in Web Data sqlite (primary location for modern Chrome)
        if webdata_path and os.path.exists(webdata_path):
            try:
                conn_wd = sqlite3.connect(webdata_path)
                c_wd = conn_wd.cursor()
                c_wd.execute("SELECT keyword, url FROM keywords")
                for kw, url in c_wd.fetchall():
                    if kw.lower() == "grave" and "findagrave.com" in url.lower():
                        grave_found = True
                    if kw.lower() == "ssdi" and "genealogybank.com" in url.lower():
                        ssdi_found = True
                conn_wd.close()
            except Exception as e:
                logger.error(f"Error reading Web Data DB: {e}")

        # Fallback to checking preferences (custom_search_providers)
        if not grave_found or not ssdi_found:
            search_engines = prefs.get("default_search_provider_data", {}).get("template_url_data", {})
            # It's difficult to parse all overriding structures in standard preferences, so we rely mainly on DB.
            custom_providers = prefs.get("profile", {}).get("custom_search_providers", []) # older chrome fallback
            for sp in custom_providers:
                kw = sp.get("keyword", "").lower()
                url = sp.get("url", "").lower()
                if kw == "grave" and "findagrave.com" in url:
                    grave_found = True
                if kw == "ssdi" and "genealogybank.com" in url:
                    ssdi_found = True

        if grave_found: c6_score += 5
        if ssdi_found: c6_score += 5

        if c6_score == 10:
            feedback.append("✅ Custom Search Engines: 'grave' and 'ssdi' configured.")
        else:
            feedback.append(f"⚠️ Custom Search Engines: Partial match ({c6_score}/10 pts). grave={grave_found}, ssdi={ssdi_found}.")
        score += c6_score

        # -------------------------------------------------------------
        # Criterion 7: Startup Pages (10 pts)
        # -------------------------------------------------------------
        c7_score = 0
        restore_on_startup = prefs.get("session", {}).get("restore_on_startup", 0)
        startup_urls = prefs.get("session", {}).get("startup_urls", [])
        
        if restore_on_startup == 4:
            c7_score += 5
            urls_str = " ".join(startup_urls).lower()
            if "findagrave.com" in urls_str and "familysearch.org" in urls_str:
                c7_score += 5
                feedback.append("✅ Startup Pages: Configured to open specific genealogy URLs.")
            else:
                feedback.append("⚠️ Startup Pages: Configured to open URLs, but wrong URLs found.")
        else:
            feedback.append("❌ Startup Pages: Not configured to open specific URLs on startup.")
        score += c7_score

        # -------------------------------------------------------------
        # Final Evaluation
        # -------------------------------------------------------------
        # Pass requires >= 75 points AND strict passing of history and pdf checks
        passed = (score >= 75) and history_strictly_passed and pdf_strictly_passed

        if passed:
            feedback.insert(0, f"🎉 SUCCESS! Total Score: {score}/100")
        else:
            feedback.insert(0, f"🛑 TASK FAILED! Total Score: {score}/100. (Requires >=75, strict history, strict PDF settings).")

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    finally:
        # Cleanup
        for p in [bookmarks_path, prefs_path, history_path, webdata_path]:
            if p and os.path.exists(p):
                try:
                    os.unlink(p)
                except Exception:
                    pass