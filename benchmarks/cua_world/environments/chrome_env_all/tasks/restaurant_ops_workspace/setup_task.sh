#!/usr/bin/env bash
set -euo pipefail

echo "=== Restaurant Operations Workspace Task Setup ==="
echo "Task: Configure browser per restaurant manager standard"

# Wait for environment to be ready
sleep 2

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any running Chrome
echo "Stopping Chrome to set up task data..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# 2. Prepare Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# 3. Create Bookmarks JSON (20 flat + 12 in Old Imports)
echo "Creating bookmarks..."
cat > "$CHROME_PROFILE/Bookmarks" << 'BOOKMARKS_EOF'
{
   "checksum": "0",
   "roots": {
      "bookmark_bar": {
         "children": [
            {"date_added": "13360000000000000", "id": "1", "name": "Sysco", "type": "url", "url": "https://www.sysco.com/"},
            {"date_added": "13360000000000001", "id": "2", "name": "US Foods", "type": "url", "url": "https://www.usfoods.com/"},
            {"date_added": "13360000000000002", "id": "3", "name": "Restaurant Depot", "type": "url", "url": "https://www.restaurantdepot.com/"},
            {"date_added": "13360000000000003", "id": "4", "name": "Toast POS", "type": "url", "url": "https://pos.toasttab.com/"},
            {"date_added": "13360000000000004", "id": "5", "name": "Square Dashboard", "type": "url", "url": "https://squareup.com/dashboard/"},
            {"date_added": "13360000000000005", "id": "6", "name": "ServSafe", "type": "url", "url": "https://www.servsafe.com/"},
            {"date_added": "13360000000000006", "id": "7", "name": "FDA Food Safety", "type": "url", "url": "https://www.fda.gov/food/"},
            {"date_added": "13360000000000007", "id": "8", "name": "7shifts", "type": "url", "url": "https://www.7shifts.com/"},
            {"date_added": "13360000000000008", "id": "9", "name": "When I Work", "type": "url", "url": "https://wheniwork.com/"},
            {"date_added": "13360000000000009", "id": "10", "name": "Indeed", "type": "url", "url": "https://www.indeed.com/"},
            {"date_added": "13360000000000010", "id": "11", "name": "Yelp for Business", "type": "url", "url": "https://business.yelp.com/"},
            {"date_added": "13360000000000011", "id": "12", "name": "Google Business Profile", "type": "url", "url": "https://business.google.com/"},
            {"date_added": "13360000000000012", "id": "13", "name": "Netflix", "type": "url", "url": "https://www.netflix.com/"},
            {"date_added": "13360000000000013", "id": "14", "name": "Spotify", "type": "url", "url": "https://www.spotify.com/"},
            {"date_added": "13360000000000014", "id": "15", "name": "Reddit", "type": "url", "url": "https://www.reddit.com/"},
            {"date_added": "13360000000000015", "id": "16", "name": "DoorDash Merchant", "type": "url", "url": "https://merchants.doordash.com/"},
            {"date_added": "13360000000000016", "id": "17", "name": "QuickBooks", "type": "url", "url": "https://quickbooks.intuit.com/"},
            {"date_added": "13360000000000017", "id": "18", "name": "TripAdvisor", "type": "url", "url": "https://www.tripadvisor.com/"},
            {"date_added": "13360000000000018", "id": "19", "name": "Instagram", "type": "url", "url": "https://www.instagram.com/"},
            {"date_added": "13360000000000019", "id": "20", "name": "Steam", "type": "url", "url": "https://store.steampowered.com/"},
            {
               "date_added": "13360000000000020",
               "id": "21",
               "name": "Old Imports",
               "type": "folder",
               "children": [
                  {"date_added": "13360000000000021", "id": "22", "name": "WebstaurantStore", "type": "url", "url": "https://www.webstaurantstore.com/"},
                  {"date_added": "13360000000000022", "id": "23", "name": "ChefWorks", "type": "url", "url": "https://www.chefworks.com/"},
                  {"date_added": "13360000000000023", "id": "24", "name": "USDA HACCP", "type": "url", "url": "https://www.fsis.usda.gov/food-safety/haccp/"},
                  {"date_added": "13360000000000024", "id": "25", "name": "FDA Recalls", "type": "url", "url": "https://www.fda.gov/safety/recalls-market-withdrawals-safety-alerts"},
                  {"date_added": "13360000000000025", "id": "26", "name": "FoodSafety.gov", "type": "url", "url": "https://www.foodsafety.gov/"},
                  {"date_added": "13360000000000026", "id": "27", "name": "Chicago Health Dept", "type": "url", "url": "https://www.chicago.gov/city/en/depts/cdph/provdrs/healthy_restaurants.html"},
                  {"date_added": "13360000000000027", "id": "28", "name": "OpenTable Restaurant", "type": "url", "url": "https://restaurant.opentable.com/"},
                  {"date_added": "13360000000000028", "id": "29", "name": "ADP", "type": "url", "url": "https://www.adp.com/"},
                  {"date_added": "13360000000000029", "id": "30", "name": "Facebook Business", "type": "url", "url": "https://business.facebook.com/"},
                  {"date_added": "13360000000000030", "id": "31", "name": "Twitch", "type": "url", "url": "https://www.twitch.tv/"},
                  {"date_added": "13360000000000031", "id": "32", "name": "Gmail (personal)", "type": "url", "url": "https://mail.google.com/"},
                  {"date_added": "13360000000000032", "id": "33", "name": "When I Work (dup)", "type": "url", "url": "https://wheniwork.com/login"}
               ]
            }
         ],
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
BOOKMARKS_EOF
chown ga:ga "$CHROME_PROFILE/Bookmarks"

# 4. Create non-compliant preferences
echo "Creating initial preferences..."
cat > "$CHROME_PROFILE/Preferences" << 'PREFS_EOF'
{
   "browser": {
      "show_home_button": true,
      "custom_chrome_frame": false
   },
   "download": {
      "default_directory": "/home/ga/Downloads",
      "prompt_for_download": false
   },
   "homepage": "https://www.google.com",
   "homepage_is_newtabpage": false,
   "profile": {
      "password_manager_enabled": true,
      "default_content_setting_values": {
         "notifications": 1
      }
   },
   "autofill": {
      "profile_enabled": true,
      "credit_card_enabled": true
   },
   "safebrowsing": {
      "enabled": true,
      "enhanced": false
   },
   "session": {
      "restore_on_startup": 5
   }
}
PREFS_EOF
chown ga:ga "$CHROME_PROFILE/Preferences"

# 5. Write the specification document
cat > /home/ga/Desktop/restaurant_browser_standard.txt << 'SPEC_EOF'
RESTAURANT BROWSER CONFIGURATION STANDARD

1. BOOKMARKS
Organize all bookmarks into the following folders on the bookmark bar:
- Suppliers & Ordering (Sysco, US Foods, Restaurant Depot, WebstaurantStore, ChefWorks)
- Food Safety & Compliance (FDA, ServSafe, USDA HACCP, FoodSafety.gov, Chicago Health Dept)
- POS & Finance (Toast, Square, QuickBooks, DoorDash, OpenTable)
- Staff & Scheduling (7shifts, When I Work, Indeed, ADP)
- Marketing & Reviews (Yelp, Google Business, TripAdvisor, Instagram, Facebook)

Put all personal bookmarks (Netflix, Spotify, Reddit, Steam, Twitch, Gmail) in a folder called "Personal - Previous Manager".
Remove any other loose bookmarks or the "Old Imports" folder.

2. SEARCH ENGINES
Add these custom search engines:
- Keyword: sysco -> https://www.sysco.com/Contact/Contact/Product-Search.html?q=%s
- Keyword: recipe -> https://www.allrecipes.com/search?q=%s
- Keyword: safety -> https://search.usa.gov/search?utf8=✓&affiliate=fda1&query=%s

3. HOMEPAGE & STARTUP
- Homepage: https://pos.toasttab.com
- Startup pages (open specific pages): https://pos.toasttab.com, https://www.7shifts.com, https://www.sysco.com

4. DOWNLOADS
- Download directory: /home/ga/Documents/Restaurant_Files
- Turn ON "Ask where to save each file before downloading"

5. PRIVACY & SECURITY
- Block third-party cookies
- Default behavior for notifications: Block
- Safe Browsing: Enhanced Protection
- Disable password saving
- Disable address and payment method autofill
SPEC_EOF
chown ga:ga /home/ga/Desktop/restaurant_browser_standard.txt

# 6. Create download directory
mkdir -p /home/ga/Documents/Restaurant_Files
chown ga:ga /home/ga/Documents/Restaurant_Files

# 7. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="