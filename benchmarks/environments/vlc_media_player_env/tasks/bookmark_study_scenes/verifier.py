#!/usr/bin/env python3
"""
Verifier for Bookmark Study Scenes task
"""

import sys
import os
import logging
import tempfile
import json
import re
import xml.etree.ElementTree as ET

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_xspf_bookmarks(xspf_path):
    """
    Parse bookmarks from VLC XSPF media library file.
    
    VLC stores bookmarks in XSPF extensions as:
    <vlc:option>bookmarks={name=Introduction,time=75000},{name=Concept1,time=375000}...</vlc:option>
    
    Time is in milliseconds.
    """
    try:
        tree = ET.parse(xspf_path)
        root = tree.getroot()
        
        bookmarks = []
        
        # Try multiple namespace patterns
        namespaces = [
            {'vlc': 'http://www.videolan.org/vlc/playlist/0'},
            {'vlc': 'http://www.videolan.org/vlc/playlist/ns/0/'},
            {}  # No namespace
        ]
        
        for ns in namespaces:
            # Look for VLC options containing bookmarks
            for option in root.findall('.//vlc:option', ns) if ns else root.findall('.//option'):
                option_text = option.text or ""
                
                if 'bookmarks=' in option_text or 'bookmark' in option_text.lower():
                    # Parse bookmark format: {name=...,time=...},{name=...,time=...}
                    bookmark_pattern = r'\{name=([^,}]+),time=(\d+)\}'
                    matches = re.findall(bookmark_pattern, option_text)
                    
                    for name, time_ms in matches:
                        bookmarks.append({
                            'name': name.strip(),
                            'time': int(time_ms) / 1000.0  # Convert ms to seconds
                        })
            
            # Also check for individual bookmark entries
            for bookmark_elem in root.findall('.//vlc:bookmark', ns) if ns else root.findall('.//bookmark'):
                name = bookmark_elem.get('name', '')
                time_ms = bookmark_elem.get('time', '0')
                
                if name:
                    bookmarks.append({
                        'name': name.strip(),
                        'time': float(time_ms) / 1000.0
                    })
        
        if bookmarks:
            logger.info(f"Parsed {len(bookmarks)} bookmarks from XSPF")
            return bookmarks
        
        # Fallback: try to parse raw text patterns
        with open(xspf_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Look for bookmark-like patterns in the raw XML
        bookmark_pattern = r'(?:bookmark|name)[:=]\s*["\']?([^,"\']+)["\']?\s*(?:,|\s+)(?:time|position)[:=]\s*(\d+)'
        matches = re.findall(bookmark_pattern, content, re.IGNORECASE)
        
        for name, time_val in matches:
            if name and time_val:
                bookmarks.append({
                    'name': name.strip(),
                    'time': int(time_val) / 1000.0  # Assume milliseconds
                })
        
        logger.info(f"Parsed {len(bookmarks)} bookmarks from XSPF (fallback)")
        return bookmarks
        
    except Exception as e:
        logger.error(f"Error parsing XSPF bookmarks: {e}")
        return []


def parse_sqlite_bookmarks(db_path):
    """
    Parse bookmarks from VLC SQLite media library database.
    
    VLC stores bookmarks in the media library database.
    Table structure varies by version.
    """
    try:
        import sqlite3
        
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        bookmarks = []
        
        # Try different possible table structures
        table_queries = [
            "SELECT name, time FROM bookmarks",
            "SELECT title, position FROM bookmarks",
            "SELECT name, timestamp FROM media_bookmarks",
            "SELECT * FROM bookmarks",
        ]
        
        for query in table_queries:
            try:
                cursor.execute(query)
                rows = cursor.fetchall()
                
                for row in rows:
                    if len(row) >= 2:
                        name = str(row[0]) if row[0] else ""
                        time_val = float(row[1]) if row[1] else 0.0
                        
                        # Time might be in milliseconds or seconds
                        if time_val > 10000:  # Likely milliseconds
                            time_val = time_val / 1000.0
                        
                        if name:
                            bookmarks.append({
                                'name': name.strip(),
                                'time': time_val
                            })
                
                if bookmarks:
                    break
                    
            except sqlite3.OperationalError:
                continue
        
        conn.close()
        
        logger.info(f"Parsed {len(bookmarks)} bookmarks from SQLite DB")
        return bookmarks
        
    except Exception as e:
        logger.error(f"Error parsing SQLite bookmarks: {e}")
        return []


def verify_bookmark_study_scenes(traj, env_info, task_info):
    """
    Verify bookmark study scenes task completion.
    
    Checks:
    1. At least 5 bookmarks created
    2. All bookmarks have descriptive custom names
    3. Bookmarks are well-distributed (span 60%+ of video)
    4. Bookmarks at reasonable positions (between 2% and 98%)
    5. Bookmarks saved persistently (exist in storage files)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    video_duration = 1500.0  # 25 minutes = 1500 seconds
    
    # Try to copy and parse bookmark storage files
    bookmarks = []
    storage_found = False
    
    # Try XSPF media library
    temp_ml_xspf = tempfile.NamedTemporaryFile(delete=False, suffix='.xspf')
    try:
        copy_from_env("/tmp/vlc_ml.xspf", temp_ml_xspf.name)
        storage_found = True
        xspf_bookmarks = parse_xspf_bookmarks(temp_ml_xspf.name)
        bookmarks.extend(xspf_bookmarks)
        logger.info(f"Found {len(xspf_bookmarks)} bookmarks in ml.xspf")
    except Exception as e:
        logger.info(f"ml.xspf not found or not parseable: {e}")
    finally:
        try:
            os.unlink(temp_ml_xspf.name)
        except:
            pass
    
    # Try bookmarks XSPF
    temp_bookmarks_xspf = tempfile.NamedTemporaryFile(delete=False, suffix='.xspf')
    try:
        copy_from_env("/tmp/vlc_bookmarks.xspf", temp_bookmarks_xspf.name)
        storage_found = True
        xspf_bookmarks = parse_xspf_bookmarks(temp_bookmarks_xspf.name)
        bookmarks.extend(xspf_bookmarks)
        logger.info(f"Found {len(xspf_bookmarks)} bookmarks in bookmarks.xspf")
    except Exception as e:
        logger.info(f"bookmarks.xspf not found or not parseable: {e}")
    finally:
        try:
            os.unlink(temp_bookmarks_xspf.name)
        except:
            pass
    
    # Try SQLite database
    temp_ml_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
    try:
        copy_from_env("/tmp/vlc_ml.db", temp_ml_db.name)
        storage_found = True
        db_bookmarks = parse_sqlite_bookmarks(temp_ml_db.name)
        bookmarks.extend(db_bookmarks)
        logger.info(f"Found {len(db_bookmarks)} bookmarks in ml.db")
    except Exception as e:
        logger.info(f"ml.db not found or not parseable: {e}")
    finally:
        try:
            os.unlink(temp_ml_db.name)
        except:
            pass
    
    # Remove duplicates (same name and similar time)
    unique_bookmarks = []
    for bookmark in bookmarks:
        is_duplicate = False
        for existing in unique_bookmarks:
            if (existing['name'] == bookmark['name'] and 
                abs(existing['time'] - bookmark['time']) < 5):
                is_duplicate = True
                break
        if not is_duplicate:
            unique_bookmarks.append(bookmark)
    
    bookmarks = unique_bookmarks
    
    logger.info(f"Total unique bookmarks found: {len(bookmarks)}")
    for bm in bookmarks:
        logger.info(f"  - {bm['name']}: {bm['time']:.1f}s")
    
    if not storage_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ No bookmark storage files found (ml.xspf, bookmarks.xspf, or ml.db)"
        }
    
    # Criterion 5: Persistent storage (files exist)
    criteria_met += 1
    feedback_parts.append("✅ Bookmark storage files found")
    
    if len(bookmarks) == 0:
        return {
            "passed": False,
            "score": 20,
            "feedback": "⚠️ Bookmark files found but no bookmarks parsed | " + " | ".join(feedback_parts)
        }
    
    # Criterion 1: At least 5 bookmarks
    if len(bookmarks) >= 5:
        criteria_met += 1
        feedback_parts.append(f"✅ Bookmark count: {len(bookmarks)} bookmarks")
    else:
        feedback_parts.append(f"❌ Only {len(bookmarks)} bookmarks (need 5+)")
    
    # Criterion 2: Descriptive names (not empty, not "Bookmark X", min 3 chars)
    has_good_names = True
    bad_names = []
    
    for bm in bookmarks:
        name = bm['name']
        if (not name or 
            len(name) < 3 or 
            name.lower().startswith('bookmark') or
            name.lower() == 'untitled' or
            re.match(r'^bookmark\s*\d+$', name.lower())):
            has_good_names = False
            bad_names.append(name)
    
    if has_good_names and len(bookmarks) > 0:
        criteria_met += 1
        feedback_parts.append("✅ All bookmarks have descriptive names")
    else:
        feedback_parts.append(f"❌ Some bookmarks have generic names: {bad_names[:3]}")
    
    # Criterion 3: Well-distributed (span at least 60% of video)
    if len(bookmarks) >= 2:
        timestamps = sorted([bm['time'] for bm in bookmarks])
        span = timestamps[-1] - timestamps[0]
        span_percent = (span / video_duration) * 100
        
        if span_percent >= 60:
            criteria_met += 1
            feedback_parts.append(f"✅ Well distributed: span {span_percent:.0f}% of video")
        else:
            feedback_parts.append(f"❌ Poor distribution: only {span_percent:.0f}% span (need 60%+)")
    else:
        feedback_parts.append("❌ Too few bookmarks to check distribution")
    
    # Criterion 4: Reasonable positions (not at very edges)
    reasonable_positions = True
    edge_bookmarks = []
    
    for bm in bookmarks:
        position_percent = (bm['time'] / video_duration) * 100
        if position_percent < 2 or position_percent > 98:
            reasonable_positions = False
            edge_bookmarks.append(f"{bm['name']}@{position_percent:.1f}%")
    
    if reasonable_positions and len(bookmarks) > 0:
        criteria_met += 1
        feedback_parts.append("✅ All bookmarks at reasonable positions")
    else:
        feedback_parts.append(f"⚠️ Some bookmarks too close to edges: {edge_bookmarks[:2]}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    # Add detailed bookmark info to feedback
    if len(bookmarks) > 0:
        bookmark_summary = "; ".join([f"{bm['name']}@{bm['time']:.0f}s" for bm in bookmarks[:5]])
        feedback += f" | Bookmarks: {bookmark_summary}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "bookmark_count": len(bookmarks),
            "criteria_met": criteria_met,
            "bookmarks": bookmarks
        }
    }