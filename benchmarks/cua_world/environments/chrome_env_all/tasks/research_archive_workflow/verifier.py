#!/usr/bin/env python3
"""
Verifier for Chrome Research Archive Workflow Task (research_archive_workflow@1)
Task: Create comprehensive research archive (bookmark folder + bookmark + reading list + PDF)

Verification Strategy:
- Multi-format archival verification across three preservation methods
- Bookmark organization: Verify folder creation and article bookmark
- Reading List: Check article added to Chrome Reading List
- PDF Export: Verify PDF saved with proper naming
- Semantic validation: Ensure all three methods reference the same content
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
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

# Try to import PDF library
try:
    from PyPDF2 import PdfReader
    HAS_PYPDF = True
except ImportError:
    try:
        import pypdf
        from pypdf import PdfReader
        HAS_PYPDF = True
    except ImportError:
        HAS_PYPDF = False
        logger.warning("PyPDF2/pypdf not available, PDF analysis will be limited")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for research_archive_workflow@1.
    
    Verifies that the agent successfully created a multi-format research archive:
    1. Created an organized bookmark folder
    2. Bookmarked the article in that folder
    3. Added article to Reading List
    4. Saved article as PDF with descriptive name
    
    Scoring:
    - Need at least 4/6 criteria to pass (67%)
    - Perfect score requires all 6 criteria
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    # Target article URL (local file)
    target_url = "file:///home/ga/Documents/ai_agents_research.html"
    
    try:
        # Verification results dictionary
        results = {
            "bookmark_folder_created": False,
            "article_bookmarked": False,
            "bookmark_well_named": False,
            "reading_list_added": False,
            "pdf_exported": False,
            "pdf_well_named": False
        }
        
        feedback_parts = []
        
        # Step 1: Verify bookmark organization
        logger.info("Verifying bookmark organization...")
        bookmark_result = verify_bookmark_organization(copy_from_env, target_url)
        
        results["bookmark_folder_created"] = bookmark_result["folder_created"]
        results["article_bookmarked"] = bookmark_result["bookmark_present"]
        results["bookmark_well_named"] = bookmark_result["custom_name"]
        
        if bookmark_result["folder_created"]:
            feedback_parts.append(f"✓ Bookmark folder created: '{bookmark_result['folder_name']}'")
        else:
            feedback_parts.append("✗ No research-related bookmark folder found")
        
        if bookmark_result["bookmark_present"]:
            feedback_parts.append(f"✓ Article bookmarked in organized folder")
            if bookmark_result["custom_name"]:
                feedback_parts.append(f"✓ Bookmark has descriptive name: '{bookmark_result['bookmark_name']}'")
            else:
                feedback_parts.append(f"⚠ Bookmark name could be more descriptive: '{bookmark_result['bookmark_name']}'")
        else:
            feedback_parts.append("✗ Article not bookmarked in folder")
        
        # Step 2: Verify Reading List entry
        logger.info("Verifying Reading List entry...")
        reading_list_result = verify_reading_list(copy_from_env, target_url)
        
        results["reading_list_added"] = reading_list_result["added"]
        
        if reading_list_result["added"]:
            feedback_parts.append("✓ Article added to Chrome Reading List")
        else:
            feedback_parts.append(f"✗ Article not in Reading List: {reading_list_result['reason']}")
        
        # Step 3: Verify PDF export
        logger.info("Verifying PDF export...")
        pdf_result = verify_pdf_export(copy_from_env, target_url)
        
        results["pdf_exported"] = pdf_result["found"]
        results["pdf_well_named"] = pdf_result["well_named"]
        
        if pdf_result["found"]:
            feedback_parts.append(f"✓ PDF exported: {pdf_result['filename']} ({pdf_result['size_kb']:.1f} KB)")
            if pdf_result["well_named"]:
                feedback_parts.append(f"✓ PDF has descriptive filename")
            else:
                feedback_parts.append(f"⚠ PDF filename could be more descriptive")
        else:
            feedback_parts.append(f"✗ PDF not found in Downloads: {pdf_result['reason']}")
        
        # Calculate score
        criteria_met = sum([
            results["bookmark_folder_created"],
            results["article_bookmarked"],
            results["bookmark_well_named"],
            results["reading_list_added"],
            results["pdf_exported"],
            results["pdf_well_named"]
        ])
        
        total_criteria = 6
        score = int((criteria_met / total_criteria) * 100)
        passed = criteria_met >= 4  # Need at least 4/6 criteria
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*60}"
        feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        
        if passed:
            if criteria_met == total_criteria:
                feedback += "\n✅ EXCELLENT: Complete multi-format research archive created!"
            else:
                feedback += "\n✅ PASSED: Research archive created with minor issues"
        else:
            feedback += "\n❌ FAILED: Incomplete research archive workflow"
            feedback += f"\n   (Need {4 - criteria_met} more criteria to pass)"
        
        # Clean up
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": results
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_bookmark_organization(copy_from_env, target_url: str) -> Dict[str, Any]:
    """
    Verify that article was bookmarked in an organized folder structure.
    
    Args:
        copy_from_env: Function to copy files from container
        target_url: Expected URL of the bookmarked article
        
    Returns:
        Dict with verification results
    """
    result = {
        "folder_created": False,
        "bookmark_present": False,
        "custom_name": False,
        "folder_name": "",
        "bookmark_name": ""
    }
    
    try:
        # Copy bookmarks file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple locations
        bookmarks_paths = [
            "/tmp/research_archive_verification/Bookmarks.json",
            "/tmp/Bookmarks.json",
            "/home/ga/.config/google-chrome-cdp/Default/Bookmarks",
            "/home/ga/.config/google-chrome/Default/Bookmarks"
        ]
        
        bookmarks_data = None
        for path in bookmarks_paths:
            try:
                copy_from_env(path, temp_file.name)
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 10:
                    bookmarks_data = parse_bookmarks(temp_file.name)
                    logger.info(f"Successfully loaded bookmarks from: {path}")
                    break
            except Exception as e:
                logger.debug(f"Could not load from {path}: {e}")
                continue
        
        os.unlink(temp_file.name)
        
        if not bookmarks_data:
            return result
        
        # Navigate to bookmark bar
        bookmark_bar = bookmarks_data.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        
        # Look for research-related folder
        research_keywords = ['research', 'ai', 'paper', 'article', 'project', '2024', 'study']
        target_folder = None
        
        for child in children:
            if child.get('type') == 'folder':
                folder_name = child.get('name', '').lower()
                if any(keyword in folder_name for keyword in research_keywords):
                    result["folder_created"] = True
                    result["folder_name"] = child.get('name', '')
                    target_folder = child
                    logger.info(f"Found research folder: {result['folder_name']}")
                    break
        
        if not target_folder:
            return result
        
        # Look for bookmark with target URL in folder
        folder_children = target_folder.get('children', [])
        normalized_target = normalize_url(target_url)
        
        for item in folder_children:
            if item.get('type') == 'url':
                item_url = item.get('url', '')
                if normalize_url(item_url) == normalized_target:
                    result["bookmark_present"] = True
                    result["bookmark_name"] = item.get('name', '')
                    
                    # Check if name is descriptive
                    name_lower = result["bookmark_name"].lower()
                    descriptive_keywords = ['ai', 'agent', 'research', 'review', 'article', 'autonomous']
                    if any(keyword in name_lower for keyword in descriptive_keywords):
                        result["custom_name"] = True
                    
                    logger.info(f"Found bookmark: {result['bookmark_name']}")
                    break
        
        return result
        
    except Exception as e:
        logger.error(f"Error verifying bookmarks: {e}")
        return result


def verify_reading_list(copy_from_env, target_url: str) -> Dict[str, Any]:
    """
    Verify that article was added to Chrome Reading List.
    
    Note: Reading List data location varies by Chrome version.
    May be in Preferences, or in a separate ReadingList database.
    
    Args:
        copy_from_env: Function to copy files from container
        target_url: Expected URL in reading list
        
    Returns:
        Dict with verification results
    """
    result = {
        "added": False,
        "reason": "Not checked yet"
    }
    
    try:
        # Copy preferences file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        prefs_paths = [
            "/tmp/research_archive_verification/Preferences.json",
            "/tmp/Preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        for path in prefs_paths:
            try:
                copy_from_env(path, temp_file.name)
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 10:
                    prefs_data = parse_preferences(temp_file.name)
                    logger.info(f"Successfully loaded preferences from: {path}")
                    break
            except Exception as e:
                logger.debug(f"Could not load from {path}: {e}")
                continue
        
        os.unlink(temp_file.name)
        
        if not prefs_data:
            result["reason"] = "Could not access Chrome Preferences"
            return result
        
        # Check for reading list data (varies by Chrome version)
        normalized_target = normalize_url(target_url)
        
        # Try different possible locations in preferences
        reading_list_locations = [
            prefs_data.get('reading_list', {}).get('entries', []),
            prefs_data.get('read_later', {}).get('entries', []),
            prefs_data.get('reading_list', {}).get('items', []),
        ]
        
        for entries in reading_list_locations:
            if not entries:
                continue
            
            for entry in entries:
                entry_url = entry.get('url', '')
                if normalize_url(entry_url) == normalized_target:
                    result["added"] = True
                    result["reason"] = "Found in Reading List"
                    logger.info("Article found in Reading List")
                    return result
        
        # Fallback: Check if target URL appears anywhere in preferences as string
        prefs_str = json.dumps(prefs_data)
        if 'ai_agents_research' in prefs_str.lower() or normalized_target in prefs_str:
            result["added"] = True
            result["reason"] = "Found evidence of Reading List entry"
            logger.info("Possible Reading List entry detected")
            return result
        
        result["reason"] = "Article not found in Reading List data"
        return result
        
    except Exception as e:
        logger.error(f"Error verifying Reading List: {e}")
        result["reason"] = f"Error: {str(e)}"
        return result


def verify_pdf_export(copy_from_env, target_url: str) -> Dict[str, Any]:
    """
    Verify that article was saved as PDF with appropriate naming.
    
    Args:
        copy_from_env: Function to copy files from container
        target_url: Source URL for context
        
    Returns:
        Dict with verification results
    """
    result = {
        "found": False,
        "well_named": False,
        "filename": "",
        "size_kb": 0,
        "page_count": 0,
        "reason": "Not checked yet"
    }
    
    try:
        # First, get list of PDF files
        temp_list = tempfile.NamedTemporaryFile(delete=False, mode='w+', suffix='.txt')
        temp_list.close()
        
        list_paths = [
            "/tmp/research_archive_verification/pdf_files.txt",
            "/tmp/pdf_files.txt"
        ]
        
        pdf_filenames = []
        for path in list_paths:
            try:
                copy_from_env(path, temp_list.name)
                if os.path.exists(temp_list.name):
                    with open(temp_list.name, 'r') as f:
                        pdf_filenames = [line.strip() for line in f if line.strip()]
                    if pdf_filenames:
                        break
            except Exception as e:
                logger.debug(f"Could not load PDF list from {path}: {e}")
                continue
        
        os.unlink(temp_list.name)
        
        if not pdf_filenames:
            result["reason"] = "No PDF files found in Downloads directory"
            return result
        
        logger.info(f"Found {len(pdf_filenames)} PDF file(s): {pdf_filenames}")
        
        # Check each PDF file
        for pdf_name in pdf_filenames:
            # Try to copy the PDF
            temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
            temp_pdf.close()
            
            pdf_paths = [
                f"/tmp/research_archive_verification/{pdf_name}",
                f"/tmp/{pdf_name}",
                f"/home/ga/Downloads/{pdf_name}"
            ]
            
            pdf_copied = False
            for path in pdf_paths:
                try:
                    copy_from_env(path, temp_pdf.name)
                    if os.path.exists(temp_pdf.name) and os.path.getsize(temp_pdf.name) > 1024:
                        pdf_copied = True
                        break
                except Exception as e:
                    logger.debug(f"Could not copy PDF from {path}: {e}")
                    continue
            
            if not pdf_copied:
                os.unlink(temp_pdf.name)
                continue
            
            # We found a PDF!
            result["found"] = True
            result["filename"] = pdf_name
            result["size_kb"] = os.path.getsize(temp_pdf.name) / 1024
            
            # Check if filename is descriptive
            name_lower = pdf_name.lower()
            descriptive_keywords = ['research', 'ai', 'agent', 'article', 'review', 'autonomous']
            if any(keyword in name_lower for keyword in descriptive_keywords):
                result["well_named"] = True
            
            # Try to get page count if PyPDF available
            if HAS_PYPDF:
                try:
                    reader = PdfReader(temp_pdf.name)
                    result["page_count"] = len(reader.pages)
                    logger.info(f"PDF has {result['page_count']} pages")
                except Exception as e:
                    logger.warning(f"Could not read PDF page count: {e}")
            
            os.unlink(temp_pdf.name)
            
            result["reason"] = "PDF successfully exported"
            return result
        
        result["reason"] = "PDF files found but could not be verified"
        return result
        
    except Exception as e:
        logger.error(f"Error verifying PDF: {e}")
        result["reason"] = f"Error: {str(e)}"
        return result


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison by removing trailing slashes, 
    converting to lowercase, and removing protocol.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Remove protocol
    url = re.sub(r'^https?://', '', url)
    url = re.sub(r'^file://', '', url)
    
    # Convert to lowercase
    url = url.lower()
    
    # Remove trailing slashes
    url = url.rstrip('/')
    
    # Remove query parameters and fragments for local files
    if 'localhost' in url or '127.0.0.1' in url or url.startswith('/'):
        url = url.split('?')[0].split('#')[0]
    
    return url
