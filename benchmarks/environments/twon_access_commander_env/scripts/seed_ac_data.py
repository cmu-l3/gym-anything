#!/usr/bin/env python3
"""
Seed realistic data into 2N Access Commander.

Creates user groups, time profiles, and 25 employees for a mid-size
commercial building tenant. Data reflects realistic access control needs
for an office environment: front-desk staff, engineers, contractors, and
security personnel with varied schedules and card assignments.

Usage: python3 seed_ac_data.py <ac_url> <admin_user> <admin_pass>
"""

import sys
import json
import requests
import urllib3

urllib3.disable_warnings()


def main():
    if len(sys.argv) < 4:
        print("Usage: seed_ac_data.py <url> <user> <pass>")
        sys.exit(1)

    AC_URL = sys.argv[1].rstrip("/")
    AC_USER = sys.argv[2]
    AC_PASS = sys.argv[3]

    s = requests.Session()
    s.verify = False

    # Login
    resp = s.put(f"{AC_URL}/api/v3/auth",
                 json={"login": AC_USER, "password": AC_PASS}, timeout=20)
    if resp.status_code not in (200, 201):
        print(f"ERROR: Login failed ({resp.status_code}): {resp.text[:200]}")
        sys.exit(1)
    print("Logged in to 2N Access Commander")

    # ------------------------------------------------------------------
    # 1. User groups (realistic for a corporate office building)
    # ------------------------------------------------------------------
    groups = [
        {"name": "Employees",      "description": "Full-time staff with standard access"},
        {"name": "Contractors",    "description": "Temporary contractors with limited access"},
        {"name": "Security Staff", "description": "24/7 access throughout the building"},
        {"name": "Reception Team", "description": "Front-desk and visitor management staff"},
        {"name": "IT Department",  "description": "IT staff with server room access"},
    ]
    group_ids = {}
    for g in groups:
        resp = s.post(f"{AC_URL}/api/v3/groups", json=g, timeout=15)
        if resp.status_code in (200, 201):
            gid = resp.json().get("id") or resp.json().get("groupId")
            group_ids[g["name"]] = gid
            print(f"  Created group: {g['name']} (id={gid})")
        else:
            print(f"  WARN: Could not create group '{g['name']}': {resp.status_code}")

    # ------------------------------------------------------------------
    # 2. Time profiles (standard office schedules)
    # ------------------------------------------------------------------
    time_profiles = [
        {
            "name": "Office Hours",
            "description": "Standard weekday business hours",
            "schedules": [
                {"days": ["MON","TUE","WED","THU","FRI"],
                 "timeFrom": "08:00", "timeTo": "18:00"}
            ]
        },
        {
            "name": "Extended Hours",
            "description": "Early start and late finish for senior staff",
            "schedules": [
                {"days": ["MON","TUE","WED","THU","FRI"],
                 "timeFrom": "06:00", "timeTo": "22:00"}
            ]
        },
        {
            "name": "24/7 Access",
            "description": "Unrestricted access for security staff",
            "schedules": [
                {"days": ["MON","TUE","WED","THU","FRI","SAT","SUN"],
                 "timeFrom": "00:00", "timeTo": "23:59"}
            ]
        },
        {
            "name": "Contractor Hours",
            "description": "Daytime only, no weekends",
            "schedules": [
                {"days": ["MON","TUE","WED","THU","FRI"],
                 "timeFrom": "09:00", "timeTo": "17:00"}
            ]
        },
    ]
    for tp in time_profiles:
        resp = s.post(f"{AC_URL}/api/v3/timeProfiles", json=tp, timeout=15)
        if resp.status_code in (200, 201):
            print(f"  Created time profile: {tp['name']}")
        else:
            # Try alternate endpoint
            resp2 = s.post(f"{AC_URL}/api/v3/time-profiles", json=tp, timeout=15)
            if resp2.status_code in (200, 201):
                print(f"  Created time profile: {tp['name']}")
            else:
                print(f"  WARN: Could not create time profile '{tp['name']}': {resp.status_code}")

    # ------------------------------------------------------------------
    # 3. Employees — realistic names for a mid-size tech company
    # Names drawn from diverse professional backgrounds typical of
    # commercial building tenants.
    # ------------------------------------------------------------------
    employees = [
        # Reception Team
        {"firstName": "Sandra",  "lastName": "Okafor",    "email": "s.okafor@buildingtech.com",    "phone": "+1-312-555-0142", "company": "BuildingTech Solutions", "group": "Reception Team",  "cardNumber": "0004521873"},
        {"firstName": "James",   "lastName": "Whitfield", "email": "j.whitfield@buildingtech.com",  "phone": "+1-312-555-0163", "company": "BuildingTech Solutions", "group": "Reception Team",  "cardNumber": "0004521874"},

        # Employees (general)
        {"firstName": "Priya",   "lastName": "Nair",      "email": "p.nair@buildingtech.com",       "phone": "+1-415-555-0198", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521875"},
        {"firstName": "Marcus",  "lastName": "Webb",      "email": "m.webb@buildingtech.com",       "phone": "+1-415-555-0209", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521876"},
        {"firstName": "Aaliyah", "lastName": "Thompson",  "email": "a.thompson@buildingtech.com",   "phone": "+1-415-555-0217", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521877"},
        {"firstName": "Derek",   "lastName": "Caldwell",  "email": "d.caldwell@buildingtech.com",   "phone": "+1-312-555-0224", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0013988412"},
        {"firstName": "Fatima",  "lastName": "Al-Rashid", "email": "f.alrashid@buildingtech.com",   "phone": "+1-312-555-0231", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521879"},
        {"firstName": "Carlos",  "lastName": "Mendoza",   "email": "c.mendoza@buildingtech.com",    "phone": "+1-415-555-0238", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521880"},
        {"firstName": "Yuki",    "lastName": "Tanaka",    "email": "y.tanaka@buildingtech.com",     "phone": "+1-415-555-0245", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521881"},
        {"firstName": "Rachel",  "lastName": "Goldstein", "email": "r.goldstein@buildingtech.com",  "phone": "+1-312-555-0252", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521882"},
        {"firstName": "Patrick", "lastName": "O'Brien",   "email": "p.obrien@buildingtech.com",     "phone": "+1-312-555-0259", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521883"},
        {"firstName": "Diana",   "lastName": "Flores",    "email": "d.flores@buildingtech.com",     "phone": "+1-415-555-0266", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521884"},

        # IT Department
        {"firstName": "Kwame",   "lastName": "Asante",    "email": "k.asante@buildingtech.com",     "phone": "+1-415-555-0273", "company": "BuildingTech Solutions", "group": "IT Department",   "cardNumber": "0004521885"},
        {"firstName": "Mei-Ling","lastName": "Zhang",     "email": "m.zhang@buildingtech.com",      "phone": "+1-312-555-0280", "company": "BuildingTech Solutions", "group": "IT Department",   "cardNumber": "0004521886"},

        # Security Staff
        {"firstName": "Victor",  "lastName": "Schulz",    "email": "v.schulz@secureguard.net",      "phone": "+1-773-555-0187", "company": "SecureGuard Services",   "group": "Security Staff",  "cardNumber": "0004521887"},
        {"firstName": "Tamara",  "lastName": "Kowalski",  "email": "t.kowalski@secureguard.net",    "phone": "+1-773-555-0194", "company": "SecureGuard Services",   "group": "Security Staff",  "cardNumber": "0004521888"},
        {"firstName": "Leon",    "lastName": "Fischer",   "email": "l.fischer@secureguard.net",     "phone": "+1-773-555-0201", "company": "SecureGuard Services",   "group": "Security Staff",  "cardNumber": "0007654321"},

        # Contractors
        {"firstName": "Nadia",   "lastName": "Ivanova",   "email": "n.ivanova@meridianfacilities.com","phone": "+1-847-555-0118", "company": "Meridian Facilities",    "group": "Contractors",     "cardNumber": "0004521890"},
        {"firstName": "Tomás",   "lastName": "Guerrero",  "email": "t.guerrero@meridianfacilities.com","phone": "+1-847-555-0125","company": "Meridian Facilities",    "group": "Contractors",     "cardNumber": "0004521891"},
        {"firstName": "Olumide", "lastName": "Adeyemi",   "email": "o.adeyemi@meridianfacilities.com","phone": "+1-847-555-0132", "company": "Meridian Facilities",    "group": "Contractors",     "cardNumber": "0004521892"},

        # Senior employees (for disable/update tasks)
        {"firstName": "Heather", "lastName": "Morrison",  "email": "h.morrison@buildingtech.com",   "phone": "+1-312-555-0139", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521893"},
        {"firstName": "Robert",  "lastName": "Nakamura",  "email": "r.nakamura@buildingtech.com",   "phone": "+1-415-555-0146", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521894"},
        {"firstName": "Ingrid",  "lastName": "Sorensen",  "email": "i.sorensen@buildingtech.com",   "phone": "+1-312-555-0153", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521895"},
        {"firstName": "Darnell", "lastName": "Robinson",  "email": "d.robinson@buildingtech.com",   "phone": "+1-415-555-0160", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521896"},
        {"firstName": "Aisha",   "lastName": "Patel",     "email": "a.patel@buildingtech.com",      "phone": "+1-312-555-0167", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521897"},
    ]

    created_users = {}
    for emp in employees:
        user_data = {
            "firstName": emp["firstName"],
            "lastName":  emp["lastName"],
            "email":     emp["email"],
            "phone":     emp["phone"],
            "company":   emp["company"],
            "enabled":   True,
        }
        resp = s.post(f"{AC_URL}/api/v3/users", json=user_data, timeout=15)
        if resp.status_code in (200, 201):
            uid = resp.json().get("id") or resp.json().get("userId")
            created_users[emp["email"]] = uid
            print(f"  Created user: {emp['firstName']} {emp['lastName']} (id={uid})")

            # Assign to group
            gid = group_ids.get(emp["group"])
            if gid and uid:
                s.post(f"{AC_URL}/api/v3/groups/{gid}/members",
                       json={"userId": uid}, timeout=10)

            # Assign RFID card
            if uid and emp.get("cardNumber"):
                cred_data = {"type": "card", "cardNumber": emp["cardNumber"]}
                cresp = s.post(f"{AC_URL}/api/v3/users/{uid}/credentials",
                               json=cred_data, timeout=10)
                if cresp.status_code in (200, 201):
                    print(f"    Assigned card {emp['cardNumber']}")
        else:
            print(f"  WARN: Could not create user {emp['firstName']} {emp['lastName']}: {resp.status_code}")

    print(f"\nSeeding complete: {len(created_users)} users, {len(group_ids)} groups")


if __name__ == "__main__":
    main()
