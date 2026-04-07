#!/usr/bin/env bash
set -euo pipefail

echo "=== Tax Season Browser Workspace Task Setup ==="

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Stop Chrome to prepare profile safely
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# Create required download directory
mkdir -p "/home/ga/Documents/Client_Tax_Files"
chown -R ga:ga "/home/ga/Documents/Client_Tax_Files"

# 1. Create Bookmarks file (20 tax + 15 personal, unorganized)
echo "Injecting Bookmarks..."
python3 - << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

tax_bms = [
    ("IRS Homepage", "https://www.irs.gov"),
    ("IRS Free File", "https://www.irs.gov/filing/free-file-do-your-federal-taxes-for-free"),
    ("IRS EITC", "https://www.irs.gov/credits-deductions/individuals/earned-income-tax-credit-eitc"),
    ("IRS Forms", "https://www.irs.gov/forms-instructions"),
    ("IRS Refund Tracker", "https://www.irs.gov/refunds"),
    ("IRS e-File", "https://www.irs.gov/filing/e-file-options"),
    ("IRS Publication 17", "https://www.irs.gov/publications/p17"),
    ("IRS VITA Locator", "https://www.irs.gov/individuals/free-tax-return-preparation-for-qualifying-taxpayers"),
    ("California FTB", "https://www.ftb.ca.gov"),
    ("New York Tax", "https://www.tax.ny.gov"),
    ("Texas Comptroller", "https://comptroller.texas.gov"),
    ("Florida Revenue", "https://floridarevenue.com"),
    ("AICPA", "https://www.aicpa-cima.com"),
    ("Tax Foundation", "https://taxfoundation.org"),
    ("NATP", "https://www.natptax.com"),
    ("Drake Software", "https://www.drakesoftware.com"),
    ("TaxAct Professional", "https://www.taxact.com/professional"),
    ("Social Security Admin", "https://www.ssa.gov"),
    ("FinCEN", "https://www.fincen.gov"),
    ("SEC EDGAR", "https://www.sec.gov/edgar")
]

personal_bms = [
    ("YouTube", "https://www.youtube.com"), ("Reddit", "https://www.reddit.com"),
    ("Spotify", "https://open.spotify.com"), ("Netflix", "https://www.netflix.com"),
    ("TikTok", "https://www.tiktok.com"), ("Instagram", "https://www.instagram.com"),
    ("Twitter/X", "https://x.com"), ("Discord", "https://discord.com"),
    ("Twitch", "https://www.twitch.tv"), ("Pinterest", "https://www.pinterest.com"),
    ("Amazon", "https://www.amazon.com"), ("eBay", "https://www.ebay.com"),
    ("Steam", "https://store.steampowered.com"), ("ESPN", "https://www.espn.com"),
    ("Weather.com", "https://weather.com")
]

# Mix them up slightly
all_bms = tax_bms[:10] + personal_bms[:7] + tax_bms[10:] + personal_bms[7:]

