#!/usr/bin/env python3
"""
Verifier for multi_sector_watchlist_setup task.

Task: Securities Sales Agent setting up 3 sector watchlists with precise alerts.
Required watchlists:
  Technology_Coverage: AAPL(170/200), GOOGL(125/155), MSFT(355/410)
  Healthcare_Coverage: JNJ(145/175), UNH(495/565), PFE(22/32)
  Energy_Coverage:     XOM(95/120), CVX(140/168), COP(100/128)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/multi_sector_watchlist_setup_result.json"

ALERT_TOLERANCE = 2.0  # ±$2.00 per alert value

REQUIRED = {
    "Technology_Coverage": {
        "AAPL":  {"fall_below": 170.0, "rise_above": 200.0},
        "GOOGL": {"fall_below": 125.0, "rise_above": 155.0},
        "MSFT":  {"fall_below": 355.0, "rise_above": 410.0},
    },
    "Healthcare_Coverage": {
        "JNJ": {"fall_below": 145.0, "rise_above": 175.0},
        "UNH": {"fall_below": 495.0, "rise_above": 565.0},
        "PFE": {"fall_below":  22.0, "rise_above":  32.0},
    },
    "Energy_Coverage": {
        "XOM": {"fall_below":  95.0, "rise_above": 120.0},
        "CVX": {"fall_below": 140.0, "rise_above": 168.0},
        "COP": {"fall_below": 100.0, "rise_above": 128.0},
    },
}

# Points per watchlist: exists=5, per-stock=4, per-fall_below=3, per-rise_above=3
# Max per watchlist: 5 + 3*(4+3+3) = 5 + 30 = 35 pts  →  3 watchlists = 105 (capped at 100)


def _check_alert(entry, field, target, tol=ALERT_TOLERANCE):
    """Return (pts, note). pts=3 if correct, 0 otherwise."""
    if not entry:
        return 0, f"{field} entry missing"
    try:
        val = float(entry.get(field, "0") or "0")
        if abs(val - target) <= tol:
            return 3, None
        else:
            return 0, f"{field}={val:.2f} != expected {target:.2f}"
    except (ValueError, TypeError):
        return 0, f"invalid {field} value '{entry.get(field)}'"


def _check_watchlist(watchlist_key, entries_key, result):
    """Score one watchlist. Returns (pts, max_pts, parts)."""
    spec = REQUIRED[watchlist_key]
    parts = []
    pts = 0
    max_pts = 5 + len(spec) * 10  # 5 exists + per stock: 4+3+3=10

    # Watchlist exists
    if result.get(f"{entries_key}_watchlist_exists"):
        pts += 5
    else:
        parts.append(f"{watchlist_key}: MISSING (watchlist not created)")
        return pts, max_pts, parts

    # Per-stock checks
    entries = result.get(f"{entries_key}_entries", [])
    existing_codes = {e.get("Code", "").upper() for e in entries}

    for code, alert_spec in spec.items():
        # Find entry
        entry = next((e for e in entries if e.get("Code", "").upper() == code), None)

        # Stock present: 4 pts
        if entry is not None:
            pts += 4
        else:
            parts.append(f"{watchlist_key}/{code}: NOT in watchlist")
            continue

        # Fall Below alert: 3 pts
        fall_pts, fall_note = _check_alert(entry, "Fall Below", alert_spec["fall_below"])
        pts += fall_pts
        if fall_note:
            parts.append(f"{watchlist_key}/{code} Fall Below: {fall_note}")

        # Rise Above alert: 3 pts
        rise_pts, rise_note = _check_alert(entry, "Rise Above", alert_spec["rise_above"])
        pts += rise_pts
        if rise_note:
            parts.append(f"{watchlist_key}/{code} Rise Above: {rise_note}")

    return pts, max_pts, parts


def verify_multi_sector_watchlist_setup(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    result = {}
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r", encoding="utf-8") as f:
                result = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load result JSON: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read result file: {e}. Agent may not have completed the task.",
                "subscores": {}
            }
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    # ----------------------------------------------------------------
    # GATE: if none of the 3 sector watchlists were created → score 0
    # ----------------------------------------------------------------
    tech_exists = result.get("tech_watchlist_exists", False)
    health_exists = result.get("health_watchlist_exists", False)
    energy_exists = result.get("energy_watchlist_exists", False)

    if not tech_exists and not health_exists and not energy_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: No sector watchlists created. "
                        "Technology_Coverage, Healthcare_Coverage, and Energy_Coverage are all missing.",
            "subscores": {}
        }

    # ----------------------------------------------------------------
    # Score each watchlist
    # ----------------------------------------------------------------
    total_score = 0
    feedback_parts = []
    subscores = {}

    for wl_key, entries_key in [
        ("Technology_Coverage", "tech"),
        ("Healthcare_Coverage", "health"),
        ("Energy_Coverage", "energy"),
    ]:
        pts, max_pts, parts = _check_watchlist(wl_key, entries_key, result)
        total_score += pts
        subscores[wl_key] = pts
        status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
        msg = f"{wl_key}: {status}"
        if parts:
            msg += " | " + "; ".join(parts)
        feedback_parts.append(msg)

    total_score = min(total_score, 100)
    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " || ".join(feedback_parts),
        "subscores": subscores,
    }
