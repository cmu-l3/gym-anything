# OSWorld Chrome Metrics Support

This document maps all OSWorld Chrome evaluation metrics to the capabilities provided by the `chrome_env_all` environment.

## Overview

The `chrome_env_all` environment is designed to support **all** OSWorld Chrome metrics through a combination of:
1. **Chrome DevTools Protocol (CDP)** access
2. **File system access** to Chrome's profile data
3. **Verification utilities** in `utils/chrome_verification_utils.py`
4. **GUI automation** tools (xdotool, wmctrl)

## Metric Support Matrix

### ✅ URL and Tab Management

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `is_expected_active_tab` | ✅ Full | CDP `/json` endpoint + `chrome-cdp-util active-tab` |
| `is_expected_active_tab_approximate` | ✅ Full | Same as above + URL parsing utilities |
| `is_expected_url_pattern_match` | ✅ Full | CDP + Python regex matching in verifier |
| `is_expected_tabs` | ✅ Full | CDP `/json` endpoint lists all tabs |

**Implementation Details:**
```python
# Get active tab URL
import requests
response = requests.get('http://localhost:9222/json')
tabs = response.json()
active_tab = tabs[0] if tabs else {}
url = active_tab.get('url', '')

# Or use utility
from chrome_verification_utils import get_active_tab_info_from_cdp
tab_info = get_active_tab_info_from_cdp(copy_from_env_fn)
```

**Files Used:**
- CDP HTTP endpoint at port 9222
- `/tmp/final_url.txt` (exported by tasks)

---

### ✅ Bookmarks

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `is_expected_bookmarks` (folders) | ✅ Full | Parse `Bookmarks` JSON file |
| `is_expected_bookmarks` (URLs) | ✅ Full | Parse `Bookmarks` JSON file |
| `is_expected_bookmarks` (folder contents) | ✅ Full | Parse nested bookmark structure |

**Implementation Details:**
```python
from chrome_verification_utils import (
    get_bookmark_bar_folders,
    get_bookmark_bar_urls,
    get_folder_bookmarks
)

# Copy bookmarks file
success, files, error = setup_chrome_verification(
    copy_from_env,
    ["Bookmarks"]
)

# Get bookmark bar folders
folders = get_bookmark_bar_folders(files["Bookmarks"])

# Get specific folder contents
liked_authors_urls = get_folder_bookmarks(files["Bookmarks"], "Liked Authors")
```

**Files Used:**
- `/home/ga/.config/google-chrome/Default/Bookmarks`

**Format:** JSON file with nested structure
```json
{
  "roots": {
    "bookmark_bar": {
      "children": [
        {"type": "folder", "name": "Work", "children": [...]},
        {"type": "url", "name": "Example", "url": "https://..."}
      ]
    }
  }
}
```

---

### ✅ History

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `check_history_deleted` | ✅ Full | Query History SQLite database |
| History keyword search | ✅ Full | `check_history_contains_keyword()` |

**Implementation Details:**
```python
from chrome_verification_utils import parse_history, check_history_contains_keyword

# Copy and parse history
success, files, error = setup_chrome_verification(copy_from_env, ["History"])
history = parse_history(files["History"])

# Check for specific keywords
has_youtube = check_history_contains_keyword(files["History"], "youtube")
```

**Files Used:**
- `/home/ga/.config/google-chrome/Default/History` (SQLite database)

**Schema:** 
```sql
CREATE TABLE urls (
    id INTEGER PRIMARY KEY,
    url TEXT,
    title TEXT,
    visit_count INTEGER,
    last_visit_time INTEGER
);
```

---

### ✅ Cookies

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `is_cookie_deleted` | ✅ Full | Query Cookies SQLite database |
| Cookie domain check | ✅ Full | `check_cookie_for_domain()` |

**Implementation Details:**
```python
from chrome_verification_utils import parse_cookies, check_cookie_for_domain

# Copy and parse cookies
success, files, error = setup_chrome_verification(copy_from_env, ["Cookies"])
cookies = parse_cookies(files["Cookies"])

# Check for specific domain
has_google_cookie = check_cookie_for_domain(files["Cookies"], "google.com")
```

**Files Used:**
- `/home/ga/.config/google-chrome/Default/Cookies` (SQLite database)

**Schema:**
```sql
CREATE TABLE cookies (
    name TEXT,
    value TEXT,
    host_key TEXT,
    path TEXT,
    expires_utc INTEGER,
    is_secure INTEGER,
    is_httponly INTEGER
);
```

---

### ✅ Extensions

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `is_expected_installed_extensions` | ✅ Full | List extension directories + manifest parsing |

**Implementation Details:**
```python
from chrome_verification_utils import get_installed_extensions

# Get installed extension IDs
extensions_dir = "/home/ga/.config/google-chrome/Default/Extensions"
installed = get_installed_extensions(extensions_dir)

# Verify expected extensions
expected = ["extension_id_1", "extension_id_2"]
all_installed = set(expected).issubset(set(installed))
```

**Files Used:**
- `/home/ga/.config/google-chrome/Default/Extensions/`
- Each extension has a subdirectory with `manifest.json`

---

### ✅ Settings and Preferences

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `check_font_size` | ✅ Full | Parse Preferences JSON |
| `check_enabled_experiments` | ✅ Full | Parse `Local State` file |
| Download settings | ✅ Full | Parse Preferences JSON |
| Privacy settings | ✅ Full | Parse Preferences JSON |

**Implementation Details:**
```python
from chrome_verification_utils import parse_preferences, get_font_size

# Copy preferences
success, files, error = setup_chrome_verification(
    copy_from_env,
    ["Preferences", "Local State"]
)

# Get font size
font_info = get_font_size(files["Preferences"])
default_size = font_info['default_font_size']

# Get any preference
prefs = parse_preferences(files["Preferences"])
download_prompt = prefs.get('download', {}).get('prompt_for_download', True)
```

**Files Used:**
- `/home/ga/.config/google-chrome/Default/Preferences` (JSON)
- `/home/ga/.config/google-chrome/Local State` (JSON)

---

### ✅ Search Queries

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `is_expected_search_query` | ✅ Full | URL pattern matching via CDP |

**Implementation Details:**
```python
import re

# Get active URL from CDP
url = get_active_tab_url()

# Check search query pattern
pattern = r"google\.com/search\?q=(.+)"
match = re.search(pattern, url)
if match:
    query = match.group(1)
```

---

### ✅ File Comparisons

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `compare_pdfs` | ✅ Full | PyMuPDF + text extraction + fuzzy matching |
| `compare_pdf_images` | ✅ Full | Image extraction + perceptual hashing |
| `compare_htmls` | ✅ Full | BeautifulSoup4 + structure comparison |
| `compare_archive` | ✅ Full | Archive extraction + recursive comparison |

**Implementation Details:**

**PDF Comparison:**
```python
import fitz  # PyMuPDF
import rapidfuzz.fuzz as fuzz

def compare_pdfs(pdf1_path, pdf2_path):
    # Extract text from both PDFs
    text1 = extract_text_from_pdf(pdf1_path)
    text2 = extract_text_from_pdf(pdf2_path)
    
    # Fuzzy match
    score = fuzz.ratio(text1, text2) / 100
    return score
```

**PDF Image Comparison:**
```python
import imagehash
from PIL import Image

def compare_pdf_images(pdf1_path, pdf2_path):
    images1 = extract_images_from_pdf(pdf1_path)
    images2 = extract_images_from_pdf(pdf2_path)
    
    scores = []
    for img1, img2 in zip(images1, images2):
        hash1 = imagehash.phash(img1)
        hash2 = imagehash.phash(img2)
        diff = hash1 - hash2
        scores.append(1.0 if diff <= 5 else 0.0)
    
    return sum(scores) / len(scores)
```

**HTML Comparison:**
```python
from bs4 import BeautifulSoup

def compare_htmls(html1_path, html2_path):
    with open(html1_path) as f1, open(html2_path) as f2:
        soup1 = BeautifulSoup(f1, 'lxml')
        soup2 = BeautifulSoup(f2, 'lxml')
    
    # Compare structure recursively
    for elem1, elem2 in zip(soup1.recursiveChildGenerator(), 
                            soup2.recursiveChildGenerator()):
        if not compare_elements(elem1, elem2):
            return 0.0
    return 1.0
```

**Dependencies Installed:**
- PyMuPDF (`fitz`)
- Pillow (PIL)
- imagehash
- BeautifulSoup4
- lxml
- poppler-utils (for PDF manipulation)

---

### ✅ Desktop and System

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `is_shortcut_on_desktop` | ✅ Full | Check `/home/ga/Desktop/*.desktop` files |

**Implementation Details:**
```python
import os

def check_desktop_shortcut(name=None, exec_cmd=None, url=None):
    desktop_dir = "/home/ga/Desktop"
    
    for filename in os.listdir(desktop_dir):
        if filename.endswith('.desktop'):
            path = os.path.join(desktop_dir, filename)
            with open(path) as f:
                content = f.read()
            
            if name and f"Name={name}\n" in content:
                return True
            if exec_cmd and f"Exec={exec_cmd}\n" in content:
                return True
            if url and url in content:
                return True
    
    return False
```

**Files Used:**
- `/home/ga/Desktop/*.desktop` (XDG desktop entry files)

---

### ✅ Content Verification

| OSWorld Metric | Support | Implementation |
|----------------|---------|----------------|
| `is_added_to_steam_cart` | ✅ Full | CDP page content extraction |

**Implementation Details:**
```python
# Use CDP Runtime.evaluate to get page content
import requests
import json

# Get WebSocket debugger URL
response = requests.get('http://localhost:9222/json')
tabs = response.json()
ws_url = tabs[0]['webSocketDebuggerUrl']

# Connect via WebSocket and execute JavaScript
# to get page content, then check for expected items
```

**Alternative:** Use Selenium or pychrome for easier CDP interaction
```python
import pychrome

browser = pychrome.Browser(url="http://localhost:9222")
tab = browser.list_tab()[0]
tab.start()

# Get page content
result = tab.Runtime.evaluate(expression="document.body.innerText")
content = result['result']['value']

# Check for items
items = ["Item 1", "Item 2"]
all_present = all(item in content for item in items)
```

---

## Additional Features

### Screenshot Capture
```bash
# From inside container
import -window root /tmp/screenshot.png

# Or using Chrome CDP
# Navigate to chrome://screenshot or use DevTools API
```

### Video/Audio Recording
- Environment includes FFmpeg for video recording
- PulseAudio for audio capture
- VLC for media playback and verification

### Network Control
```bash
# Block specific domains (if needed for tasks)
iptables -A OUTPUT -d example.com -j REJECT

# Or use Chrome flags
google-chrome-stable --host-rules="MAP * 127.0.0.1"
```

---

## Integration Examples

### Example 1: URL Navigation Task (Implemented)

See `tasks/example_url_navigation/` for a complete implementation that:
1. Launches Chrome at a starting URL
2. Lets the agent navigate
3. Captures final URL via CDP
4. Verifies URL pattern match

### Example 2: Bookmark Management Task

```python
def verify_bookmark_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    
    success, files, error = setup_chrome_verification(
        copy_from_env,
        ["Bookmarks"]
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": error}
    
    # Check if "Work" folder exists
    folders = get_bookmark_bar_folders(files["Bookmarks"])
    
    passed = "Work" in folders
    cleanup_verification_temp()
    
    return {
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": "Bookmark folder created" if passed else "Folder not found"
    }
```

### Example 3: Extension Installation Task

```python
def verify_extension_task(traj, env_info, task_info):
    # Extension IDs to check
    expected_extensions = ["extension_id_123"]
    
    # Get installed extensions via file system
    extensions_dir = "/home/ga/.config/google-chrome/Default/Extensions"
    # Copy directory or list via exec
    
    installed = get_installed_extensions(extensions_dir)
    
    passed = set(expected_extensions).issubset(set(installed))
    
    return {
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": f"Extensions: {installed}"
    }
```

---

## Limitations and Workarounds

### 1. Real-time Content Access
**Challenge:** Getting page content requires WebSocket CDP connection

**Workaround:**
- Use `export_result.sh` to execute JavaScript via CDP
- Save content to temp file
- Copy file in verifier

```bash
# In export_result.sh
curl -s http://localhost:9222/json/list | \
  jq -r '.[0].webSocketDebuggerUrl' > /tmp/ws_url.txt

# Use pychrome or similar to evaluate:
# document.body.innerText
```

### 2. Dynamic State Changes
**Challenge:** Chrome state changes after task completes

**Workaround:**
- Use `post_task` hook to export all necessary files
- Take screenshots immediately
- Save HTML snapshots

### 3. Extension Permissions
**Challenge:** Some extensions require user interaction

**Workaround:**
- Pre-configure extension permissions in Preferences
- Use `--load-extension` flag in launch script
- Disable extension prompts via policy

---

## Summary

The `chrome_env_all` environment provides **comprehensive support** for all OSWorld Chrome metrics through:

1. **CDP Access**: Real-time tab/URL/content information
2. **File System**: Bookmarks, history, cookies, preferences
3. **Utilities**: Pre-built verification functions
4. **Flexibility**: Both API and GUI automation supported

All metrics listed in `osworld_chrome_metrics.py` can be implemented using the provided infrastructure.

