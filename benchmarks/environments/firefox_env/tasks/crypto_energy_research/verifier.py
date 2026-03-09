#!/usr/bin/env python3
"""
Verifier for crypto_energy_research task.
Validates browser history, bookmarks, file downloads, and JSON report content.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_crypto_energy_research(traj, env_info, task_info):
    """
    Verify the Crypto Mining Environmental Impact Research task.
    """
    # 1. Setup - Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve Exported Result (Browser state & file metadata)
    task_result_path = "/tmp/task_result.json"
    browser_state = {}
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(task_result_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            browser_state = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Retrieve User's JSON Brief (Content)
    user_json_path = "/home/ga/Documents/crypto_environmental_brief.json"
    user_content = {}
    json_load_success = False
    
    if browser_state.get('json_file', {}).get('exists', False):
        temp_brief = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(user_json_path, temp_brief.name)
            with open(temp_brief.name, 'r') as f:
                user_content = json.load(f)
            json_load_success = True
        except Exception as e:
            logger.warning(f"Failed to load user JSON brief: {e}")
        finally:
            if os.path.exists(temp_brief.name):
                os.unlink(temp_brief.name)

    # ================= SCORING LOGIC =================

    score = 0
    feedback = []
    
    # Criterion 1: Browser History (20 pts)
    # Require visits to at least 3 of the 4 domains
    hist = browser_state.get('history_stats', {})
    domains_visited = 0
    visited_list = []
    
    if hist.get('eia', 0) > 0: domains_visited += 1; visited_list.append("EIA")
    if hist.get('epa', 0) > 0: domains_visited += 1; visited_list.append("EPA")
    if hist.get('whitehouse', 0) > 0: domains_visited += 1; visited_list.append("WhiteHouse")
    if hist.get('iea', 0) > 0: domains_visited += 1; visited_list.append("IEA")
    
    if domains_visited >= 3:
        score += 20
        feedback.append(f"History Check: Passed ({domains_visited}/4 domains visited: {', '.join(visited_list)})")
    else:
        feedback.append(f"History Check: Failed. Only {domains_visited} domains visited (Need 3+). Visited: {visited_list}")

    # Criterion 2: Bookmarks (20 pts)
    # Folder found + Count >= 5
    bm = browser_state.get('bookmarks', {})
    if bm.get('folder_found', False):
        count = bm.get('count', 0)
        if count >= 5:
            score += 20
            feedback.append(f"Bookmarks Check: Passed (Folder found with {count} bookmarks)")
        else:
            score += 10 # Partial credit for folder existence
            feedback.append(f"Bookmarks Check: Partial. Folder found but only {count}/5 bookmarks")
    else:
        feedback.append("Bookmarks Check: Failed. Folder 'Crypto Environmental Research' not found")

    # Criterion 3: PDF Download (15 pts)
    dl = browser_state.get('download', {})
    if dl.get('pdf_found', False):
        score += 15
        feedback.append(f"Download Check: Passed (Found new PDF: {dl.get('filename')})")
    else:
        feedback.append("Download Check: Failed. No valid PDF >10KB found in Downloads created during task")

    # Criterion 4: JSON Brief Existence & Freshness (10 pts)
    js_meta = browser_state.get('json_file', {})
    if js_meta.get('exists', False) and js_meta.get('fresh', False):
        score += 10
        feedback.append("JSON File Check: Passed (File exists and created during task)")
    elif js_meta.get('exists', False):
        score += 5
        feedback.append("JSON File Check: Partial. File exists but timestamp predates task (stale?)")
    else:
        feedback.append("JSON File Check: Failed. File not found")

    # Criterion 5: JSON Content Quality (35 pts total)
    if json_load_success:
        # Schema Check (10 pts)
        required_keys = ['topic', 'bitcoin_annual_energy_twh', 'us_crypto_mining_share_global_pct', 
                         'co2_equivalent_description', 'ostp_report_year', 'key_findings', 'sources']
        missing_keys = [k for k in required_keys if k not in user_content]
        
        if not missing_keys:
            score += 10
            feedback.append("JSON Schema: Passed (All keys present)")
            
            # Data Plausibility (15 pts)
            # Bitcoin Energy: 50-300
            val_energy = user_content.get('bitcoin_annual_energy_twh')
            # US Share: 10-60
            val_share = user_content.get('us_crypto_mining_share_global_pct')
            
            data_ok = True
            if not isinstance(val_energy, (int, float)) or not (50 <= val_energy <= 300):
                feedback.append(f"Data Check: Energy value {val_energy} out of range (50-300)")
                data_ok = False
            
            if not isinstance(val_share, (int, float)) or not (10 <= val_share <= 60):
                feedback.append(f"Data Check: US Share {val_share}% out of range (10-60)")
                data_ok = False
                
            if user_content.get('ostp_report_year') != 2022:
                feedback.append(f"Data Check: OSTP Year {user_content.get('ostp_report_year')} incorrect (Expected 2022)")
                data_ok = False
                
            if data_ok:
                score += 15
                feedback.append("Data Plausibility: Passed")
            
            # Content Length (10 pts)
            # Findings should be a list of strings, Sources a list of dicts
            findings = user_content.get('key_findings', [])
            sources = user_content.get('sources', [])
            
            if isinstance(findings, list) and len(findings) >= 3 and isinstance(sources, list) and len(sources) >= 3:
                score += 10
                feedback.append("Content Depth: Passed (3+ findings and sources)")
            else:
                feedback.append("Content Depth: Failed (Need 3+ findings and 3+ sources)")
                
        else:
            feedback.append(f"JSON Schema: Failed. Missing keys: {missing_keys}")
    else:
        feedback.append("JSON Content: Failed to parse user JSON file")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }