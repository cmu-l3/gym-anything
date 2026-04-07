#!/usr/bin/env python3
"""
Seed realistic data into 2N Access Commander v3.5.2.

Creates companies, user groups, time profiles, and 25 employees for a
mid-size commercial building tenant. Data reflects realistic access control
needs for an office environment: front-desk staff, engineers, contractors,
and security personnel with varied schedules and card assignments.

Authentication flow handled automatically:
  - Fresh install: login with default password → change password → accept EULA
  - Already configured: login with new password directly

Usage: python3 seed_ac_data.py <ac_url> <admin_user> <admin_pass>
  <admin_pass> should be the DEFAULT password (e.g. "2n").
  The script will change it to Admin2n1! on first-time setup, or try
  Admin2n1! directly if the default password no longer works.
"""

import sys
import json
import requests
import urllib3

urllib3.disable_warnings()

NEW_PASSWORD = "Admin2n1!"


# ---------------------------------------------------------------------------
# Authentication helpers
# ---------------------------------------------------------------------------

def login(s, ac_url, user, password):
    """PUT /api/v3/login and return the response."""
    return s.put(f"{ac_url}/api/v3/login",
                 json={"login": user, "password": password}, timeout=20)


def change_onetime_password(s, ac_url, user_id, old_pw, new_pw):
    """PUT /api/v3/users/{id}/changeonetimepassword → 210."""
    return s.put(
        f"{ac_url}/api/v3/users/{user_id}/changeonetimepassword",
        json={"OldPassword": old_pw, "NewPassword": new_pw},
        timeout=20,
    )


def accept_eula(s, ac_url):
    """PUT /api/v3/system/eula with body true → 204."""
    return s.put(f"{ac_url}/api/v3/system/eula", json=True, timeout=20)


def do_login(s, ac_url, user, default_pass):
    """
    Full authentication flow for v3.5.2.

    Returns True on success, exits on unrecoverable failure.

    Sequence:
      1. Try login with default_pass.
         - 200  → already configured, done.
         - 412  → first-time setup: change password, re-login, accept EULA.
         - other → try NEW_PASSWORD in case setup was already done.
      2. On 412 (first-time):
         a. Change one-time password (default_pass → NEW_PASSWORD).
         b. Re-login with NEW_PASSWORD.
         c. If 406 (EULA required) → accept EULA → re-login.
         d. Expect 200.
    """
    resp = login(s, ac_url, user, default_pass)

    if resp.status_code == 200:
        print("Logged in to 2N Access Commander (existing session)")
        return True

    if resp.status_code == 412:
        # First-time setup: server returns user info in the body
        body = resp.json()
        user_id = body.get("Id")
        print(f"First-time setup detected (user id={user_id}). Changing password …")

        chg = change_onetime_password(s, ac_url, user_id, default_pass, NEW_PASSWORD)
        if chg.status_code != 210:
            print(f"ERROR: changeonetimepassword returned {chg.status_code}: {chg.text[:200]}")
            sys.exit(1)
        print("Password changed successfully.")

        # Re-login with new password
        resp2 = login(s, ac_url, user, NEW_PASSWORD)
        if resp2.status_code == 406:
            # EULA required
            print("EULA acceptance required. Accepting …")
            eula = accept_eula(s, ac_url)
            if eula.status_code not in (200, 204):
                print(f"WARN: EULA acceptance returned {eula.status_code}: {eula.text[:200]}")
            resp2 = login(s, ac_url, user, NEW_PASSWORD)

        if resp2.status_code == 200:
            print("Logged in to 2N Access Commander (first-time setup complete)")
            return True

        print(f"ERROR: Login after password change failed ({resp2.status_code}): {resp2.text[:200]}")
        sys.exit(1)

    # Default password did not work — maybe setup was already done previously
    print(f"Login with default password failed ({resp.status_code}). Trying '{NEW_PASSWORD}' …")
    resp3 = login(s, ac_url, user, NEW_PASSWORD)

    if resp3.status_code == 406:
        print("EULA acceptance required. Accepting …")
        accept_eula(s, ac_url)
        resp3 = login(s, ac_url, user, NEW_PASSWORD)

    if resp3.status_code == 200:
        print("Logged in to 2N Access Commander (using existing new password)")
        return True

    print(f"ERROR: All login attempts failed. Last status: {resp3.status_code}: {resp3.text[:200]}")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

def get_existing(s, ac_url, endpoint, name_field="Name"):
    """
    Fetch all entities from a list endpoint and return a dict of name→id.
    Handles both plain arrays and {items: [...], count: N} responses.
    """
    resp = s.get(f"{ac_url}{endpoint}", timeout=15)
    if resp.status_code != 200:
        return {}
    data = resp.json()
    items = data.get("items", data) if isinstance(data, dict) else data
    return {item[name_field]: item["Id"] for item in items if name_field in item and "Id" in item}


# ---------------------------------------------------------------------------
# Entity creation helpers (idempotent — skip if already exists)
# ---------------------------------------------------------------------------

def ensure_companies(s, ac_url, company_names):
    """Create companies that do not already exist. Returns name→id dict."""
    existing = get_existing(s, ac_url, "/api/v3/companies")
    ids = dict(existing)
    for name in company_names:
        if name in existing:
            print(f"  Company already exists: {name} (id={existing[name]})")
            continue
        resp = s.post(f"{ac_url}/api/v3/companies", json={"Name": name}, timeout=15)
        if resp.status_code in (200, 201):
            cid = resp.json().get("Id")
            ids[name] = cid
            print(f"  Created company: {name} (id={cid})")
        else:
            print(f"  WARN: Could not create company '{name}': {resp.status_code} {resp.text[:120]}")
    return ids


def ensure_groups(s, ac_url, groups, company_ids):
    """
    Create groups that do not already exist.
    Each group dict: {name, description, company}.
    Returns name→id dict.
    """
    existing = get_existing(s, ac_url, "/api/v3/groups")
    ids = dict(existing)
    for g in groups:
        if g["name"] in existing:
            print(f"  Group already exists: {g['name']} (id={existing[g['name']]})")
            continue
        company_id = company_ids.get(g["company"])
        body = {
            "Name": g["name"],
            "Description": g["description"],
        }
        if company_id is not None:
            body["Company"] = {"Id": company_id}
        resp = s.post(f"{ac_url}/api/v3/groups", json=body, timeout=15)
        if resp.status_code in (200, 201):
            gid = resp.json().get("Id")
            ids[g["name"]] = gid
            print(f"  Created group: {g['name']} (id={gid})")
        else:
            print(f"  WARN: Could not create group '{g['name']}': {resp.status_code} {resp.text[:120]}")
    return ids


def _make_time_profile_body(tp):
    """
    Convert our internal time-profile description into the v3.5.2 per-day body.

    tp["schedules"] is a list of {days: [...abbrev...], timeFrom, timeTo}.
    Days use 3-letter abbreviations: MON, TUE, WED, THU, FRI, SAT, SUN.
    """
    day_map = {
        "MON": "Monday", "TUE": "Tuesday", "WED": "Wednesday",
        "THU": "Thursday", "FRI": "Friday", "SAT": "Saturday", "SUN": "Sunday",
    }
    all_days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    # Build enabled interval per day
    day_intervals = {}
    for sched in tp.get("schedules", []):
        interval = {"From": sched["timeFrom"], "To": sched["timeTo"]}
        for abbr in sched["days"]:
            full = day_map.get(abbr)
            if full:
                day_intervals.setdefault(full, []).append(interval)

    body = {"Name": tp["name"]}
    if "description" in tp:
        body["Description"] = tp["description"]
    for day in all_days:
        if day in day_intervals:
            body[day] = {"Enabled": True, "Intervals": day_intervals[day]}
        else:
            body[day] = {"Enabled": False, "Intervals": []}
    return body


def ensure_time_profiles(s, ac_url, time_profiles):
    """Create time profiles that do not already exist. Returns name→id dict."""
    existing = get_existing(s, ac_url, "/api/v3/timeProfiles")
    ids = dict(existing)
    for tp in time_profiles:
        if tp["name"] in existing:
            print(f"  Time profile already exists: {tp['name']} (id={existing[tp['name']]})")
            continue
        body = _make_time_profile_body(tp)
        resp = s.post(f"{ac_url}/api/v3/timeProfiles", json=body, timeout=15)
        if resp.status_code in (200, 201):
            tpid = resp.json().get("Id")
            ids[tp["name"]] = tpid
            print(f"  Created time profile: {tp['name']} (id={tpid})")
        else:
            print(f"  WARN: Could not create time profile '{tp['name']}': {resp.status_code} {resp.text[:120]}")
    return ids


