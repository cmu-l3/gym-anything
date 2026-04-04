#!/usr/bin/env python3
"""
Verifier for Met Museum Curation Task (met_museum_curation_research@1)

Scoring Criteria (100 pts total):
1. Catalog JSON structure (20 pts)
2. Catalog Content (3 entries + correct fields + correct Medium) (20 pts)
3. Bookmark Organization (Folder exists + 3 Met URLs) (20 pts)
4. Image Download (File exists + >500KB) (25 pts)
5. Source Integrity (URLs are from metmuseum.org) (15 pts)

Pass Threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_met_curation(traj, env_info, task_info):
    # 1. Retrieve result via copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/met_curation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load verification data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1 & 2: Catalog JSON (40 pts total) ---
    catalog = result.get("catalog", {})
    catalog_content = []
    
    if catalog.get("exists") and catalog.get("valid_json"):
        score += 20
        feedback_parts.append("Catalog JSON valid (+20)")
        
        try:
            raw = catalog.get("content_raw", "[]")
            catalog_content = json.loads(raw)
            
            # Check length
            if isinstance(catalog_content, list) and len(catalog_content) >= 3:
                # Check fields
                item = catalog_content[0]
                required_keys = ["title", "date", "medium", "accession_number", "url"]
                has_keys = all(k in item for k in required_keys)
                
                # Check filtering (Medium should contain 'Oil')
                has_oil = any("oil" in str(i.get("medium", "")).lower() for i in catalog_content)
                
                if has_keys and has_oil:
                    score += 20
                    feedback_parts.append("Catalog content correct (Fields & 'Oil' medium verified) (+20)")
                elif has_keys:
                    score += 10
                    feedback_parts.append("Catalog structure correct, but 'Oil' medium not found (-10)")
                else:
                    score += 5
                    feedback_parts.append("Catalog exists but missing required JSON keys (-15)")
            else:
                feedback_parts.append(f"Catalog contains {len(catalog_content)} items (expected >= 3) (+0)")
        except:
            feedback_parts.append("Error parsing catalog content")
    else:
        feedback_parts.append("Catalog JSON file missing or invalid (+0)")

    # --- Criterion 3 & 5: Bookmarks (35 pts total) ---
    bk = result.get("bookmarks", {})
    if bk.get("folder_found"):
        count = bk.get("count", 0)
        urls = bk.get("urls", [])
        
        if count >= 3:
            score += 20
            feedback_parts.append("Bookmark folder found with >= 3 items (+20)")
            
            # Check source integrity (metmuseum.org)
            met_urls = [u for u in urls if "metmuseum.org" in u]
            if len(met_urls) >= 3:
                score += 15
                feedback_parts.append("Bookmarks link to Met Museum (+15)")
            else:
                feedback_parts.append("Bookmarks do not link to metmuseum.org (+0)")
        else:
            score += 10
            feedback_parts.append(f"Bookmark folder found but only has {count} items (+10)")
    else:
        feedback_parts.append("'Met Van Gogh' bookmark folder not found (+0)")

    # --- Criterion 4: Image Download (25 pts total) ---
    img = result.get("image", {})
    if img.get("found"):
        size_kb = img.get("size_bytes", 0) / 1024
        
        if size_kb > 500:
            score += 25
            feedback_parts.append(f"High-res image found ({int(size_kb)}KB) (+25)")
        elif size_kb > 50:
            score += 10
            feedback_parts.append(f"Image found but low resolution/thumbnail ({int(size_kb)}KB) (+10)")
        else:
            feedback_parts.append("Image found but likely empty/corrupt (+0)")
    else:
        feedback_parts.append("No downloaded image found in ~/Documents/met_images (+0)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }