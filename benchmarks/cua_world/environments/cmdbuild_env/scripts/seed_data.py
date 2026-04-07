#!/usr/bin/env python3
"""Seed CMDBuild with realistic IT infrastructure data.

Uses real-world server models, serial number formats, and network configurations
based on publicly available Dell, HP, and Cisco product specifications.
"""

import sys
import json
import time

sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *


def wait_for_api(timeout=300):
    """Wait until the CMDBuild REST API is fully available."""
    elapsed = 0
    while elapsed < timeout:
        try:
            resp = api("GET", "classes?limit=1", "basic")
            if resp and resp.get("data") is not None:
                return True
        except Exception:
            pass
        time.sleep(5)
        elapsed += 5
        print(f"  Waiting for API... {elapsed}s", file=sys.stderr)
    return False


def discover_classes(token):
    """Discover available CI classes in the empty CMDBuild schema."""
    classes = list_classes(token)
    class_map = {}
    for c in classes:
        name = c.get("_id", "")
        desc = c.get("description", "")
        prototype = c.get("prototype", False)
        active = c.get("active", True)
        if active:
            class_map[name] = {
                "description": desc,
                "prototype": prototype,
                "parent": c.get("parent", "")
            }
    return class_map


def find_usable_class(class_map, preferred_names):
    """Find the first usable (non-prototype) class from a list of names."""
    for name in preferred_names:
        if name in class_map and not class_map[name].get("prototype", False):
            return name
    # Fallback: search by pattern
    for name, info in class_map.items():
        if not info.get("prototype", False):
            for pref in preferred_names:
                if pref.lower() in name.lower() or pref.lower() in info.get("description", "").lower():
                    return name
    return None


def seed_servers(server_cls, token):
    """Seed realistic server CI records based on real Dell/HP/Cisco product lines."""
    servers = [
        {
            "Code": "SRV-PDC-001",
            "Description": "Dell PowerEdge R760 - Primary Domain Controller",
            "SerialNumber": "CN-0HRPG2-74261-4B7-03KJ",
            "Notes": "Rack A3 U12-14, PDU-A Port 8, iDRAC 10.20.30.41, 2x Xeon Gold 6430 / 256GB DDR5 / 4x 960GB SSD RAID10"
        },
        {
            "Code": "SRV-SQL-002",
            "Description": "HP ProLiant DL380 Gen10 Plus - SQL Server Cluster Node 1",
            "SerialNumber": "MXL2431HPC",
            "Notes": "Rack B1 U22-24, PDU-B Port 12, iLO 10.20.30.52, 2x Xeon Silver 4314 / 512GB DDR4 / 8x 2.4TB SAS RAID10"
        },
        {
            "Code": "SRV-WEB-003",
            "Description": "Dell PowerEdge R650 - Web Application Server",
            "SerialNumber": "FXTK4N3",
            "Notes": "Rack A1 U5-6, PDU-A Port 3, iDRAC 10.20.30.33, 2x Xeon Gold 5318Y / 128GB DDR4 / 2x 480GB SSD RAID1"
        },
        {
            "Code": "SRV-BKP-004",
            "Description": "Dell PowerEdge R640 - Backup and Recovery Server",
            "SerialNumber": "USE413KR9F",
            "Notes": "Rack C2 U1-2, PDU-C Port 1, iDRAC 10.20.30.64, 2x Xeon Silver 4210R / 64GB DDR4 / 12x 4TB SATA RAID6"
        },
        {
            "Code": "SRV-APP-005",
            "Description": "Cisco UCS C220 M6 - Application Server",
            "SerialNumber": "CZJ4130BYN",
            "Notes": "Rack A2 U15-16, PDU-A Port 10, CIMC 10.20.30.45, 2x Xeon Gold 6326 / 256GB DDR4 / 4x 1.92TB NVMe"
        },
        {
            "Code": "SRV-MON-006",
            "Description": "HP ProLiant DL360 Gen10 - Monitoring Server (Nagios/Grafana)",
            "SerialNumber": "MXL3012KBV",
            "Notes": "Rack B2 U8, PDU-B Port 5, iLO 10.20.30.56, 1x Xeon Silver 4208 / 64GB DDR4 / 2x 960GB SSD RAID1"
        },
        {
            "Code": "SRV-DEV-007",
            "Description": "Dell PowerEdge T640 - Development and Test Server",
            "SerialNumber": "8GKNP23",
            "Notes": "Lab Room B, Floor-standing, iDRAC 10.20.31.10, 2x Xeon Silver 4210 / 128GB DDR4 / 4x 2TB SATA RAID5"
        },
        {
            "Code": "SRV-FW-008",
            "Description": "Dell PowerEdge R450 - File and Print Server",
            "SerialNumber": "JXPW9M3",
            "Notes": "Rack A1 U3-4, PDU-A Port 2, iDRAC 10.20.30.32, 1x Xeon E-2334 / 32GB DDR4 / 8x 8TB SATA RAID6"
        },
    ]

    created_ids = {}
    for srv in servers:
        existing = get_cards(server_cls, token, limit=200)
        found = None
        for c in existing:
            if c.get("Code", "") == srv["Code"]:
                found = c
                break

        if found:
            print(f"  Server {srv['Code']} already exists (id={found['_id']})")
            created_ids[srv["Code"]] = found["_id"]
        else:
            # Retry up to 5 times with increasing delay
            card_id = None
            for attempt in range(5):
                card_id = create_card(server_cls, srv, token)
                if card_id:
                    break
                delay = 3 * (attempt + 1)
                print(f"  Retry {attempt+1}/5 for {srv['Code']} (waiting {delay}s)...")
                time.sleep(delay)
            if card_id:
                print(f"  Created server {srv['Code']} (id={card_id})")
                created_ids[srv["Code"]] = card_id
            else:
                print(f"  FAILED to create server {srv['Code']}")
        time.sleep(1)  # Brief pause between creates to avoid API overload

    return created_ids


def main():
    print("=== Seeding CMDBuild with IT infrastructure data ===")

    print("Waiting for CMDBuild API...")
    if not wait_for_api(300):
        print("ERROR: CMDBuild API not available after 300s", file=sys.stderr)
        sys.exit(1)

    token = get_token()
    if not token:
        print("ERROR: Authentication failed", file=sys.stderr)
        sys.exit(1)

    print("Discovering classes...")
    class_map = discover_classes(token)
    print(f"  Found {len(class_map)} classes")

    # Print all non-prototype classes for diagnostics
    print("  Available non-prototype classes:")
    for name, info in sorted(class_map.items()):
        if not info.get("prototype", False):
            print(f"    {name}: {info['description']}")

    # Find server-related class
    server_cls = find_usable_class(class_map, [
        "Server", "InternalServer", "VirtualServer", "PhysicalServer",
        "Computer", "CI", "Hardware", "Asset", "NetworkDevice"
    ])

    if not server_cls:
        print("WARNING: No suitable CI class found. Available classes:")
        for name, info in class_map.items():
            if not info.get("prototype"):
                print(f"  {name}: {info['description']}")
        # Use first non-prototype class as fallback
        for name, info in class_map.items():
            if not info.get("prototype"):
                server_cls = name
                break

    if not server_cls:
        print("ERROR: No usable class found at all", file=sys.stderr)
        sys.exit(1)

    print(f"\nUsing class: {server_cls}")

    # Show attributes for this class
    attrs = get_class_attributes(server_cls, token)
    print(f"  Attributes ({len(attrs)}):")
    for a in attrs:
        aname = a.get("_id", "") or a.get("name", "")
        atype = a.get("type", "")
        mandatory = a.get("mandatory", False)
        print(f"    {aname} ({atype}){' [REQUIRED]' if mandatory else ''}")

    # Seed servers
    print("\nSeeding server records...")
    created_ids = seed_servers(server_cls, token)

    # Save seed data metadata
    seed_info = {
        "server_class": server_cls,
        "server_ids": created_ids,
        "class_map": {k: v for k, v in class_map.items() if not v.get("prototype")}
    }

    with open("/tmp/seed_data_info.json", "w") as f:
        json.dump(seed_info, f, indent=2)

    print(f"\n=== Seeding complete: {len(created_ids)} servers created ===")


if __name__ == "__main__":
    main()
