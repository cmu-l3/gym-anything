#!/usr/bin/env python3
"""
Verifier for Chrome Multi-Source Presentation Research Task (presentation_research_workflow@1)
Task: Navigate to research sources, organize in bookmarks folder, and download infographic

Verification Strategy:
- Parse Chrome Bookmarks JSON to find "Climate Presentation" folder
- Check that folder contains all three expected URLs (World Bank, Scholar, BBC)
- Verify image file was downloaded to Downloads folder
- Check browsing history for evidence of visiting the research sites
- Multi-criteria scoring with detailed feedback
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add Chrome verification utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        parse_bookmarks,
        get_bookmark_bar_folders,
        get_folder_bookmarks,
        parse_history,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_bookmarks(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def parse_history(path):
        try:
            conn = sqlite3.connect(path)
            cursor = conn.cursor()
            cursor.execute("SELECT url, title FROM urls ORDER BY last_visit_time DESC LIMIT 100")
            results = cursor.fetchall()
            conn.close()
            return results
        except Exception as e:
            logger.error(f"Error parsing history: {e}")
            return []
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for presentation_research_workflow@1.
    
    Verifies:
    1. Bookmark folder "Climate Presentation" exists in bookmark bar
    2. Three research URLs are bookmarked in that folder
    3. Image file was downloaded
    4. (Optional) Browsing history shows visits to research sites
    
    Scoring:
    - 100%: All 5 criteria met (folder, 3 bookmarks, image, history)
    - 90%: 4/5 criteria met
    - 75%: 3/5 criteria met (minimum passing)
    - 60%: 2/5 criteria met
    - <50%: <2 criteria met
    
    Pass threshold: 75%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Verify bookmark organization
        bookmark_result = verify_bookmark_organization(copy_from_env)
        
        # Verify image download
        image_result = verify_image_download(copy_from_env)
        
        # Verify browsing history (optional, for bonus points)
        history_result = verify_browsing_history(copy_from_env)
        
        # Calculate overall score
        final_result = calculate_final_score(bookmark_result, image_result, history_result)
        
        # Cleanup
        cleanup_verification_temp()
        
        return final_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_bookmark_organization(copy_from_env) -> Dict[str, Any]:
    """
    Verify bookmark folder and URLs were correctly organized.
    
    Returns:
        Dict with folder_exists, bookmark_count, bookmarks_found list, and score
    """
    expected_folder_name = "Climate Presentation"
    expected_domains = {
        "worldbank": "worldbank.org",
        "scholar": "scholar.google.com",
        "bbc": "bbc.com"
    }
    
    result = {
        "folder_exists": False,
        "bookmark_count": 0,
        "bookmarks_found": [],
        "score": 0,
        "feedback": ""
    }
    
    try:
        # Try to copy bookmarks file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        bookmarks_paths = [
            "/tmp/bookmarks_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        for container_path in bookmarks_paths:
            try:
                logger.info(f"Trying to copy bookmarks from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        bookmarks_data = json.load(f)
                    logger.info(f"Successfully loaded bookmarks from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        
        if not bookmarks_data:
            result["feedback"] = "Could not access bookmarks file"
            return result
        
        # Navigate to bookmark bar
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        
        # Find the target folder
        target_folder = None
        for child in children:
            if child.get('type') == 'folder':
                folder_name = child.get('name', '')
                # Flexible matching: check if folder name contains key terms
                if 'climate' in folder_name.lower() and 'presentation' in folder_name.lower():
                    target_folder = child
                    result["folder_exists"] = True
                    logger.info(f"Found folder: {folder_name}")
                    break
        
        if not target_folder:
            result["feedback"] = f"Bookmark folder '{expected_folder_name}' not found in bookmark bar"
            return result
        
        # Check bookmarks within the folder
        folder_children = target_folder.get('children', [])
        bookmarked_urls = []
        
        for item in folder_children:
            if item.get('type') == 'url':
                url = item.get('url', '').lower()
                bookmarked_urls.append(url)
                
                # Check which expected domains are present
                for key, domain in expected_domains.items():
                    if domain in url:
                        result["bookmarks_found"].append(key)
                        logger.info(f"Found bookmark for {key}: {url}")
        
        # Remove duplicates from bookmarks_found
        result["bookmarks_found"] = list(set(result["bookmarks_found"]))
        result["bookmark_count"] = len(bookmarked_urls)
        
        # Calculate score
        if result["folder_exists"]:
            result["score"] += 20  # Folder exists
        
        result["score"] += len(result["bookmarks_found"]) * 13  # 13 points per bookmark (max 39)
        
        # Generate feedback
        if result["folder_exists"] and len(result["bookmarks_found"]) == 3:
            result["feedback"] = f"✓ Folder created and all 3 sources bookmarked"
        elif result["folder_exists"]:
            result["feedback"] = f"⚠ Folder found but only {len(result['bookmarks_found'])}/3 sources bookmarked"
        else:
            result["feedback"] = "✗ Bookmark folder not created"
        
        logger.info(f"Bookmark verification: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Error verifying bookmarks: {e}", exc_info=True)
        result["feedback"] = f"Error checking bookmarks: {str(e)}"
        return result


def verify_image_download(copy_from_env) -> Dict[str, Any]:
    """
    Verify that the climate infographic image was downloaded.
    
    Returns:
        Dict with image_found, file_size, score, and feedback
    """
    result = {
        "image_found": False,
        "file_size": 0,
        "score": 0,
        "feedback": ""
    }
    
    try:
        # Try to copy the downloaded image
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_file.close()
        
        # Try multiple possible locations and filenames
        image_paths = [
            "/tmp/downloaded_infographic.png",
            "/home/ga/Downloads/climate_infographic.png",
            "/home/ga/Downloads/climate_data_chart.png",
        ]
        
        # Also try to find any recent PNG in Downloads
        for container_path in image_paths:
            try:
                logger.info(f"Trying to copy image from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                if os.path.exists(temp_file.name):
                    file_size = os.path.getsize(temp_file.name)
                    if file_size > 1024:  # At least 1KB
                        result["image_found"] = True
                        result["file_size"] = file_size
                        logger.info(f"Found image: {container_path} ({file_size} bytes)")
                        break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        
        # Calculate score
        if result["image_found"]:
            if result["file_size"] > 10 * 1024:  # >10KB
                result["score"] = 30  # Full points
                result["feedback"] = f"✓ Image downloaded ({result['file_size'] / 1024:.1f} KB)"
            else:
                result["score"] = 15  # Partial credit
                result["feedback"] = f"⚠ Image found but small ({result['file_size']} bytes)"
        else:
            result["feedback"] = "✗ Climate infographic not found in Downloads"
        
        logger.info(f"Image verification: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Error verifying image: {e}", exc_info=True)
        result["feedback"] = f"Error checking image: {str(e)}"
        return result


def verify_browsing_history(copy_from_env) -> Dict[str, Any]:
    """
    Verify that research URLs were visited (optional bonus criterion).
    
    Returns:
        Dict with sites_visited count, score, and feedback
    """
    result = {
        "sites_visited": 0,
        "visited_list": [],
        "score": 0,
        "feedback": ""
    }
    
    expected_domains = ["worldbank.org", "scholar.google.com", "bbc.com"]
    
    try:
        # Try to copy history file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_file.close()
        
        history_paths = [
            "/tmp/history_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        history_data = None
        for container_path in history_paths:
            try:
                logger.info(f"Trying to copy history from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    history_data = parse_history(temp_file.name)
                    logger.info(f"Successfully loaded history from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        
        if not history_data:
            result["feedback"] = "⚠ Could not verify browsing history"
            return result
        
        # Check which domains were visited
        history_urls = [url.lower() for url, _ in history_data]
        
        for domain in expected_domains:
            if any(domain in url for url in history_urls):
                result["sites_visited"] += 1
                result["visited_list"].append(domain)
                logger.info(f"Found visit to: {domain}")
        
        # Calculate score
        result["score"] = result["sites_visited"] * 3  # 3 points per site visited (max 9)
        
        if result["sites_visited"] == 3:
            result["feedback"] = f"✓ All 3 research sites visited"
        elif result["sites_visited"] > 0:
            result["feedback"] = f"⚠ {result['sites_visited']}/3 sites found in history"
        else:
            result["feedback"] = "⚠ Research sites not found in history"
        
        logger.info(f"History verification: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Error verifying history: {e}", exc_info=True)
        result["feedback"] = f"⚠ Could not verify history"
        return result


def calculate_final_score(bookmark_result: Dict, image_result: Dict, 
                         history_result: Dict) -> Dict[str, Any]:
    """
    Calculate final score and generate comprehensive feedback.
    
    Criteria:
    1. Bookmark folder created (20 points)
    2. Three bookmarks added (39 points total, 13 each)
    3. Image downloaded (30 points)
    4. History verification (9 points, 3 each)
    
    Total: 98 points possible
    Pass threshold: 75 points (need folder + 3 bookmarks + image, or similar)
    """
    total_score = 0
    feedback_parts = []
    
    # Add scores
    total_score += bookmark_result.get("score", 0)
    total_score += image_result.get("score", 0)
    total_score += history_result.get("score", 0)
    
    # Normalize to 100
    total_score = min(100, total_score)
    
    # Build detailed feedback
    feedback_parts.append("=" * 60)
    feedback_parts.append("PRESENTATION RESEARCH WORKFLOW VERIFICATION")
    feedback_parts.append("=" * 60)
    
    # Bookmark organization
    feedback_parts.append("\n📁 BOOKMARK ORGANIZATION:")
    feedback_parts.append(f"   {bookmark_result.get('feedback', 'Not checked')}")
    if bookmark_result.get("folder_exists"):
        feedback_parts.append(f"   - Folder exists: ✓")
        feedback_parts.append(f"   - Bookmarks found: {len(bookmark_result.get('bookmarks_found', []))}/3")
        for site in bookmark_result.get('bookmarks_found', []):
            feedback_parts.append(f"     • {site}: ✓")
        # Check which are missing
        all_sites = {"worldbank", "scholar", "bbc"}
        missing = all_sites - set(bookmark_result.get('bookmarks_found', []))
        for site in missing:
            feedback_parts.append(f"     • {site}: ✗")
    else:
        feedback_parts.append(f"   - Folder exists: ✗")
    
    # Image download
    feedback_parts.append("\n🖼️  IMAGE DOWNLOAD:")
    feedback_parts.append(f"   {image_result.get('feedback', 'Not checked')}")
    
    # History verification
    feedback_parts.append("\n🌐 BROWSING HISTORY:")
    feedback_parts.append(f"   {history_result.get('feedback', 'Not checked')}")
    
    # Summary
    feedback_parts.append("\n" + "=" * 60)
    feedback_parts.append(f"FINAL SCORE: {total_score}/100")
    
    # Determine pass/fail
    passed = total_score >= 75
    
    if passed:
        if total_score >= 95:
            feedback_parts.append("RESULT: ✅ EXCELLENT - All criteria met!")
        elif total_score >= 85:
            feedback_parts.append("RESULT: ✅ PASSED - Strong performance with minor issues")
        else:
            feedback_parts.append("RESULT: ✅ PASSED - Met minimum requirements")
    else:
        feedback_parts.append("RESULT: ❌ FAILED - Insufficient criteria met")
        feedback_parts.append("\nREQUIREMENTS NOT MET:")
        if not bookmark_result.get("folder_exists"):
            feedback_parts.append("  • Create bookmark folder 'Climate Presentation'")
        if len(bookmark_result.get('bookmarks_found', [])) < 3:
            feedback_parts.append("  • Bookmark all three research sources")
        if not image_result.get("image_found"):
            feedback_parts.append("  • Download the climate infographic image")
    
    feedback_parts.append("=" * 60)
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": {
            "bookmark_folder_exists": bookmark_result.get("folder_exists", False),
            "bookmarks_count": len(bookmark_result.get('bookmarks_found', [])),
            "bookmarks_found": bookmark_result.get('bookmarks_found', []),
            "image_downloaded": image_result.get("image_found", False),
            "image_size_bytes": image_result.get("file_size", 0),
            "sites_visited": history_result.get("sites_visited", 0),
            "visited_list": history_result.get("visited_list", [])
        }
    }