def get_existing_users(s, ac_url):
    """Return dict of full_name→id for all existing users."""
    resp = s.get(f"{ac_url}/api/v3/users", timeout=15)
    if resp.status_code != 200:
        return {}
    data = resp.json()
    items = data.get("items", data) if isinstance(data, dict) else data
    return {item["Name"]: item["Id"] for item in items if "Name" in item and "Id" in item}


def patch_user(s, ac_url, uid, ops):
    """PATCH /api/v3/users/{uid} with JSON-Patch ops."""
    return s.patch(
        f"{ac_url}/api/v3/users/{uid}",
        data=json.dumps(ops),
        headers={"Content-Type": "application/json-patch+json"},
        timeout=15,
    )


def ensure_users(s, ac_url, employees, company_ids, group_ids):
    """
    Create users, assign cards/email/phone via JSON Patch, and add to groups.
    Idempotent: skips users whose full name already exists.
    Returns full_name→id dict.
    """
    existing = get_existing_users(s, ac_url)
    created = {}

    for emp in employees:
        full_name = f"{emp['firstName']} {emp['lastName']}"

        if full_name in existing:
            print(f"  User already exists: {full_name} (id={existing[full_name]})")
            created[full_name] = existing[full_name]
            continue

        company_id = company_ids.get(emp["company"])
        body = {"Name": full_name}
        if company_id is not None:
            body["Company"] = {"Id": company_id}

        resp = s.post(f"{ac_url}/api/v3/users", json=body, timeout=15)
        if resp.status_code not in (200, 201):
            print(f"  WARN: Could not create user {full_name}: {resp.status_code} {resp.text[:120]}")
            continue

        uid = resp.json().get("Id")
        created[full_name] = uid
        print(f"  Created user: {full_name} (id={uid})")

        # Build JSON-Patch operations — send card+email separately from phone
        # (phone path may differ across AC versions and should not block card/email)
        core_ops = []
        if emp.get("cardNumber"):
            core_ops.append({"op": "add", "path": "/AccessCredentials/Cards/-", "value": emp["cardNumber"]})
        if emp.get("email"):
            core_ops.append({"op": "replace", "path": "/Account/Email", "value": emp["email"]})

        if core_ops:
            presp = patch_user(s, ac_url, uid, core_ops)
            if presp.status_code in (200, 204):
                if emp.get("cardNumber"):
                    print(f"    Assigned card {emp['cardNumber']}")
            else:
                print(f"    WARN: PATCH card/email for {uid} returned {presp.status_code}: {presp.text[:120]}")

        # Phone is optional — try separately and ignore failures
        if emp.get("phone"):
            for phone_path in ["/Calling/PhoneNumbers/-", "/Account/Phone"]:
                presp2 = patch_user(s, ac_url, uid, [{"op": "add", "path": phone_path, "value": emp["phone"]}])
                if presp2.status_code in (200, 204):
                    break

        # Add to group
        gid = group_ids.get(emp["group"])
        if gid and uid:
            gresp = s.put(f"{ac_url}/api/v3/groups/{gid}/members",
                          json=[{"Id": uid}], timeout=10)
            if gresp.status_code not in (200, 204):
                print(f"    WARN: Group assignment returned {gresp.status_code}: {gresp.text[:80]}")

    return created


# ---------------------------------------------------------------------------
# Data definitions
# ---------------------------------------------------------------------------

COMPANY_NAMES = [
    "BuildingTech Solutions",
    "SecureGuard Services",
    "Meridian Facilities",
]

