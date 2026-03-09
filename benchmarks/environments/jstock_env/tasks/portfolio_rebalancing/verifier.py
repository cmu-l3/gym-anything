#!/usr/bin/env python3
"""
Verifier for portfolio_rebalancing task.

Task: Personal Financial Advisor rebalancing a tech-heavy client portfolio.
Required actions:
  SELL: AAPL 45 shares @ $184.15, Feb 15 2024, broker $6.95
  SELL: NVDA 12 shares @ $674.72, Feb 15 2024, broker $6.95
  BUY:  JNJ  35 shares @ $159.54, Feb 15 2024, broker $6.95
  BUY:  XOM  55 shares @ $103.87, Feb 15 2024, broker $6.95
  EXPORT: /home/ga/Desktop/rebalance_sells_feb2024.csv
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/portfolio_rebalancing_result.json"

# Required transactions
REQUIRED_SELLS = {
    "AAPL": {"units": 45.0, "price": 184.15, "date_substr": "Feb 15, 2024", "broker": 6.95},
    "NVDA": {"units": 12.0, "price": 674.72, "date_substr": "Feb 15, 2024", "broker": 6.95},
}
REQUIRED_BUYS = {
    "JNJ":  {"units": 35.0, "price": 159.54, "date_substr": "Feb 15, 2024", "broker": 6.95},
    "XOM":  {"units": 55.0, "price": 103.87, "date_substr": "Feb 15, 2024", "broker": 6.95},
}

PRICE_TOLERANCE = 0.15   # ±$0.15 per share tolerance
UNITS_TOLERANCE = 0.5    # ±0.5 shares tolerance
BROKER_TOLERANCE = 0.10  # ±$0.10 broker fee


def _find_entry_for_code(entries, code):
    """Find the most recent/last sell or buy entry for a given stock code."""
    matches = [e for e in entries if e.get("Code", "").upper() == code.upper()]
    return matches[-1] if matches else None


def _check_sell_entry(entry, spec):
    """Check if a sell entry matches the required spec. Returns (points, max_points, notes)."""
    if not entry:
        return 0, 20, ["entry not found"]
    notes = []
    pts = 0

    # Units check (10 pts)
    try:
        units = float(entry.get("Units", "0"))
        if abs(units - spec["units"]) <= UNITS_TOLERANCE:
            pts += 10
        else:
            notes.append(f"units {units} != expected {spec['units']}")
    except ValueError:
        notes.append("invalid units value")

    # Price check (5 pts) — may appear as "Selling Price" column
    price_val = (entry.get("Selling Price") or entry.get("Purchase Price") or "0").strip()
    try:
        price = float(price_val)
        if abs(price - spec["price"]) <= PRICE_TOLERANCE:
            pts += 5
        else:
            notes.append(f"price {price:.2f} != expected {spec['price']:.2f}")
    except ValueError:
        notes.append(f"invalid price '{price_val}'")

    # Date check (3 pts)
    date_val = entry.get("Date", "")
    if spec["date_substr"].lower() in date_val.lower():
        pts += 3
    else:
        notes.append(f"date '{date_val}' != '{spec['date_substr']}'")

    # Broker fee check (2 pts)
    try:
        broker = float(entry.get("Broker", "0"))
        if abs(broker - spec["broker"]) <= BROKER_TOLERANCE:
            pts += 2
        else:
            notes.append(f"broker {broker:.2f} != expected {spec['broker']:.2f}")
    except ValueError:
        notes.append("invalid broker value")

    return pts, 20, notes


def _check_buy_entry(entry, spec):
    """Check if a buy entry matches the required spec. Returns (points, max_points, notes)."""
    if not entry:
        return 0, 20, ["entry not found"]
    notes = []
    pts = 0

    # Units check (10 pts)
    try:
        units = float(entry.get("Units", "0"))
        if abs(units - spec["units"]) <= UNITS_TOLERANCE:
            pts += 10
        else:
            notes.append(f"units {units} != expected {spec['units']}")
    except ValueError:
        notes.append("invalid units value")

    # Price check (5 pts)
    price_val = entry.get("Purchase Price", "0").strip()
    try:
        price = float(price_val)
        if abs(price - spec["price"]) <= PRICE_TOLERANCE:
            pts += 5
        else:
            notes.append(f"price {price:.2f} != expected {spec['price']:.2f}")
    except ValueError:
        notes.append(f"invalid price '{price_val}'")

    # Date check (3 pts)
    date_val = entry.get("Date", "")
    if spec["date_substr"].lower() in date_val.lower():
        pts += 3
    else:
        notes.append(f"date '{date_val}' != '{spec['date_substr']}'")

    # Broker fee check (2 pts)
    try:
        broker = float(entry.get("Broker", "0"))
        if abs(broker - spec["broker"]) <= BROKER_TOLERANCE:
            pts += 2
        else:
            notes.append(f"broker {broker:.2f} != expected {spec['broker']:.2f}")
    except ValueError:
        notes.append("invalid broker value")

    return pts, 20, notes


def verify_portfolio_rebalancing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    # Load result JSON
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

    sell_entries = result.get("sell_entries", [])
    buy_entries = result.get("buy_entries", [])

    # ----------------------------------------------------------------
    # GATE: Wrong-target check — if zero sell entries AND zero NEW
    # buy entries (> 5 initial ones), the agent did nothing meaningful.
    # ----------------------------------------------------------------
    initial_buy_count = 5  # AAPL, MSFT, NVDA, JNJ, XOM
    has_sell = len(sell_entries) > 0
    has_new_buys = len(buy_entries) > initial_buy_count
    if not has_sell and not has_new_buys:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: No sell transactions recorded and no new buy transactions found. "
                        "Portfolio was not modified.",
            "subscores": {}
        }

    # ----------------------------------------------------------------
    # Score each required transaction
    # ----------------------------------------------------------------
    total_score = 0
    feedback_parts = []
    subscores = {}

    # SELL: AAPL
    aapl_sell = _find_entry_for_code(sell_entries, "AAPL")
    pts, max_pts, notes = _check_sell_entry(aapl_sell, REQUIRED_SELLS["AAPL"])
    total_score += pts
    subscores["sell_aapl"] = pts
    status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
    msg = f"SELL AAPL: {status}"
    if notes:
        msg += f" ({', '.join(notes)})"
    feedback_parts.append(msg)

    # SELL: NVDA
    nvda_sell = _find_entry_for_code(sell_entries, "NVDA")
    pts, max_pts, notes = _check_sell_entry(nvda_sell, REQUIRED_SELLS["NVDA"])
    total_score += pts
    subscores["sell_nvda"] = pts
    status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
    msg = f"SELL NVDA: {status}"
    if notes:
        msg += f" ({', '.join(notes)})"
    feedback_parts.append(msg)

    # BUY: JNJ (new lot — find entry with Feb 15 date)
    # The setup already has JNJ 40 shares (Jan 2); agent adds a new entry
    jnj_buys = [e for e in buy_entries if e.get("Code", "").upper() == "JNJ"]
    jnj_new = None
    for entry in jnj_buys:
        if "Feb 15, 2024" in entry.get("Date", ""):
            jnj_new = entry
            break
    pts, max_pts, notes = _check_buy_entry(jnj_new, REQUIRED_BUYS["JNJ"])
    total_score += pts
    subscores["buy_jnj"] = pts
    status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
    msg = f"BUY JNJ (new lot): {status}"
    if notes:
        msg += f" ({', '.join(notes)})"
    feedback_parts.append(msg)

    # BUY: XOM (new lot — find entry with Feb 15 date)
    xom_buys = [e for e in buy_entries if e.get("Code", "").upper() == "XOM"]
    xom_new = None
    for entry in xom_buys:
        if "Feb 15, 2024" in entry.get("Date", ""):
            xom_new = entry
            break
    pts, max_pts, notes = _check_buy_entry(xom_new, REQUIRED_BUYS["XOM"])
    total_score += pts
    subscores["buy_xom"] = pts
    status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
    msg = f"BUY XOM (new lot): {status}"
    if notes:
        msg += f" ({', '.join(notes)})"
    feedback_parts.append(msg)

    # Export file check (20 pts)
    export_exists = result.get("export_file_exists", False)
    export_is_new = result.get("export_file_is_new", False)
    export_size = result.get("export_file_size", 0)
    if export_exists and export_is_new and export_size > 50:
        total_score += 20
        subscores["export_file"] = 20
        feedback_parts.append("EXPORT rebalance_sells_feb2024.csv: PASS")
    elif export_exists:
        total_score += 10
        subscores["export_file"] = 10
        feedback_parts.append("EXPORT: file exists but may be stale or empty")
    else:
        subscores["export_file"] = 0
        feedback_parts.append("EXPORT rebalance_sells_feb2024.csv: FAIL (file not found on Desktop)")

    total_score = min(total_score, 100)
    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
