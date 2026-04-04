#!/usr/bin/env python3
"""
Verifier for tax_lot_portfolio_tracking task.

Task: Accountant entering multiple tax lots with FIFO disposition.
Required:
  Portfolio 'Tax Lots 2024':
    BUY COST lot1: 10sh @ $638.22, Dec 1 2023,  broker $4.95, clearing $0.20, comment has 'lot 1'
    BUY COST lot2:  8sh @ $715.40, Jan 19 2024, broker $4.95, clearing $0.20, comment has 'lot 2'
    BUY META lot1: 20sh @ $367.15, Dec 15 2023, broker $4.95, clearing $0.20, comment has 'lot 1'
    BUY META lot2: 12sh @ $484.10, Jan 26 2024, broker $4.95, clearing $0.20, comment has 'lot 2'
    BUY AMZN:      30sh @ $172.35, Feb 2 2024,  broker $4.95, clearing $0.20
    SELL COST:     10sh @ $755.60, Feb 22 2024, broker $4.95
  Watchlist 'Tax Watch 2024':
    META: Fall Below $350.00, Rise Above $525.00
    AMZN: Fall Below $155.00, Rise Above $195.00
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/tax_lot_portfolio_tracking_result.json"

PRICE_TOL    = 0.15
UNITS_TOL    = 0.5
BROKER_TOL   = 0.10
CLEARING_TOL = 0.05
ALERT_TOL    = 5.0

REQUIRED_LOTS = [
    {"code": "COST", "lot": 1, "units": 10.0, "price": 638.22, "date_substr": "Dec 1, 2023",  "broker": 4.95, "clearing": 0.20, "comment_kw": "lot 1"},
    {"code": "COST", "lot": 2, "units":  8.0, "price": 715.40, "date_substr": "Jan 19, 2024", "broker": 4.95, "clearing": 0.20, "comment_kw": "lot 2"},
    {"code": "META", "lot": 1, "units": 20.0, "price": 367.15, "date_substr": "Dec 15, 2023", "broker": 4.95, "clearing": 0.20, "comment_kw": "lot 1"},
    {"code": "META", "lot": 2, "units": 12.0, "price": 484.10, "date_substr": "Jan 26, 2024", "broker": 4.95, "clearing": 0.20, "comment_kw": "lot 2"},
    {"code": "AMZN", "lot": 0, "units": 30.0, "price": 172.35, "date_substr": "Feb 2, 2024",  "broker": 4.95, "clearing": 0.20, "comment_kw": None},
]

REQUIRED_SELL = {"code": "COST", "units": 10.0, "price": 755.60, "date_substr": "Feb 22, 2024", "broker": 4.95}

REQUIRED_ALERTS = {
    "META": {"fall_below": 350.0, "rise_above": 525.0},
    "AMZN": {"fall_below": 155.0, "rise_above": 195.0},
}


def _find_lot(entries, code, lot_num):
    """Find the n-th lot (1-indexed) for a given code. lot_num=0 → last entry."""
    matches = [e for e in entries if e.get("Code", "").upper() == code.upper()]
    if not matches:
        return None
    if lot_num == 0:
        return matches[-1]
    return matches[lot_num - 1] if lot_num <= len(matches) else None


def _check_lot(entry, spec):
    """Check a buy lot. Returns (pts, max_pts=15, notes)."""
    max_pts = 15
    if not entry:
        return 0, max_pts, ["entry not found"]
    pts = 0
    notes = []

    # Units: 3 pts
    try:
        u = float(entry.get("Units", "0") or "0")
        if abs(u - spec["units"]) <= UNITS_TOL:
            pts += 3
        else:
            notes.append(f"units {u} != {spec['units']}")
    except ValueError:
        notes.append("invalid units")

    # Price: 4 pts
    try:
        p = float(entry.get("Purchase Price", "0") or "0")
        if abs(p - spec["price"]) <= PRICE_TOL:
            pts += 4
        else:
            notes.append(f"price {p:.2f} != {spec['price']:.2f}")
    except ValueError:
        notes.append("invalid price")

    # Date: 3 pts
    date_val = entry.get("Date", "")
    if spec["date_substr"].lower() in date_val.lower():
        pts += 3
    else:
        notes.append(f"date '{date_val}' != '{spec['date_substr']}'")

    # Broker: 2 pts
    try:
        b = float(entry.get("Broker", "0") or "0")
        if abs(b - spec["broker"]) <= BROKER_TOL:
            pts += 2
        else:
            notes.append(f"broker {b:.2f} != {spec['broker']:.2f}")
    except ValueError:
        notes.append("invalid broker")

    # Clearing fee: 2 pts
    try:
        c = float(entry.get("Clearing Fee", "0") or "0")
        if abs(c - spec["clearing"]) <= CLEARING_TOL:
            pts += 2
        else:
            notes.append(f"clearing {c:.2f} != {spec['clearing']:.2f}")
    except ValueError:
        notes.append("invalid clearing fee")

    # Comment keyword: 1 pt (optional, only if spec has it)
    if spec.get("comment_kw"):
        comment = entry.get("Comment", "").lower()
        if spec["comment_kw"].lower() in comment:
            pts += 1
        else:
            notes.append(f"comment missing '{spec['comment_kw']}'")

    return pts, max_pts, notes


def _check_sell(entry, spec):
    """Check the COST sell entry. Returns (pts, max_pts=12, notes)."""
    max_pts = 12
    if not entry:
        return 0, max_pts, ["COST sell entry not found"]
    pts = 0
    notes = []

    # Units: 3 pts
    try:
        u = float(entry.get("Units", "0") or "0")
        if abs(u - spec["units"]) <= UNITS_TOL:
            pts += 3
        else:
            notes.append(f"units {u} != {spec['units']}")
    except ValueError:
        notes.append("invalid units")

    # Price: 4 pts
    price_val = (entry.get("Selling Price") or entry.get("Purchase Price") or "0").strip()
    try:
        p = float(price_val)
        if abs(p - spec["price"]) <= PRICE_TOL:
            pts += 4
        else:
            notes.append(f"selling price {p:.2f} != {spec['price']:.2f}")
    except ValueError:
        notes.append(f"invalid selling price '{price_val}'")

    # Date: 3 pts
    date_val = entry.get("Date", "")
    if spec["date_substr"].lower() in date_val.lower():
        pts += 3
    else:
        notes.append(f"date '{date_val}' != '{spec['date_substr']}'")

    # Broker: 2 pts
    try:
        b = float(entry.get("Broker", "0") or "0")
        if abs(b - spec["broker"]) <= BROKER_TOL:
            pts += 2
        else:
            notes.append(f"broker {b:.2f} != {spec['broker']:.2f}")
    except ValueError:
        notes.append("invalid broker")

    return pts, max_pts, notes


def verify_tax_lot_portfolio_tracking(traj, env_info, task_info):
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
                "feedback": f"Could not read result file: {e}.",
                "subscores": {}
            }
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    # ----------------------------------------------------------------
    # GATE: portfolio must exist and have at least one buy entry
    # ----------------------------------------------------------------
    portfolio_exists = result.get("portfolio_exists", False)
    buy_count = result.get("buy_count", 0)

    if not portfolio_exists and buy_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: 'Tax Lots 2024' portfolio not created; no lot entries found.",
            "subscores": {}
        }

    total_score = 0
    feedback_parts = []
    subscores = {}

    # Portfolio exists: 3 pts
    if portfolio_exists:
        total_score += 3
        subscores["portfolio_created"] = 3
    else:
        subscores["portfolio_created"] = 0
        feedback_parts.append("Portfolio 'Tax Lots 2024': NOT CREATED")

    # Buy lots
    buy_entries = result.get("buy_entries", [])
    for spec in REQUIRED_LOTS:
        code = spec["code"]
        lot_num = spec["lot"]
        entry = _find_lot(buy_entries, code, lot_num)
        pts, max_pts, notes = _check_lot(entry, spec)
        total_score += pts
        label = f"buy_{code}_lot{lot_num}" if lot_num else f"buy_{code}"
        subscores[label] = pts
        display = f"BUY {code} lot{lot_num}" if lot_num else f"BUY {code}"
        status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
        msg = f"{display}: {status}"
        if notes:
            msg += f" ({', '.join(notes)})"
        feedback_parts.append(msg)

    # Sell COST
    cost_sell = result.get("cost_sell")
    pts, max_pts, notes = _check_sell(cost_sell, REQUIRED_SELL)
    total_score += pts
    subscores["sell_cost"] = pts
    status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
    msg = f"SELL COST: {status}"
    if notes:
        msg += f" ({', '.join(notes)})"
    feedback_parts.append(msg)

    # Watchlist alerts
    for code, alert_spec in REQUIRED_ALERTS.items():
        watch_entry = result.get(f"watch_{code.lower()}")
        fall_pts = 0
        rise_pts = 0
        fall_note = None
        rise_note = None

        if watch_entry:
            try:
                fall = float(watch_entry.get("Fall Below", "0") or "0")
                if abs(fall - alert_spec["fall_below"]) <= ALERT_TOL:
                    fall_pts = 3
                else:
                    fall_note = f"Fall Below {fall:.2f} != {alert_spec['fall_below']:.2f}"
            except (ValueError, TypeError):
                fall_note = "invalid Fall Below value"

            try:
                rise = float(watch_entry.get("Rise Above", "0") or "0")
                if abs(rise - alert_spec["rise_above"]) <= ALERT_TOL:
                    rise_pts = 3
                else:
                    rise_note = f"Rise Above {rise:.2f} != {alert_spec['rise_above']:.2f}"
            except (ValueError, TypeError):
                rise_note = "invalid Rise Above value"
        else:
            fall_note = f"{code} not in Tax Watch 2024"
            rise_note = f"{code} not in Tax Watch 2024"

        alert_pts = fall_pts + rise_pts
        total_score += alert_pts
        subscores[f"alert_{code}"] = alert_pts
        status = "PASS" if alert_pts == 6 else (f"PARTIAL {alert_pts}/6" if alert_pts > 0 else "FAIL")
        notes = [n for n in [fall_note, rise_note] if n]
        msg = f"ALERT {code}: {status}"
        if notes:
            msg += f" ({', '.join(notes)})"
        feedback_parts.append(msg)

    total_score = min(total_score, 100)
    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
