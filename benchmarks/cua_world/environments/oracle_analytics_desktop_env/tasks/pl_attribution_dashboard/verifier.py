#!/usr/bin/env python3
"""
Verifier for pl_attribution_dashboard task.

Scoring breakdown (100 pts total):
  20 pts - DVA workbook file exists and was created after task start
  15 pts - File is a valid ZIP archive (proper .dva structure)
  15 pts - Canvas 'Segment Profitability' present in workbook
  15 pts - Canvas 'Category Margin Analysis' present in workbook
  15 pts - Canvas 'Unit Economics' present in workbook
  10 pts - Calculated column 'Profit_Margin_Pct' defined in workbook
  10 pts - Calculated column 'Net_Profit_Per_Unit' defined in workbook
"""

import json
import logging
import os
import re
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\pl_attribution_dashboard_result.json"


def _load_dva_json_text(dva_path):
    """Unzip a .dva file and return the concatenated text of all JSON and .arc files inside."""
    if not zipfile.is_zipfile(dva_path):
        return None, "File is not a valid ZIP archive"
    import zlib
    all_text = []
    try:
        with zipfile.ZipFile(dva_path, 'r') as zf:
            for name in zf.namelist():
                data = zf.read(name)
                if name.lower().endswith('.json'):
                    try:
                        all_text.append(data.decode('utf-8', errors='replace'))
                    except Exception:
                        pass
                elif name.lower().endswith('.arc'):
                    try:
                        decompressed = zlib.decompress(data)
                        all_text.append(decompressed.decode('utf-8', errors='replace'))
                    except Exception:
                        pass
        return '\n'.join(all_text), None
    except Exception as e:
        return None, str(e)


def verify_pl_attribution_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Step 1: Read result JSON from VM
    result = {}
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, tmp_json.name)
        with open(tmp_json.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp_json.name)
        except Exception:
            pass

    dva_info = result.get('dva_file', {})
    if not isinstance(dva_info, dict):
        dva_info = {}

    score = 0
    feedback_parts = []

    # Check 1: DVA file exists and is new (20 pts)
    if dva_info.get('exists') and dva_info.get('is_new'):
        score += 20
        feedback_parts.append("Workbook file created after task start (+20)")
    elif dva_info.get('exists') and not dva_info.get('is_new'):
        feedback_parts.append("Workbook file found but predates task start (0)")
    else:
        feedback_parts.append("Workbook file not found (0)")
        return {"passed": False, "score": 0,
                "feedback": " | ".join(feedback_parts)}

    dva_remote_path = dva_info.get('path', '')
    if not dva_remote_path:
        feedback_parts.append("No DVA path recorded")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Step 2: Copy the .dva file and inspect its contents
    tmp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    try:
        copy_from_env(dva_remote_path, tmp_dva.name)
    except Exception as e:
        feedback_parts.append(f"Could not copy DVA file: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        pass

    try:
        json_text, err = _load_dva_json_text(tmp_dva.name)
        if err or json_text is None:
            feedback_parts.append(f"DVA is not a valid ZIP/DVA structure: {err}")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Check 2: Valid ZIP structure (15 pts)
        score += 15
        feedback_parts.append("DVA file is valid ZIP archive (+15)")

        text_lower = json_text.lower()

        # Check 3: Canvas 'Segment Profitability' (15 pts)
        if 'segment profitability' in text_lower:
            score += 15
            feedback_parts.append("Canvas 'Segment Profitability' found (+15)")
        else:
            feedback_parts.append("Canvas 'Segment Profitability' NOT found (0)")

        # Check 4: Canvas 'Category Margin Analysis' (15 pts)
        if 'category margin analysis' in text_lower:
            score += 15
            feedback_parts.append("Canvas 'Category Margin Analysis' found (+15)")
        else:
            feedback_parts.append("Canvas 'Category Margin Analysis' NOT found (0)")

        # Check 5: Canvas 'Unit Economics' (15 pts)
        if 'unit economics' in text_lower:
            score += 15
            feedback_parts.append("Canvas 'Unit Economics' found (+15)")
        else:
            feedback_parts.append("Canvas 'Unit Economics' NOT found (0)")

        # Check 6: Calculated column 'Profit_Margin_Pct' (10 pts)
        if 'profit_margin_pct' in text_lower or 'profit_margin_pct' in json_text:
            score += 10
            feedback_parts.append("Calculated column 'Profit_Margin_Pct' found (+10)")
        else:
            feedback_parts.append("Calculated column 'Profit_Margin_Pct' NOT found (0)")

        # Check 7: Calculated column 'Net_Profit_Per_Unit' (10 pts)
        if 'net_profit_per_unit' in text_lower or 'net_profit_per_unit' in json_text:
            score += 10
            feedback_parts.append("Calculated column 'Net_Profit_Per_Unit' found (+10)")
        else:
            feedback_parts.append("Calculated column 'Net_Profit_Per_Unit' NOT found (0)")

    finally:
        try:
            os.unlink(tmp_dva.name)
        except Exception:
            pass

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
