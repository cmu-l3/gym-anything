#!/usr/bin/env python3
"""Verifier for inventory_network_expansion_scconfig task.

A seismologist must import a new seismic network (IU) inventory from FDSN
StationXML, convert and load it into SeisComP, configure station bindings
for the new stations, and verify the expanded network.

Scoring:
- 25 pts: IU network and all 3 stations imported into database
- 15 pts: Inventory file copied to etc/inventory/ for scconfig
- 30 pts: scautopick bindings configured for all 3 IU stations
- 15 pts: scamp bindings configured for all 3 IU stations
- 15 pts: Inventory listing file exists with IU network info

Wrong-target guard: If no IU stations in DB and no bindings, return 0.
"""

import json
import os
import tempfile


def verify_inventory_network_expansion_scconfig(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "inventory_network_expansion_scconfig"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(result_path, tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {e}",
        }

    def _bool(v):
        if isinstance(v, bool):
            return v
        return str(v).lower() == "true"

    iu_network_in_db = _bool(result.get("iu_network_in_db", False))
    iu_stations_in_db = int(result.get("iu_stations_in_db", 0))
    inventory_file_in_etc = _bool(result.get("inventory_file_in_etc", False))
    stations_with_scautopick = int(result.get("stations_with_scautopick", 0))
    stations_with_scamp = int(result.get("stations_with_scamp", 0))
    listing_exists = _bool(result.get("listing_exists", False))
    listing_has_iu = _bool(result.get("listing_has_iu", False))

    # ── Do-nothing guard ───────────────────────────────────────────────────
    if iu_stations_in_db == 0 and stations_with_scautopick == 0 and not listing_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No changes detected. IU stations not in database, no bindings configured, "
                "no inventory listing. The agent must convert StationXML with fdsnxml2inv, "
                "import with scdb, configure bindings in scconfig, and run scinv ls."
            ),
        }

    score = 0
    parts = []

    # ── Criterion 1 (25 pts): IU stations imported ───────────────────────
    if iu_network_in_db and iu_stations_in_db >= 3:
        score += 25
        parts.append(f"IU network + {iu_stations_in_db} stations imported to DB (25/25)")
    elif iu_network_in_db and iu_stations_in_db >= 1:
        pts = 10 + iu_stations_in_db * 5
        score += pts
        parts.append(
            f"IU network in DB but only {iu_stations_in_db}/3 stations ({pts}/25)"
        )
    elif iu_stations_in_db >= 1:
        score += iu_stations_in_db * 5
        parts.append(
            f"Stations found but IU network record missing ({iu_stations_in_db * 5}/25)"
        )
    else:
        parts.append("IU network not imported into database (0/25)")

    # ── Criterion 2 (15 pts): Inventory file in etc/inventory/ ───────────
    if inventory_file_in_etc:
        score += 15
        parts.append("Inventory file copied to etc/inventory/ (15/15)")
    else:
        parts.append("Inventory file not in etc/inventory/ — scconfig won't see it (0/15)")

    # ── Criterion 3 (30 pts): scautopick bindings ────────────────────────
    if stations_with_scautopick >= 3:
        score += 30
        parts.append(f"scautopick bindings on all {stations_with_scautopick} IU stations (30/30)")
    elif stations_with_scautopick >= 1:
        pts = stations_with_scautopick * 10
        score += pts
        parts.append(
            f"scautopick on {stations_with_scautopick}/3 IU stations ({pts}/30)"
        )
    else:
        parts.append("No scautopick bindings for IU stations (0/30)")

    # ── Criterion 4 (15 pts): scamp bindings ─────────────────────────────
    if stations_with_scamp >= 3:
        score += 15
        parts.append(f"scamp bindings on all {stations_with_scamp} IU stations (15/15)")
    elif stations_with_scamp >= 1:
        pts = stations_with_scamp * 5
        score += pts
        parts.append(
            f"scamp on {stations_with_scamp}/3 IU stations ({pts}/15)"
        )
    else:
        parts.append("No scamp bindings for IU stations (0/15)")

    # ── Criterion 5 (15 pts): Inventory listing file ─────────────────────
    if listing_exists and listing_has_iu:
        score += 15
        parts.append("Inventory listing with IU network info (15/15)")
    elif listing_exists:
        score += 5
        parts.append("Inventory listing exists but doesn't mention IU (5/15)")
    else:
        parts.append(
            "No inventory listing at /home/ga/Desktop/network_inventory.txt (0/15)"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
