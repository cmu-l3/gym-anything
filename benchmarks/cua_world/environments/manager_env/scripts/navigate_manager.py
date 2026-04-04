#!/usr/bin/env python3
"""
Navigate Manager.io Server Edition to a specific module.

Uses xdotool to:
  1. Start Firefox at localhost:8080
  2. Login as administrator (no password - click Next)
  3. Select the Northwind Traders business
  4. Navigate to the requested module via the left sidebar
  5. Optionally click the "New [Item]" button

Usage:
  python3 navigate_manager.py <module> [action]

Modules:
  summary, bank_accounts, receipts, payments, customers, sales_invoices,
  credit_notes, suppliers, purchase_invoices, debit_notes,
  inventory, journal_entries, reports, settings

Actions:
  new   -- click the "New" button to open a blank entry form

Coordinates are calibrated for 1920x1080 resolution.
Verified via visual_grounding on 2026-02-20.
"""

import subprocess
import sys
import time
import os

MANAGER_URL = "http://localhost:8080"
# Snap Firefox stores profiles in snap data dir; the classical path is a symlink
# but snap resolves it internally to the snap data dir for lock files.
FIREFOX_PROFILE = "/home/ga/.mozilla/firefox/manager.profile"
FIREFOX_SNAP_PROFILE = "/home/ga/snap/firefox/common/.mozilla/firefox/manager.profile"

# -----------------------------------------------------------------------
# Sidebar module coordinates at 1920x1080.
# Verified via visual_grounding on 2026-02-20 from live Summary page:
# All sidebar items at x=154 in 720p (Firefox window pos 70,101 size 1850x1016)
# 720p coords × 1.5 = 1080p coords
# 720p: Summary(154,238) BankAccounts(154,263) Receipts(154,288)
#   Payments(154,313) Customers(154,337) SalesInvoices(154,362)
#   CreditNotes(154,387) Suppliers(154,411) PurchaseInvoices(154,436)
#   DebitNotes(154,461) Inventory(154,485) JournalEntries(154,510)
#   Reports(154,535) Settings(154,560)
# -----------------------------------------------------------------------
SIDEBAR_COORDS = {
    "summary":            (231, 357),
    "bank_accounts":      (231, 395),
    "receipts":           (231, 432),
    "payments":           (231, 470),
    "customers":          (231, 506),
    "sales_invoices":     (231, 543),
    "credit_notes":       (231, 581),
    "suppliers":          (231, 617),
    "purchase_invoices":  (231, 654),
    "debit_notes":        (231, 692),
    "inventory":          (231, 728),
    "journal_entries":    (231, 765),
    "reports":            (231, 803),
    "settings":           (231, 840),
}

# "New [Item]" button location in the content area.
# Verified 2026-02-20: New Customer at (388,312) in 720p → (582,468) in 1080p
NEW_BUTTON_COORDS = (582, 468)

# Login form: verified 2026-02-20 from live login page screenshot
# Username field at (665,278) in 720p → (998,417) in 1080p
# Next button at (557,312) in 720p → (836,468) in 1080p
LOGIN_USERNAME_COORDS = (998, 417)
LOGIN_NEXT_COORDS = (836, 468)

# Business list: Northwind Traders link (center of page, first business row)
# Verified via visual_grounding: 720p (574,245) × 1.5 = 1080p (861,368)
BUSINESS_LINK_COORDS = (861, 368)


def xdo(*args, delay=0.6, check=False):
    """Run an xdotool command with DISPLAY=:1."""
    env = os.environ.copy()
    env["DISPLAY"] = ":1"
    env["XAUTHORITY"] = "/home/ga/.Xauthority"
    cmd = ["xdotool"] + list(str(a) for a in args)
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if delay > 0:
        time.sleep(delay)
    return result


def run(cmd, check=False):
    """Run a shell command."""
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def click(x, y, delay=0.8):
    xdo("mousemove", x, y, delay=0)
    xdo("click", "1", delay=delay)


def key(k, delay=0.5):
    xdo("key", "--clearmodifiers", k, delay=delay)


def type_text(text, delay=0.3):
    xdo("type", "--clearmodifiers", "--delay", "50", text, delay=delay)


def get_window_title():
    """Get the current Firefox window title."""
    result = run("DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null")
    return result.stdout.strip()


def start_firefox():
    """Kill existing Firefox and start a new instance at Manager.io."""
    run("pkill -9 -f firefox 2>/dev/null || true")
    time.sleep(3)
    # Stop and reset the snap Firefox systemd scope so it doesn't block new launch
    run("systemctl --user stop 'snap.firefox.firefox*.scope' 2>/dev/null || true")
    run("systemctl --user reset-failed 'snap.firefox.firefox*.scope' 2>/dev/null || true")
    time.sleep(2)
    # Remove stale Firefox lock files (both classical and snap profile paths)
    run(f"rm -f '{FIREFOX_PROFILE}/lock' '{FIREFOX_PROFILE}/.parentlock' 2>/dev/null || true")
    run(f"rm -f '{FIREFOX_SNAP_PROFILE}/lock' '{FIREFOX_SNAP_PROFILE}/.parentlock' 2>/dev/null || true")

    firefox_inner = (
        f"DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority "
        f"setsid firefox --no-remote "
        f"--new-window \"{MANAGER_URL}/\" "
        f"> /tmp/firefox_manager_nav.log 2>&1"
    )
    # If running as root, switch to ga user; otherwise run directly
    if os.getuid() == 0:
        cmd = f"su - ga -c '{firefox_inner} &'"
    else:
        cmd = f"{firefox_inner} &"
    run(cmd)
    print("Firefox starting...")
    time.sleep(12)  # Wait for Firefox and page to fully load

    # Focus and maximize the Firefox window
    xdo("search", "--onlyvisible", "--name", "Firefox", "windowfocus", delay=1)
    run("DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true")
    time.sleep(2)

    # Handle post-startup dialogs before returning
    title_check = get_window_title()
    print(f"Post-start window title: {title_check!r}")

    if "Close Firefox" in title_check or "already running" in title_check.lower():
        print("Dismissing 'Close Firefox' dialog...")
        xdo("key", "Return", delay=3)
        time.sleep(3)
        # Retry focus
        xdo("search", "--onlyvisible", "--name", "Firefox", "windowfocus", delay=1)
        time.sleep(1)

    # Handle "Restore Session" page by navigating directly to Manager URL
    title_check2 = get_window_title()
    if "Restore Session" in title_check2 or "Restore" in title_check2:
        print("Handling 'Restore Session' page - navigating to Manager.io...")
        xdo("key", "ctrl+l", delay=0.5)
        type_text(MANAGER_URL + "/")
        xdo("key", "Return", delay=4)
        time.sleep(2)


def login():
    """Log in to Manager.io with administrator / (empty password).

    Manager.io uses a single-step login: username → click Next.
    The administrator account has no password.
    If already on Businesses page (session active), skip login.
    """
    title = get_window_title()
    print(f"Window title: {title!r}")

    if "Login" in title or "login" in title:
        print("Logging in as administrator...")
        # Username field is typically pre-filled; ensure it's correct
        click(*LOGIN_USERNAME_COORDS)
        key("ctrl+a")
        type_text("administrator")
        # Click the Next button (single-step: no separate password field)
        click(*LOGIN_NEXT_COORDS, delay=3)
        print("Next clicked, waiting for Businesses page...")
        time.sleep(4)
    elif "Businesses" in title or "Northwind" in title:
        print("Already authenticated, skipping login.")
    else:
        print(f"Unexpected title: {title!r}, attempting login anyway...")
        click(*LOGIN_USERNAME_COORDS)
        key("ctrl+a")
        type_text("administrator")
        click(*LOGIN_NEXT_COORDS, delay=3)
        time.sleep(4)


def select_northwind():
    """Navigate to the Northwind Traders business via URL lookup."""
    title = get_window_title()
    if "Northwind" in title and "Businesses" not in title:
        print("Already in Northwind Traders business, skipping selection.")
        return

    print("Selecting Northwind Traders business...")
    # Use HTTP API to resolve the exact key for "Northwind Traders" (not "Northwind")
    try:
        import requests as _req
        import re as _re
        s = _req.Session()
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"},
               allow_redirects=True, timeout=10)
        biz_page = s.get(f"{MANAGER_URL}/businesses", timeout=10).text
        m = _re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
        if not m:
            m = _re.search(r'start\?([^"&\s]+)', biz_page)
        if m:
            nwt_url = f"{MANAGER_URL}/start?{m.group(1)}"
            print(f"Navigating to Northwind Traders via URL...")
            xdo("key", "ctrl+l", delay=0.5)
            type_text(nwt_url)
            xdo("key", "Return", delay=5)
            time.sleep(3)
            print("Business selected, waiting for dashboard...")
            return
    except Exception as e:
        print(f"URL-based navigation failed: {e}, falling back to coordinates")

    # Fallback: coordinate-based click
    click(*BUSINESS_LINK_COORDS, delay=2)
    print("Business selected, waiting for dashboard...")
    time.sleep(5)


def navigate_to_module(module):
    """Click on the specified module in the left sidebar."""
    module_key = module.lower()

    if module_key not in SIDEBAR_COORDS:
        print(f"WARNING: Unknown module '{module}'. Available: {list(SIDEBAR_COORDS.keys())}")
        return

    x, y = SIDEBAR_COORDS[module_key]
    print(f"Navigating to module '{module}' at sidebar coords ({x}, {y})...")
    click(x, y, delay=2)
    print(f"Module '{module}' loaded.")


def click_new_button():
    """Click the 'New [Item]' button in the main content area."""
    print("Clicking New button...")
    click(*NEW_BUTTON_COORDS, delay=1.5)
    print("New form should be open.")


def main():
    module = sys.argv[1] if len(sys.argv) > 1 else None
    action = sys.argv[2] if len(sys.argv) > 2 else None

    print(f"navigate_manager.py: module={module!r}, action={action!r}")

    # Step 1: Start Firefox
    start_firefox()

    # Step 2: Login
    login()

    # Step 3: Select Northwind business
    select_northwind()

    # Step 4: Navigate to module (if specified)
    if module:
        navigate_to_module(module)

    # Step 5: Click New button (if action='new')
    if action and action.lower() == "new":
        click_new_button()

    print("Navigation complete.")


if __name__ == "__main__":
    main()