children = []
for i, (name, url) in enumerate(all_bms):
    children.append({
        "date_added": str(chrome_base - (i * 100000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {"children": children, "date_added": str(chrome_base), "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": str(chrome_base), "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": str(chrome_base), "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

# 2. Briefly run Chrome headlessly to initialize the SQLite DB schemas
echo "Initializing SQLite databases..."
sudo -u ga google-chrome-stable --headless --disable-gpu --dump-dom "about:blank" > /dev/null 2>&1 || true
sleep 3
pkill -f "google-chrome" 2>/dev/null || true
sleep 1

# 3. Inject History and Cookies
echo "Injecting History and Cookies..."
python3 - << 'PYEOF'
import sqlite3, time, os

chrome_base = (int(time.time()) + 11644473600) * 1000000
history_db = "/home/ga/.config/google-chrome/Default/History"
cookies_db = "/home/ga/.config/google-chrome/Default/Cookies"

tax_urls = [
    ("https://www.irs.gov/forms-instructions", "Forms & Instructions | Internal Revenue Service"),
    ("https://www.irs.gov/refunds", "Where's My Refund? | Internal Revenue Service"),
    ("https://www.drakesoftware.com/support", "Drake Software Support"),
    ("https://www.tax.ny.gov/pit/", "NY State Personal Income Tax"),
    ("https://comptroller.texas.gov/taxes/", "Texas Taxes"),
    ("https://www.ssa.gov/employer/", "Employer W-2 Filing | SSA"),
    ("https://www.fincen.gov/boi", "Beneficial Ownership Information Reporting | FinCEN"),
    ("https://www.irs.gov/credits-deductions/individuals/earned-income-tax-credit-eitc", "Earned Income Tax Credit"),
    ("https://www.aicpa-cima.com/resources", "AICPA Resources"),
    ("https://www.sec.gov/edgar/searchedgar/companysearch", "EDGAR Company Filings"),
    ("https://www.irs.gov/payments", "Make a Payment | IRS"),
    ("https://www.irs.gov/publications/p17", "Publication 17 (2023), Your Federal Income Tax"),
    ("https://www.taxact.com/professional/support", "TaxAct Professional Support"),
    ("https://floridarevenue.com/taxes/Pages/default.aspx", "Florida Dept of Revenue"),
    ("https://www.ftb.ca.gov/file/index.html", "File - Franchise Tax Board - CA.gov")
]

personal_urls = [
    ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "Never Gonna Give You Up - YouTube"),
    ("https://www.reddit.com/r/funny/", "r/funny"),
    ("https://www.reddit.com/r/gaming/", "r/gaming - Reddit"),
    ("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M", "Today's Top Hits | Spotify"),
    ("https://www.netflix.com/browse", "Home - Netflix"),
    ("https://www.tiktok.com/foryou", "TikTok - Make Your Day"),
    ("https://www.instagram.com/", "Instagram"),
    ("https://x.com/home", "Home / X"),
    ("https://discord.com/channels/@me", "Discord"),
    ("https://www.twitch.tv/directory", "Browse - Twitch"),
    ("https://www.pinterest.com/", "Pinterest"),
    ("https://www.amazon.com/dp/B08F7PTF53", "Amazon.com: Desk Organizer"),
    ("https://www.amazon.com/cart", "Amazon.com Shopping Cart"),
    ("https://www.ebay.com/itm/123456789", "Vintage Watch | eBay"),
    ("https://store.steampowered.com/", "Welcome to Steam"),
    ("https://store.steampowered.com/app/1086940/Baldurs_Gate_3/", "Baldur's Gate 3 on Steam"),
    ("https://www.espn.com/nba/", "NBA Basketball News, Scores, Stats - ESPN"),
    ("https://www.espn.com/nfl/", "NFL Football News - ESPN"),
    ("https://weather.com/weather/today/l/USNY0996", "Local Weather Forecast"),
    ("https://weather.com/weather/radar/interactive/l/USNY0996", "Interactive Weather Radar"),
    ("https://www.youtube.com/feed/subscriptions", "YouTube Subscriptions"),
    ("https://www.reddit.com/r/AskReddit/", "AskReddit"),
    ("https://www.netflix.com/title/80018141", "Stranger Things | Netflix"),
    ("https://x.com/search?q=trending", "Trending / X"),
    ("https://www.instagram.com/explore/", "Explore - Instagram")
]

# Insert History
if os.path.exists(history_db):
    try:
        conn = sqlite3.connect(history_db)
        c = conn.cursor()
        for i, (url, title) in enumerate(tax_urls + personal_urls):
            visit_time = chrome_base - ((100 - i) * 8640000000) # Past days
            c.execute("INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, 1, 0, ?, 0)", (url, title, visit_time))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Error injecting history: {e}")

# Insert Cookies
if os.path.exists(cookies_db):
    try:
        conn = sqlite3.connect(cookies_db)
        c = conn.cursor()
        gov_cookies = [".irs.gov", ".drakesoftware.com", ".tax.ny.gov", ".ssa.gov", ".sec.gov"]
        pers_cookies = [".youtube.com", ".reddit.com", ".spotify.com", ".netflix.com", ".tiktok.com", ".instagram.com", ".x.com", ".discord.com", ".amazon.com", ".espn.com"]
        
        for i, domain in enumerate(gov_cookies + pers_cookies):
            creation_utc = chrome_base - (i * 3600000000)
            expires_utc = chrome_base + 31536000000000 # 1 year
            c.execute("""
                INSERT INTO cookies 
                (creation_utc, host_key, top_frame_site_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party, last_update_utc) 
                VALUES (?, ?, '', 'session_token', 'val123', '/', ?, 1, 1, ?, 1, 1, 1, -1, 2, 443, 0, ?)
            """, (creation_utc, domain, expires_utc, creation_utc, creation_utc))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Error injecting cookies: {e}")
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome/

# 4. Launch Chrome
echo "Launching Chrome for Agent..."
su - ga -c "DISPLAY=:1 google-chrome-stable --remote-debugging-port=9222 --no-first-run --no-default-browser-check > /tmp/chrome_task.log 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Google Chrome"; then
        break
    fi
    sleep 1
done
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="