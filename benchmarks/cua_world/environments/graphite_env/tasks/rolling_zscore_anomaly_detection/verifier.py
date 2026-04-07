#!/usr/bin/env python3
"""
Verifier for rolling_zscore_anomaly_detection task.
"""

import json
import os
import re
import tempfile

DASHBOARD_NAME = "Statistical Traffic Z-Score"
RESULT_PATH = "/tmp/rolling_zscore_anomaly_detection_result.json"
METRIC_NAME = "servers.web_traffic.speed_sensor_1"


def _get_graphs(dashboard_state):
    """Return list of (title, targets_list) from dashboard state dict."""
    graphs = []
    raw_graphs = dashboard_state.get("graphs", [])
    for entry in raw_graphs:
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        params = entry[1] if isinstance(entry[1], dict) else {}
        title = params.get("title", "")
        targets = params.get("target", [])
        if isinstance(targets, str):
            targets = [targets]
        graphs.append((title, [str(t) for t in targets]))
    return graphs


def verify_rolling_zscore_anomaly_detection(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    details = []

    # 1. Read exported result from container
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load result file: {e}",
        }

    dashboards = result.get("dashboards", {})

    # 2. Check for expected dashboard presence (10 pts)
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Dashboard '{DASHBOARD_NAME}' not found. "
                f"Present: {list(dashboards.keys())}"
            ),
        }
    
    score += 10
    details.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")

    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}",
        }

    graphs = _get_graphs(dashboard_state)
    
    # 3. Identify graphs by title
    baseline_graph = None
    volatility_graph = None
    zscore_graph = None
    
    for title, targets in graphs:
        tl = title.lower()
        if "baseline" in tl:
            baseline_graph = targets
        elif "volatility" in tl:
            volatility_graph = targets
        elif "z-score" in tl or "zscore" in tl:
            zscore_graph = targets

    # 4. Baseline Graph (15 pts)
    if baseline_graph is not None:
        has_raw = False
        has_ma = False
        for t in baseline_graph:
            t_low = t.lower()
            if METRIC_NAME.lower() in t_low:
                if "movingaverage" in t_low:
                    has_ma = True
                elif "diffseries" not in t_low and "divideseries" not in t_low:
                    has_raw = True
        
        if has_raw and has_ma:
            score += 15
            details.append("[+15] Baseline Graph contains raw metric and movingAverage")
        elif has_ma:
            score += 10
            details.append("[+10] Baseline Graph contains movingAverage but maybe missing raw metric")
        else:
            details.append("[-] Baseline Graph missing movingAverage")
    else:
        details.append("[-] Baseline Graph not found")

    # 5. Volatility Graph (15 pts)
    if volatility_graph is not None:
        has_stddev = False
        for t in volatility_graph:
            if "movingstddev" in t.lower() and METRIC_NAME.lower() in t.lower():
                has_stddev = True
        if has_stddev:
            score += 15
            details.append("[+15] Volatility Graph contains movingStdDev")
        else:
            details.append("[-] Volatility Graph missing movingStdDev")
    else:
        details.append("[-] Volatility Graph not found")

    # 6. Z-Score Graph (Numerator 20, Denominator 25, Thresholds 15)
    if zscore_graph is not None:
        has_numerator = False
        has_denominator = False
        has_thresh_pos = False
        has_thresh_neg = False
        
        for t in zscore_graph:
            t_low = t.lower().replace(' ', '')
            
            # Check thresholds (accepts both threshold(3) and threshold(3, "+3 Sigma"))
            if "threshold" in t_low:
                if re.search(r'threshold\(\s*3\s*[,)]', t_low):
                    has_thresh_pos = True
                if re.search(r'threshold\(\s*-3\s*[,)]', t_low):
                    has_thresh_neg = True

            # Check Logic Construct (X - μ) / σ
            if "diffseries" in t_low and "movingaverage" in t_low and METRIC_NAME.lower() in t_low:
                has_numerator = True
            elif "scale(" in t_low and "-1" in t_low and "movingaverage" in t_low: # Fallback math
                has_numerator = True
                
            if "divideseries" in t_low and "movingstddev" in t_low and METRIC_NAME.lower() in t_low:
                has_denominator = True
                
        if has_numerator:
            score += 20
            details.append("[+20] Z-Score Graph constructs the numerator (X - μ)")
        else:
            details.append("[-] Z-Score Graph missing proper numerator logic via diffSeries")
            
        if has_denominator:
            score += 25
            details.append("[+25] Z-Score Graph constructs the denominator and divides by σ")
        else:
            details.append("[-] Z-Score Graph missing proper denominator logic via divideSeries/movingStdDev")
            
        if has_thresh_pos and has_thresh_neg:
            score += 15
            details.append("[+15] Z-Score Graph includes both +3 and -3 thresholds")
        elif has_thresh_pos or has_thresh_neg:
            score += 7
            details.append("[+7] Z-Score Graph includes at least one threshold line")
        else:
            details.append("[-] Z-Score Graph missing +3 and -3 thresholds")
    else:
        details.append("[-] Live Z-Score Graph not found")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }