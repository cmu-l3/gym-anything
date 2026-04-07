#!/usr/bin/env python3
"""
Verifier for bookmark_library_export task.
Verifies internal Edge state (Bookmarks JSON), exported HTML file, and instruction email.
"""

import json
import os
import tempfile
import logging
import re
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bookmark_library_export(traj, env_info, task_info):
    """
    Verifies the bookmark export task.
    
    Scoring Breakdown (100 pts):
    1. Internal Bookmarks State (40 pts)
       - Top-level folder 'District Resources' exists (10)
       - 3 Correct sub-folders exist (10)
       - Correct URLs present in correct structure (20)
    2. Exported HTML File (30 pts)
       - File exists and created during task (10)
       - Valid bookmark HTML format (5)
       - Contains required URLs (15)
    3. Instruction Email (30 pts)
       - File exists and created during task (5)
       - Mentions all 3 category names (10)
       - Mentions 'import' instructions (10)
       - Substantive content (>200 chars) (5)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- 1. Verify Internal Bookmarks JSON ---
    bookmarks_score = 0
    try:
        temp_bm = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env(result['bookmarks_db_path'], temp_bm.name)
        with open(temp_bm.name, 'r', encoding='utf-8') as f:
            bm_data = json.load(f)
        os.unlink(temp_bm.name)
        
        # Helper to recursively search folders
        def find_folder(node, name):
            if node.get('type') == 'folder' and node.get('name') == name:
                return node
            for child in node.get('children', []):
                found = find_folder(child, name)
                if found: return found
            return None

        # Helper to get all URLs in a folder (shallow)
        def get_urls(node):
            return [c.get('url', '') for c in node.get('children', []) if c.get('type') == 'url']

        # Find Root Folder
        root_nodes = bm_data.get('roots', {}).values()
        district_folder = None
        for root in root_nodes:
            district_folder = find_folder(root, "District Resources")
            if district_folder: break
            
        if district_folder:
            bookmarks_score += 10
            feedback.append("✓ 'District Resources' folder found in Edge.")
            
            # Check Sub-folders and URLs
            req_structure = task_info['metadata']['required_structure']['District Resources']
            subfolders_found = 0
            urls_found = 0
            total_req_urls = sum(len(v) for v in req_structure.values())
            
            for sub_name, req_urls in req_structure.items():
                sub_node = find_folder(district_folder, sub_name)
                if sub_node:
                    subfolders_found += 1
                    actual_urls = " ".join(get_urls(sub_node)).lower()
                    
                    # Check URL presence (partial match on domain)
                    folder_urls_ok = 0
                    for req_url in req_urls:
                        if req_url.lower() in actual_urls:
                            folder_urls_ok += 1
                    urls_found += folder_urls_ok
                else:
                    feedback.append(f"✗ Missing sub-folder: '{sub_name}'")

            # Score subfolders (Max 10)
            if subfolders_found == 3:
                bookmarks_score += 10
                feedback.append("✓ All 3 sub-folders found.")
            else:
                bookmarks_score += int((subfolders_found / 3) * 10)
                
            # Score URLs (Max 20)
            if urls_found >= 7: # Allow small margin of error (7 out of 9)
                bookmarks_score += 20
                feedback.append(f"✓ {urls_found}/{total_req_urls} URLs correctly placed.")
            elif urls_found > 0:
                bookmarks_score += int((urls_found / total_req_urls) * 20)
                feedback.append(f"⚠ Only {urls_found}/{total_req_urls} URLs found.")
            else:
                feedback.append("✗ No correct URLs found in folders.")

        else:
            feedback.append("✗ 'District Resources' folder NOT found in Edge.")

    except Exception as e:
        feedback.append(f"✗ Error reading Bookmarks JSON: {e}")
    
    score += bookmarks_score

    # --- 2. Verify Exported HTML File ---
    export_score = 0
    export_status = result.get('export_file_status', {})
    if export_status.get('exists') and export_status.get('created_during_task'):
        export_score += 10
        feedback.append("✓ Export file exists and created during task.")
        
        try:
            temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
            copy_from_env(result['export_file_path'], temp_html.name)
            with open(temp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
            os.unlink(temp_html.name)
            
            # Check format
            if "<DT><A HREF=" in html_content or "<!DOCTYPE NETSCAPE-Bookmark-file-1>" in html_content:
                export_score += 5
                feedback.append("✓ Valid bookmark HTML format.")
            else:
                feedback.append("⚠ Export file does not look like standard bookmark HTML.")

            # Check content for URLs
            found_exported_urls = 0
            all_req_urls = []
            for urls in task_info['metadata']['required_structure']['District Resources'].values():
                all_req_urls.extend(urls)
            
            for url in all_req_urls:
                if url in html_content:
                    found_exported_urls += 1
            
            if found_exported_urls >= 7:
                export_score += 15
                feedback.append(f"✓ Export contains {found_exported_urls} required URLs.")
            elif found_exported_urls > 0:
                export_score += int((found_exported_urls / 9) * 15)
                feedback.append(f"⚠ Export contains {found_exported_urls}/9 required URLs.")
            else:
                feedback.append("✗ Export file missing required URLs.")
                
        except Exception as e:
            feedback.append(f"✗ Error reading export file: {e}")
    else:
        feedback.append("✗ Export file missing or not created during task.")
    
    score += export_score

    # --- 3. Verify Instruction Email ---
    email_score = 0
    email_status = result.get('instructions_file_status', {})
    if email_status.get('exists') and email_status.get('created_during_task'):
        email_score += 5
        feedback.append("✓ Instruction file exists.")
        
        try:
            temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env(result['instructions_file_path'], temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                email_content = f.read().lower()
            os.unlink(temp_txt.name)
            
            # Check length
            if len(email_content) > 200:
                email_score += 5
                feedback.append("✓ Email content is substantive.")
            
            # Check for import instructions
            if "import" in email_content and ("html" in email_content or "file" in email_content):
                email_score += 10
                feedback.append("✓ Contains import instructions.")
            else:
                feedback.append("✗ Missing clear import instructions.")
                
            # Check for categories
            cats_found = 0
            if "math" in email_content or "stem" in email_content: cats_found += 1
            if "literacy" in email_content or "reading" in email_content: cats_found += 1
            if "reference" in email_content or "research" in email_content: cats_found += 1
            
            if cats_found == 3:
                email_score += 10
                feedback.append("✓ Mentions all 3 categories.")
            else:
                email_score += int((cats_found/3) * 10)
                feedback.append(f"⚠ Mentions {cats_found}/3 categories.")
                
        except Exception as e:
            feedback.append(f"✗ Error reading instruction file: {e}")
    else:
        feedback.append("✗ Instruction file missing.")
        
    score += email_score

    # Calculate Pass/Fail
    # Must have at least some success in both bookmark creation and exporting to pass
    passed = (score >= 65) and (bookmarks_score > 10) and (export_score > 10)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }