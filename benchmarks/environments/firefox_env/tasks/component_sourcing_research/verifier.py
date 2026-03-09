#!/usr/bin/env python3
"""
Verifier for component_sourcing_research task.
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

def verify_component_sourcing(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Verify Browser Activity (25 pts)
    # History check (10 pts)
    visits = result.get('digikey_visits', 0)
    if visits >= 3:
        score += 10
        feedback.append("History: Visited DigiKey product pages (10/10)")
    elif visits > 0:
        score += 5
        feedback.append(f"History: Visited DigiKey but few pages ({visits}) (5/10)")
    else:
        feedback.append("History: No evidence of visiting DigiKey products (0/10)")

    # Bookmark check (15 pts)
    if result.get('bom_folder_exists'):
        count = result.get('bom_folder_count', 0)
        if count >= 3:
            score += 15
            feedback.append(f"Bookmarks: 'BOM Research' folder has {count} items (15/15)")
        else:
            score += 10
            feedback.append(f"Bookmarks: 'BOM Research' folder exists but only {count} items (10/15)")
    else:
        feedback.append("Bookmarks: 'BOM Research' folder not found (0/15)")

    # 3. Verify PDF Datasheet (20 pts)
    if result.get('pdf_exists') and result.get('pdf_fresh'):
        size = result.get('pdf_size_bytes', 0)
        if size > 10240: # > 10KB
            score += 20
            feedback.append("Datasheet: Valid PDF downloaded (20/20)")
        else:
            score += 5
            feedback.append("Datasheet: File exists but is too small/empty (5/20)")
    else:
        feedback.append("Datasheet: File missing or not created during task (0/20)")

    # 4. Verify JSON Report (55 pts)
    json_exists = result.get('json_exists')
    json_content_str = result.get('json_content', '{}')
    
    if not json_exists:
        feedback.append("Report: JSON file missing (0/55)")
    else:
        try:
            bom = json.loads(json_content_str)
            score += 15
            feedback.append("Report: Valid JSON format (15/15)")
            
            # Content checks
            required_keys = ['ne555p', 'pn2222a', 'capacitor']
            if all(k in bom for k in required_keys):
                
                # Check NE555P (10 pts)
                ne = bom['ne555p']
                price_ne = float(ne.get('unit_price', 0))
                pn_ne = str(ne.get('digikey_part_number', ''))
                stock_ne = int(ne.get('quantity_available', 0))
                
                if stock_ne > 0 and 0.2 <= price_ne <= 5.0 and ('296-' in pn_ne or 'NE555' in pn_ne):
                    score += 10
                    feedback.append("Report: NE555P details plausible (10/10)")
                else:
                    feedback.append(f"Report: NE555P issues (Stock:{stock_ne}, Price:{price_ne}, PN:{pn_ne}) (0/10)")

                # Check PN2222A (10 pts)
                pn = bom['pn2222a']
                price_pn = float(pn.get('unit_price', 0))
                pn_pn = str(pn.get('digikey_part_number', ''))
                stock_pn = int(pn.get('quantity_available', 0))

                if stock_pn > 0 and 0.05 <= price_pn <= 2.0 and 'PN2222' in pn_pn:
                    score += 10
                    feedback.append("Report: PN2222A details plausible (10/10)")
                else:
                    feedback.append(f"Report: PN2222A issues (Stock:{stock_pn}, Price:{price_pn}, PN:{pn_pn}) (0/10)")

                # Check Capacitor (20 pts)
                cap = bom['capacitor']
                desc_cap = str(cap.get('description', '')).lower()
                price_cap = float(cap.get('unit_price', 0))
                stock_cap = int(cap.get('quantity_available', 0))
                
                # Check for 10uF (allow 10uF or 10µF)
                is_10uf = '10uf' in desc_cap or '10\u00b5f' in desc_cap or '10 u' in desc_cap
                
                if stock_cap > 0 and 0.05 <= price_cap <= 3.0 and is_10uf:
                    score += 20
                    feedback.append("Report: Capacitor selection valid (20/20)")
                else:
                    feedback.append(f"Report: Capacitor issues (Stock:{stock_cap}, Price:{price_cap}, Desc:{desc_cap}) (0/20)")
            else:
                feedback.append(f"Report: Missing required component keys. Found: {list(bom.keys())}")
                
        except json.JSONDecodeError:
            feedback.append("Report: File exists but invalid JSON (0/55)")
        except Exception as e:
            feedback.append(f"Report: validation error: {e}")

    # Final result
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }