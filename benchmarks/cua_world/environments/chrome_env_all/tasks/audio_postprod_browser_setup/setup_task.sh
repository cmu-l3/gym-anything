#!/usr/bin/env bash
set -euo pipefail

echo "=== Audio Post-Production Browser Setup ==="
echo "Task: Configure browser for mixing bay preventing DAW interference"

# Wait for environment to be ready
sleep 2

# 1. Ensure Chrome profile structure exists
CHROME_DIR="/home/ga/.config/google-chrome"
CHROME_PROFILE="$CHROME_DIR/Default"
mkdir -p "$CHROME_PROFILE"

# 2. Kill Chrome to safely modify profile data
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 3. Create target directories
mkdir -p "/home/ga/Audio/SFX_Downloads"

# 4. Create Instructions Spec
cat > "/home/ga/Desktop/mixing_bay_browser_spec.txt" << 'SPEC_EOF'
=========================================================
MIXING BAY BROWSER CONFIGURATION STANDARD v2.4
=========================================================

1. BOOKMARK ORGANIZATION
Organize the 24 flat bookmarks into these 5 folders on the Bookmark Bar:
- "SFX Libraries": freesound.org, sounddogs.com, prosoundeffects.com, boomlibrary.com, soundsnap.com, asoundeffect.com
- "Ambience & Field": quietplanet.com, hissandaroar.com, fieldsepulchra.com, xeno-canto.org
- "Instruments & Plugins": splice.com, loopmasters.com, native-instruments.com, arturia.com, pluginboutique.com
- "Licensing & Music": epidemicsound.com, artlist.io, musicbed.com, ascap.com, bmi.com
- "Personal": twitter.com, reddit.com, youtube.com, instagram.com

2. SYSTEM PERFORMANCE (DAW Interference Prevention)
- Disable "Use hardware acceleration when available"
- Disable "Continue running background apps when Google Chrome is closed"

3. MEDIA & NOTIFICATION PERMISSIONS
- Global Sound: Set to "Mute sites that play sound" (Block)
- Sound Exceptions (Allow): Add exact whitelist for `freesound.org`, `splice.com`, `soundsnap.com`, and `epidemicsound.com`
- Global Notifications: Set to Block (Do not allow sites to send notifications)

4. DOWNLOAD WORKFLOW
- Default Download Location: `/home/ga/Audio/SFX_Downloads`
- Disable "Ask where to save each file before downloading" (we need 1-click pulling of audio files)

5. SESSION SANITIZATION
- Login tokens for FreeSound and Splice are corrupted.
- Surgically delete ALL cookies and site data ONLY for `freesound.org` and `splice.com`.
- Do NOT use "Clear browsing data" to wipe all cookies (preserve YouTube, Reddit, etc.).
SPEC_EOF

# 5. Bootstrap Chrome to generate DB schemas, then kill it
echo "Bootstrapping Chrome to initialize schemas..."
su - ga -c "DISPLAY=:1 google-chrome-stable --headless --disable-gpu --dump-dom https://example.com > /dev/null 2>&1 &"
sleep 4
pkill -9 -f "google-chrome" 2>/dev/null || true

# 6. Generate Profile via Python
echo "Injecting Task Data..."
python3 << 'PYEOF'
import json, time, uuid, os, sqlite3

chrome_profile = "/home/ga/.config/google-chrome/Default"
chrome_dir = "/home/ga/.config/google-chrome"

# A. BOOKMARKS
bookmarks_data = [
    # SFX
    ("FreeSound", "https://freesound.org"), ("SoundDogs", "https://www.sounddogs.com"),
    ("Pro Sound Effects", "https://www.prosoundeffects.com"), ("Boom Library", "https://www.boomlibrary.com"),
    ("SoundSnap", "https://www.soundsnap.com"), ("A Sound Effect", "https://www.asoundeffect.com"),
    # Ambience
    ("Quiet Planet", "https://quietplanet.com"), ("Hiss and a Roar", "https://hissandaroar.com"),
    ("Field Sepulchra", "https://fieldsepulchra.com"), ("Xeno Canto", "https://xeno-canto.org"),
    # Instruments
    ("Splice", "https://splice.com"), ("Loopmasters", "https://www.loopmasters.com"),
    ("Native Instruments", "https://www.native-instruments.com"), ("Arturia", "https://www.arturia.com"),
    ("Plugin Boutique", "https://www.pluginboutique.com"),
    # Licensing
    ("Epidemic Sound", "https://www.epidemicsound.com"), ("Artlist", "https://artlist.io"),
    ("Musicbed", "https://www.musicbed.com"), ("ASCAP", "https://www.ascap.com"),
    ("BMI", "https://www.bmi.com"),
    # Personal
    ("Twitter", "https://twitter.com"), ("Reddit", "https://www.reddit.com"),
    ("YouTube", "https://www.youtube.com"), ("Instagram", "https://www.instagram.com")
]

children = []
chrome_base = (int(time.time()) + 11644473600) * 1000000

for i, (name, url) in enumerate(bookmarks_data):
    children.append({
        "date_added": str(chrome_base - (i * 1000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base),
            "date_modified": str(chrome_base),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(f"{chrome_profile}/Bookmarks", 'w') as f:
    json.dump(bookmarks, f, indent=3)

# B. PREFERENCES & LOCAL STATE
# Seed with wrong defaults (hardware accel ON, bg apps ON, sound ON, ask ON)
prefs = {
    "background_mode": {"enabled": True},
    "download": {
        "default_directory": "/home/ga/Downloads",
        "prompt_for_download": True
    },
    "profile": {
        "default_content_setting_values": {
            "sound": 1,
            "notifications": 1
        },
        "content_settings": {"exceptions": {}}
    }
}
with open(f"{chrome_profile}/Preferences", 'w') as f:
    json.dump(prefs, f)

local_state = {
    "hardware_acceleration_mode": {"enabled": True},
    "browser": {"hardware_acceleration_mode": {"enabled": True}}
}
with open(f"{chrome_dir}/Local State", 'w') as f:
    json.dump(local_state, f)

# C. INJECT COOKIES
db_paths = [f"{chrome_profile}/Network/Cookies", f"{chrome_profile}/Cookies"]
db_path = next((p for p in db_paths if os.path.exists(p)), None)

if db_path:
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("PRAGMA table_info(cookies)")
        columns = [row[1] for row in c.fetchall()]
        
        if columns:
            domains = ['freesound.org', 'splice.com', 'youtube.com', 'reddit.com', 'google.com']
            for d in domains:
                vals = []
                for col in columns:
                    if col == 'host_key': vals.append(f"'{d}'")
                    elif col == 'name': vals.append("'session_token'")
                    elif col == 'value': vals.append("'corrupted' if d in ['freesound.org', 'splice.com'] else 'valid'")
                    elif col == 'path': vals.append("'/'")
                    elif col in ['creation_utc', 'expires_utc', 'last_access_utc', 'last_update_utc']: vals.append(str(chrome_base))
                    elif col == 'encrypted_value': vals.append("X''")
                    else: vals.append("0")
                
                c.execute(f"INSERT INTO cookies ({','.join(columns)}) VALUES ({','.join(vals)})")
            conn.commit()
        conn.close()
        print(f"Successfully injected cookies into {db_path}")
    except Exception as e:
        print(f"Cookie injection error: {e}")
else:
    print("WARNING: Cookie DB not found.")
PYEOF

chown -R ga:ga "/home/ga/.config/google-chrome"
chown ga:ga "/home/ga/Desktop/mixing_bay_browser_spec.txt"
chown ga:ga "/home/ga/Audio/SFX_Downloads"

# 7. Start Chrome
echo "Starting Chrome for user..."
date +%s > /tmp/task_start_time.txt
su - ga -c "DISPLAY=:1 google-chrome-stable --window-size=1920,1080 > /tmp/chrome_start.log 2>&1 &"

# 8. Wait and capture initial screenshot
sleep 4
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="