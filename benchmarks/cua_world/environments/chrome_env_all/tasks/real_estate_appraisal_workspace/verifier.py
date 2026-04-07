#!/usr/bin/env python3
import json
import sqlite3
import tempfile
import os
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_folders = metadata.get('expected_folders', [])
    prof_domains = metadata.get('professional_domains', [])
    pers_domains = metadata.get('personal_domains', [])
    expected_se = metadata.get('expected_search_engines', {})
    expected_dl_dir = metadata.get('expected_download_dir', 'Property_Appraisals')

    score = 0
    feedback_parts = []
    
    # Create temp directory for copied files
    temp_dir = tempfile.mkdtemp()

    try:
        # 1. Copy Files
        bm_path = os.path.join(temp_dir, 'Bookmarks')
        copy_from_env('/home/ga/.config/google-chrome/Default/Bookmarks', bm_path)
        
        hist_path = os.path.join(temp_dir, 'History')
        copy_from_env('/home/ga/.config/google-chrome/Default/History', hist_path)
        
        cook_path = os.path.join(temp_dir, 'Cookies')
        copy_from_env('/home/ga/.config/google-chrome/Default/Cookies', cook_path)
        
        prefs_path = os.path.join(temp_dir, 'Preferences')
        copy_from_env('/home/ga/.config/google-chrome/Default/Preferences', prefs_path)

        webdata_path = os.path.join(temp_dir, 'Web Data')
        copy_from_env('/home/ga/.config/google-chrome/Default/Web Data', webdata_path)

        # 2. Check Bookmarks
        bm_score = 0
        pers_purged_score = 0
        try:
            with open(bm_path, 'r') as f:
                bms = json.load(f)
            
            bar_children = bms.get('roots', {}).get('bookmark_bar', {}).get('children', [])
            
            folders_found = [c['name'] for c in bar_children if c.get('type') == 'folder']
            matching_folders = [f for f in expected_folders if f in folders_found]
            score += len(matching_folders) * (15.0 / len(expected_folders))
            feedback_parts.append(f"Bookmark folders found: {len(matching_folders)}/4")

            # Check prof domains in folders
            prof_found = 0
            for child in bar_children:
                if child.get('type') == 'folder':
                    for sub in child.get('children', []):
                        url = sub.get('url', '').lower()
                        if any(pd in url for pd in prof_domains):
                            prof_found += 1
            
            if prof_found >= 18:
                score += 20
                feedback_parts.append(f"Professional bookmarks correctly sorted ({prof_found}/20)")
            else:
                score += int((prof_found / 20.0) * 20)
                feedback_parts.append(f"Professional bookmarks sorted: {prof_found}/20")

            # Check personal domains purged
            all_urls = json.dumps(bms).lower()
            pers_found = sum(1 for pd in pers_domains if pd in all_urls)
            if pers_found == 0:
                score += 10
                feedback_parts.append("Personal bookmarks successfully purged")
            else:
                feedback_parts.append(f"Found {pers_found} personal bookmarks remaining")

        except Exception as e:
            feedback_parts.append(f"Bookmarks parsing failed: {e}")

        # 3. Check History and Cookies Selective Purge
        hist_score = 0
        try:
            conn = sqlite3.connect(hist_path)
            c = conn.cursor()
            
            # Check personal domains
            pers_queries = [f"url LIKE '%{d}%'" for d in pers_domains]
            c.execute(f"SELECT COUNT(*) FROM urls WHERE {' OR '.join(pers_queries)}")
            pers_hist_count = c.fetchone()[0]

            # Check professional domains
            prof_queries = [f"url LIKE '%{d}%'" for d in prof_domains]
            c.execute(f"SELECT COUNT(*) FROM urls WHERE {' OR '.join(prof_queries)}")
            prof_hist_count = c.fetchone()[0]
            conn.close()

            # Repeat for Cookies
            conn = sqlite3.connect(cook_path)
            c = conn.cursor()
            pers_queries_c = [f"host_key LIKE '%{d}%'" for d in pers_domains]
            c.execute(f"SELECT COUNT(*) FROM cookies WHERE {' OR '.join(pers_queries_c)}")
            pers_cook_count = c.fetchone()[0]

            prof_queries_c = [f"host_key LIKE '%{d}%'" for d in prof_domains]
            c.execute(f"SELECT COUNT(*) FROM cookies WHERE {' OR '.join(prof_queries_c)}")
            prof_cook_count = c.fetchone()[0]
            conn.close()

            if pers_hist_count == 0 and pers_cook_count == 0:
                if prof_hist_count > 0 and prof_cook_count > 0:
                    score += 20
                    feedback_parts.append("Personal history/cookies purged while professional data preserved")
                else:
                    feedback_parts.append("Browsing data wiped entirely (did not preserve professional data)")
            else:
                feedback_parts.append(f"Personal data remains: {pers_hist_count} history entries, {pers_cook_count} cookies")

        except Exception as e:
            feedback_parts.append(f"DB verification failed: {e}")

        # 4. Check Preferences (Download & PDF)
        try:
            with open(prefs_path, 'r') as f:
                prefs = json.load(f)
            
            dl_prefs = prefs.get('download', {})
            dl_dir = dl_prefs.get('default_directory', '')
            dl_prompt = dl_prefs.get('prompt_for_download', False)
            pdf_external = prefs.get('plugins', {}).get('always_open_pdf_externally', False)

            dl_score = 0
            if expected_dl_dir in dl_dir:
                dl_score += 5
            if dl_prompt is True:
                dl_score += 5
            
            score += dl_score
            feedback_parts.append(f"Download settings configured: {dl_score}/10")

            if pdf_external is True:
                score += 10
                feedback_parts.append("PDF external download enabled")
            else:
                feedback_parts.append("PDF external download not enabled")
                
        except Exception as e:
            feedback_parts.append(f"Preferences parsing failed: {e}")

        # 5. Check Custom Search Engines (Web Data DB)
        try:
            conn = sqlite3.connect(webdata_path)
            c = conn.cursor()
            c.execute("SELECT keyword, url FROM keywords")
            engines = {row[0]: row[1] for row in c.fetchall()}
            conn.close()

            se_score = 0
            for kw, expected_url in expected_se.items():
                if kw in engines and expected_url in engines[kw]:
                    se_score += 7.5
            
            score += se_score
            feedback_parts.append(f"Custom search engines configured: {se_score}/15")

        except Exception as e:
            feedback_parts.append(f"Search engine verification failed (Web Data DB missing/locked): {e}")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 70
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }