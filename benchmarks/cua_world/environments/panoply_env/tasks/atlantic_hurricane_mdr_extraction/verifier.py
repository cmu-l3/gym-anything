#!/usr/bin/env python3
"""
Verifier for atlantic_hurricane_mdr_extraction task.

Occupation: Tropical Meteorologist
Industry: National Hurricane Center
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. CSV Export (25 pts): mdr_sst_annual.csv exists, created during task, >100 bytes, contains numeric data.
  2. Map Export (15 pts): mdr_map_september.png exists, created during task, >15KB.
  3. Coordinate Accuracy (20 pts): The parsed CSV data matches expected profile for Atlantic MDR within ±0.5°C.
  4. Self-Consistent Peak Value (20 pts): PEAK_SST_VALUE in report matches the absolute maximum found within agent's own exported CSV.
  5. Self-Consistent Thresholding (20 pts): CYCLOGENESIS_MONTHS in report lists months in CSV >= 26.5°C.
"""

import json
import os
import tempfile
import math


def parse_panoply_csv(csv_text):
    """
    Parse a Panoply exported CSV to extract the time index/month and value.
    Panoply CSVs typically have a header and then data rows.
    Example line: "Jan", 25.1
    or "0", 25.1
    We will just extract all floating point numbers that look like the data column.
    """
    values = []
    lines = csv_text.strip().split('\n')
    for line in lines:
        line = line.strip()
        if not line or (line.startswith('\"') and ',' not in line):
            continue
        # Extract the last number in the comma-separated line
        parts = line.split(',')
        if len(parts) >= 2:
            val_str = parts[-1].strip()
            try:
                val = float(val_str)
                # Panoply might export NaN as "NaN"
                if not math.isnan(val):
                    values.append(val)
            except ValueError:
                pass
    return values


def verify_atlantic_hurricane_mdr_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/atlantic_hurricane_mdr_extraction_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # 1. CSV Export (25 pts)
    csv_exists = result.get('csv_exists', False)
    csv_mtime = int(result.get('csv_mtime', 0))
    csv_size = int(result.get('csv_size', 0))
    csv_content = result.get('csv_content', '')

    csv_values = parse_panoply_csv(csv_content)

    if csv_exists and csv_mtime >= task_start and csv_size >= 100 and len(csv_values) >= 12:
        score += 25
        feedback.append(f"CSV exported successfully with data ({csv_size} bytes)")
    elif csv_exists and csv_mtime >= task_start:
        score += 10
        feedback.append(f"CSV exists but may be incomplete or invalid ({csv_size} bytes, parsed {len(csv_values)} vals)")
    else:
        feedback.append(f"CSV export missing or not created during task (exists={csv_exists})")

    # 2. Map Export (15 pts)
    png_exists = result.get('png_exists', False)
    png_mtime = int(result.get('png_mtime', 0))
    png_size = int(result.get('png_size', 0))

    if png_exists and png_mtime >= task_start and png_size >= 15000:
        score += 15
        feedback.append(f"September map exported ({png_size} bytes)")
    elif png_exists and png_mtime >= task_start and png_size >= 5000:
        score += 7
        feedback.append(f"Map exported but small ({png_size} bytes)")
    else:
        feedback.append(f"Map export missing or not created during task")

    # The expected profile for NOAA OI SST v2 around 15.5N 320.5E is roughly:
    # Jan~25.5, Feb~25.1, Mar~25.1, Apr~25.6, May~26.4, Jun~27.1, Jul~27.4, Aug~27.9, Sep~28.2, Oct~28.1, Nov~27.4, Dec~26.4
    expected_peak = 28.2

    # 3. Coordinate Accuracy (20 pts)
    # If the user extracted the correct location, the peak should be around 28.2C (usually Sep)
    # and the min should be around 25.0C (usually Feb/Mar).
    actual_peak = None
    if len(csv_values) >= 12:
        actual_peak = max(csv_values)
        if abs(actual_peak - expected_peak) <= 0.5:
            score += 20
            feedback.append(f"CSV extracted data looks accurate for location (peak={actual_peak:.1f}°C)")
        else:
            feedback.append(f"CSV data extracted but values seem off for the target location (peak={actual_peak:.1f}°C, expected ~{expected_peak}°C)")
    else:
        feedback.append("Cannot verify coordinate accuracy due to missing/invalid CSV data")

    # 4. Self-Consistent Peak Value (20 pts)
    report_peak_raw = result.get('report_peak_sst_value', '').strip()
    try:
        report_peak = float(report_peak_raw)
    except ValueError:
        report_peak = None

    if report_peak is not None and actual_peak is not None:
        if abs(report_peak - actual_peak) <= 0.1:
            score += 20
            feedback.append(f"Report PEAK_SST_VALUE ({report_peak}) is consistent with CSV data")
        else:
            feedback.append(f"Report PEAK_SST_VALUE ({report_peak}) DOES NOT match CSV max ({actual_peak})")
    elif report_peak is not None:
        feedback.append(f"Report has peak value ({report_peak}) but CSV data is missing/unparseable")
    else:
        feedback.append(f"Report missing PEAK_SST_VALUE")

    # 5. Self-Consistent Thresholding (20 pts)
    # Determine which months are >= 26.5 from the agent's OWN CSV
    month_names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
    short_month_names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    
    expected_months_from_csv = []
    # If we parsed at least 12 values, assume they are Jan-Dec.
    # Take the first 12 if there are more (header might parse strangely, though unlikely)
    if len(csv_values) >= 12:
        for i, val in enumerate(csv_values[:12]):
            if val >= 26.5:
                expected_months_from_csv.append(month_names[i])
                
    report_months_raw = result.get('report_cyclogenesis_months', '').strip()
    
    if expected_months_from_csv and report_months_raw:
        report_months_lower = report_months_raw.lower()
        
        all_expected_present = all(m.lower() in report_months_lower or short_month_names[i].lower() in report_months_lower for i, m in enumerate(month_names) if m in expected_months_from_csv)
        
        unexpected_months = [m for i, m in enumerate(month_names) if m not in expected_months_from_csv and (m.lower() in report_months_lower or short_month_names[i].lower() in report_months_lower)]
        
        if all_expected_present and not unexpected_months:
            score += 20
            feedback.append(f"Report CYCLOGENESIS_MONTHS accurately reflects the CSV data threshold")
        else:
            feedback.append(f"Report CYCLOGENESIS_MONTHS does not accurately reflect the >=26.5C threshold in the CSV data")
    elif report_months_raw:
        feedback.append(f"Report has CYCLOGENESIS_MONTHS but CSV data is invalid")
    else:
        feedback.append(f"Report missing CYCLOGENESIS_MONTHS")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "csv_exists": csv_exists,
            "png_exists": png_exists,
            "csv_values": csv_values,
            "report_peak": report_peak_raw,
            "report_months": report_months_raw
        }
    }