GROUPS = [
    {"name": "Employees",      "description": "Full-time staff with standard access",          "company": "BuildingTech Solutions"},
    {"name": "Contractors",    "description": "Temporary contractors with limited access",      "company": "Meridian Facilities"},
    {"name": "Security Staff", "description": "24/7 access throughout the building",            "company": "SecureGuard Services"},
    {"name": "Reception Team", "description": "Front-desk and visitor management staff",        "company": "BuildingTech Solutions"},
    {"name": "IT Department",  "description": "IT staff with server room access",               "company": "BuildingTech Solutions"},
]

TIME_PROFILES = [
    {
        "name": "Office Hours",
        "description": "Standard weekday business hours",
        "schedules": [
            {"days": ["MON", "TUE", "WED", "THU", "FRI"], "timeFrom": "08:00", "timeTo": "18:00"},
        ],
    },
    {
        "name": "Extended Hours",
        "description": "Early start and late finish for senior staff",
        "schedules": [
            {"days": ["MON", "TUE", "WED", "THU", "FRI"], "timeFrom": "06:00", "timeTo": "22:00"},
        ],
    },
    {
        "name": "24/7 Access",
        "description": "Unrestricted access for security staff",
        "schedules": [
            {"days": ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], "timeFrom": "00:00", "timeTo": "23:59"},
        ],
    },
    {
        "name": "Contractor Hours",
        "description": "Daytime only, no weekends",
        "schedules": [
            {"days": ["MON", "TUE", "WED", "THU", "FRI"], "timeFrom": "09:00", "timeTo": "17:00"},
        ],
    },
]

EMPLOYEES = [
    # Reception Team
    {"firstName": "Sandra",  "lastName": "Okafor",    "email": "s.okafor@buildingtech.com",       "phone": "+1-312-555-0142", "company": "BuildingTech Solutions", "group": "Reception Team",  "cardNumber": "0004521873"},
    {"firstName": "James",   "lastName": "Whitfield", "email": "j.whitfield@buildingtech.com",     "phone": "+1-312-555-0163", "company": "BuildingTech Solutions", "group": "Reception Team",  "cardNumber": "0004521874"},

    # Employees (general)
    {"firstName": "Priya",   "lastName": "Nair",      "email": "p.nair@buildingtech.com",          "phone": "+1-415-555-0198", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521875"},
    {"firstName": "Marcus",  "lastName": "Webb",      "email": "m.webb@buildingtech.com",          "phone": "+1-415-555-0209", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521876"},
    {"firstName": "Aaliyah", "lastName": "Thompson",  "email": "a.thompson@buildingtech.com",      "phone": "+1-415-555-0217", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521877"},
    {"firstName": "Derek",   "lastName": "Caldwell",  "email": "d.caldwell@buildingtech.com",      "phone": "+1-312-555-0224", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0013988412"},
    {"firstName": "Fatima",  "lastName": "Al-Rashid", "email": "f.alrashid@buildingtech.com",      "phone": "+1-312-555-0231", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521879"},
    {"firstName": "Carlos",  "lastName": "Mendoza",   "email": "c.mendoza@buildingtech.com",       "phone": "+1-415-555-0238", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521880"},
    {"firstName": "Yuki",    "lastName": "Tanaka",    "email": "y.tanaka@buildingtech.com",        "phone": "+1-415-555-0245", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521881"},
    {"firstName": "Rachel",  "lastName": "Goldstein", "email": "r.goldstein@buildingtech.com",     "phone": "+1-312-555-0252", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521882"},
    {"firstName": "Patrick", "lastName": "O'Brien",   "email": "p.obrien@buildingtech.com",        "phone": "+1-312-555-0259", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521883"},
    {"firstName": "Diana",   "lastName": "Flores",    "email": "d.flores@buildingtech.com",        "phone": "+1-415-555-0266", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521884"},

    # IT Department
    {"firstName": "Kwame",   "lastName": "Asante",    "email": "k.asante@buildingtech.com",        "phone": "+1-415-555-0273", "company": "BuildingTech Solutions", "group": "IT Department",   "cardNumber": "0004521885"},
    {"firstName": "Mei-Ling","lastName": "Zhang",     "email": "m.zhang@buildingtech.com",         "phone": "+1-312-555-0280", "company": "BuildingTech Solutions", "group": "IT Department",   "cardNumber": "0004521886"},

    # Security Staff
    {"firstName": "Victor",  "lastName": "Schulz",    "email": "v.schulz@secureguard.net",         "phone": "+1-773-555-0187", "company": "SecureGuard Services",   "group": "Security Staff",  "cardNumber": "0004521887"},
    {"firstName": "Tamara",  "lastName": "Kowalski",  "email": "t.kowalski@secureguard.net",       "phone": "+1-773-555-0194", "company": "SecureGuard Services",   "group": "Security Staff",  "cardNumber": "0004521888"},
    {"firstName": "Leon",    "lastName": "Fischer",   "email": "l.fischer@secureguard.net",        "phone": "+1-773-555-0201", "company": "SecureGuard Services",   "group": "Security Staff",  "cardNumber": "0007654321"},

    # Contractors
    {"firstName": "Nadia",   "lastName": "Ivanova",   "email": "n.ivanova@meridianfacilities.com", "phone": "+1-847-555-0118", "company": "Meridian Facilities",    "group": "Contractors",     "cardNumber": "0004521890"},
    {"firstName": "Tomas",   "lastName": "Guerrero",  "email": "t.guerrero@meridianfacilities.com","phone": "+1-847-555-0125", "company": "Meridian Facilities",    "group": "Contractors",     "cardNumber": "0004521891"},
    {"firstName": "Olumide", "lastName": "Adeyemi",   "email": "o.adeyemi@meridianfacilities.com", "phone": "+1-847-555-0132", "company": "Meridian Facilities",    "group": "Contractors",     "cardNumber": "0004521892"},

    # Senior employees
    {"firstName": "Heather", "lastName": "Morrison",  "email": "h.morrison@buildingtech.com",      "phone": "+1-312-555-0139", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521893"},
    {"firstName": "Robert",  "lastName": "Nakamura",  "email": "r.nakamura@buildingtech.com",      "phone": "+1-415-555-0146", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521894"},
    {"firstName": "Ingrid",  "lastName": "Sorensen",  "email": "i.sorensen@buildingtech.com",      "phone": "+1-312-555-0153", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521895"},
    {"firstName": "Darnell", "lastName": "Robinson",  "email": "d.robinson@buildingtech.com",      "phone": "+1-415-555-0160", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521896"},
    {"firstName": "Aisha",   "lastName": "Patel",     "email": "a.patel@buildingtech.com",         "phone": "+1-312-555-0167", "company": "BuildingTech Solutions", "group": "Employees",       "cardNumber": "0004521897"},
]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 4:
        print("Usage: seed_ac_data.py <url> <user> <pass>")
        sys.exit(1)

    ac_url  = sys.argv[1].rstrip("/")
    ac_user = sys.argv[2]
    ac_pass = sys.argv[3]

    s = requests.Session()
    s.verify = False

    # 1. Authenticate (handles first-time setup, EULA, and already-configured installs)
    do_login(s, ac_url, ac_user, ac_pass)

    # 1b. Activate Basic license (50 users) — Trial only allows 5
    lic = s.get(f"{ac_url}/api/v3/system/license", timeout=15)
    if lic.status_code == 200:
        tier = lic.json().get("LicenseTier", "")
        if tier == "Trial":
            act = s.put(f"{ac_url}/api/v3/system/license/activateBasic", timeout=15)
            if act.status_code == 200:
                print("Activated Basic license (50 users)")
            else:
                print(f"WARN: Could not activate Basic license: {act.status_code}")
        else:
            print(f"License already: {tier}")

    # 2. Companies
    print("\n--- Companies ---")
    company_ids = ensure_companies(s, ac_url, COMPANY_NAMES)

    # 3. Groups
    print("\n--- Groups ---")
    group_ids = ensure_groups(s, ac_url, GROUPS, company_ids)

    # 4. Time profiles
    print("\n--- Time Profiles ---")
    ensure_time_profiles(s, ac_url, TIME_PROFILES)

    # 5. Users (with cards, contact info, and group membership)
    print("\n--- Users ---")
    created_users = ensure_users(s, ac_url, EMPLOYEES, company_ids, group_ids)

    print(f"\nSeeding complete: {len(created_users)} users processed, "
          f"{len(group_ids)} groups, {len(company_ids)} companies.")


if __name__ == "__main__":
    main()
