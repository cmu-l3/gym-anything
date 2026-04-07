#!/bin/bash
echo "=== Setting up Linguistic Localization Workspace Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Stop Chrome to safely modify profile data
echo "Stopping Chrome..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true

# Prepare Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# --- 1. Create Server Data & Files ---
SERVER_DIR="/home/ga/server_data"
mkdir -p "$SERVER_DIR"

# Generate realistic Translation Memory (TMX) file
cat > "$SERVER_DIR/project_alpha_es.tmx" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tmx SYSTEM "tmx14.dtd">
<tmx version="1.4">
  <header creationtool="BrowserSetup" creationtoolversion="1.0" datatype="PlainText" segtype="sentence" adminlang="en-us" srclang="en" o-tmf="ABCTransEx"/>
  <body>
    <tu>
      <tuv xml:lang="en"><seg>Patient exhibits severe myocardial infarction symptoms.</seg></tuv>
      <tuv xml:lang="es"><seg>El paciente presenta síntomas graves de infarto de miocardio.</seg></tuv>
    </tu>
    <tu>
      <tuv xml:lang="en"><seg>Administer 50mg intravenously every 4 hours.</seg></tuv>
      <tuv xml:lang="es"><seg>Administrar 50 mg por vía intravenosa cada 4 horas.</seg></tuv>
    </tu>
  </body>
</tmx>
EOF

# Generate Medical Style Guide (PDF)
cat > "$SERVER_DIR/medical_style_guide.txt" << 'EOF'
MEDICAL LOCALIZATION STYLE GUIDE
Target Language: Spanish (es-ES)

1. General Tone:
Use formal register (usted) for all patient-facing UI elements.

2. Terminology:
Always use standard SNOMED CT ES terms where applicable.
Do not translate product trade names unless explicitly instructed.

3. Formatting:
Decimals must use a comma (e.g., 3,14).
Thousands must use a dot (e.g., 1.000).
EOF
# Convert to PDF using LibreOffice (available in chrome_env_all)
libreoffice --headless --convert-to pdf "$SERVER_DIR/medical_style_guide.txt" --outdir "$SERVER_DIR/" 2>/dev/null || \
    cp "$SERVER_DIR/medical_style_guide.txt" "$SERVER_DIR/medical_style_guide.pdf" # Fallback if libreoffice fails

# Create HTML Index for download
cat > "$SERVER_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Project Alpha Assets</title></head>
<body style="font-family: Arial; padding: 40px;">
    <h2>Project Alpha - Localization Assets</h2>
    <p>Please download the following resources to your project folder:</p>
    <ul>
        <li><a href="project_alpha_es.tmx" download>Translation Memory (project_alpha_es.tmx)</a></li>
        <li><a href="medical_style_guide.pdf" download>Medical Style Guide (medical_style_guide.pdf)</a></li>
    </ul>
</body>
</html>
EOF

chown -R ga:ga "$SERVER_DIR"

# Start HTTP server
su - ga -c "cd $SERVER_DIR && python3 -m http.server 8080 > /tmp/server.log 2>&1 &"

# --- 2. Write Specification Document ---
cat > "/home/ga/Desktop/localization_spec.txt" << 'EOF'
LINGUISTIC LOCALIZATION WORKSPACE SPECIFICATION

1. BOOKMARKS
Organize the professional bookmarks into these exact three folders on the bookmark bar:
- "CAT & Platforms"
- "Medical Terminology"
- "Dictionaries & Reference"
Remove or archive all personal/distraction bookmarks.

2. SEARCH ENGINES
Add two custom site searches for quick terminology lookup:
- Keyword: proz -> URL: https://www.proz.com/search/?term=%s
- Keyword: ling -> URL: https://www.linguee.com/english-spanish/search?query=%s

3. BROWSER SETTINGS (CRITICAL)
- Language: Add 'Spanish' to the browser accepted languages.
- Spellcheck: Enable spell check for BOTH English and Spanish.
- Auto-Translate: Turn OFF "Offer to translate pages that aren't in a language you read". (Auto-translate must be globally disabled to prevent corrupting web-based CAT tools).

4. ASSETS
Download the Translation Memory (project_alpha_es.tmx) and the Style Guide (medical_style_guide.pdf) from the local server to:
~/Documents/Project_Alpha/
EOF
chown ga:ga "/home/ga/Desktop/localization_spec.txt"

# Ensure target download directory exists
mkdir -p "/home/ga/Documents/Project_Alpha"
chown ga:ga "/home/ga/Documents/Project_Alpha"

# --- 3. Create Bookmarks File ---
python3 << 'PYEOF'
import json

domains = [
    # CAT
    ("Crowdin", "https://crowdin.com"), ("Smartcat", "https://smartcat.com"), 
    ("MateCat", "https://matecat.com"), ("Lokalise", "https://lokalise.com"),
    ("Transifex", "https://transifex.com"), ("Weblate", "https://weblate.org"),
    # Med Term
    ("MedlinePlus ES", "https://medlineplus.gov/spanish"), ("Tremédica", "https://tremedica.org"),
    ("PAHO", "https://paho.org"), ("WHO ES", "https://who.int/es"),
    ("NCBI", "https://ncbi.nlm.nih.gov"), ("PubMed", "https://pubmed.ncbi.nlm.nih.gov"),
    # Dict
    ("WordReference", "https://wordreference.com"), ("Linguee", "https://linguee.com"),
    ("RAE", "https://rae.es"), ("Fundéu", "https://fundeu.es"),
    ("SpanishDict", "https://spanishdict.com"), ("ProZ", "https://proz.com"),
    # Personal
    ("Netflix", "https://netflix.com"), ("Facebook", "https://facebook.com"),
    ("Twitter", "https://twitter.com"), ("Amazon", "https://amazon.com"),
    ("Spotify", "https://spotify.com"), ("Reddit", "https://reddit.com"),
    ("Instagram", "https://instagram.com"), ("TikTok", "https://tiktok.com"),
    ("YouTube", "https://youtube.com"), ("Pinterest", "https://pinterest.com")
]

import random
random.seed(42)
random.shuffle(domains)

children = []
for i, (name, url) in enumerate(domains):
    children.append({
        "date_added": "13360000000000000",
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": "13360000000000000",
            "date_modified": "13360000000000000",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=2)
PYEOF

chown ga:ga "/home/ga/.config/google-chrome/Default/Bookmarks"

# --- 4. Launch Application ---
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check 'http://localhost:8080' &"
sleep 5

# Maximize Chrome Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="