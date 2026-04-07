#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Community Resource Navigator Task ==="

# 1. Kill any running Chrome instances
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 1
pkill -9 -f "google-chrome" 2>/dev/null || true
pkill -9 -f "chromium" 2>/dev/null || true
sleep 1

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Clean and prepare Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
CHROME_CONFIG="/home/ga/.config/google-chrome"
mkdir -p "$CHROME_PROFILE"
rm -f "$CHROME_PROFILE/Bookmarks" "$CHROME_PROFILE/Preferences" "$CHROME_CONFIG/Local State"

# Create default empty Bookmarks so Chrome doesn't prompt
cat > "$CHROME_PROFILE/Bookmarks" << 'EOF'
{"checksum": "","roots": {"bookmark_bar": {"children": [],"date_added": "13000000000000000","date_modified": "0","id": "1","name": "Bookmarks bar","type": "folder"},"other": {"children": [],"date_added": "13000000000000000","date_modified": "0","id": "2","name": "Other bookmarks","type": "folder"},"synced": {"children": [],"date_added": "13000000000000000","date_modified": "0","id": "3","name": "Mobile bookmarks","type": "folder"}},"version": 1}
EOF

chown -R ga:ga "$CHROME_CONFIG"

# 4. Generate the Colleague Bookmarks HTML file (Netscape format)
cat > "/home/ga/Desktop/colleague_bookmarks.html" << 'HTML_EOF'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an exported bookmark file -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><A HREF="https://hud.gov/topics/rental_assistance">HUD Rental Assistance</A>
    <DT><A HREF="https://www.huduser.gov/">HUD User</A>
    <DT><A HREF="https://nlihc.org/">National Low Income Housing Coalition</A>
    <DT><A HREF="https://www.salvationarmyusa.org/">Salvation Army</A>
    <DT><A HREF="https://endhomelessness.org/">End Homelessness</A>
    <DT><A HREF="https://www.fns.usda.gov/snap">SNAP Benefits</A>
    <DT><A HREF="https://www.feedingamerica.org/">Feeding America</A>
    <DT><A HREF="https://www.mealsonwheelsamerica.org/">Meals on Wheels</A>
    <DT><A HREF="https://www.healthcare.gov/">Healthcare.gov</A>
    <DT><A HREF="https://findahealthcenter.hrsa.gov/">Find a Health Center</A>
    <DT><A HREF="https://www.hrsa.gov/">HRSA</A>
    <DT><A HREF="https://www.samhsa.gov/">SAMHSA</A>
    <DT><A HREF="https://www.mentalhealth.gov/">MentalHealth.gov</A>
    <DT><A HREF="https://findtreatment.gov/">Find Treatment</A>
    <DT><A HREF="https://www.thehotline.org/">Domestic Violence Hotline</A>
    <DT><A HREF="https://ncadv.org/">NCADV</A>
    <DT><A HREF="https://www.veteranscrisisline.net/">Veterans Crisis Line</A>
    <DT><A HREF="https://suicidepreventionlifeline.org/">Suicide Prevention Lifeline</A>
    <DT><A HREF="https://www.lsc.gov/">Legal Services Corporation</A>
    <DT><A HREF="https://www.lawhelp.org/">LawHelp</A>
    <DT><A HREF="https://abafreelegalanswers.org/">ABA Free Legal Answers</A>
    <DT><A HREF="https://www.uscis.gov/">USCIS</A>
    <DT><A HREF="https://www.immigrationadvocates.org/">Immigration Advocates</A>
    <DT><A HREF="https://www.careeronestop.org/">CareerOneStop</A>
    <DT><A HREF="https://www.dol.gov/">Department of Labor</A>
    <DT><A HREF="https://www.goodwill.org/">Goodwill</A>
    <DT><A HREF="https://studentaid.gov/">Federal Student Aid</A>
    <DT><A HREF="https://www.ed.gov/">Department of Education</A>
    <DT><A HREF="https://mygreatlakes.org/">Great Lakes Educational</A>
    <DT><A HREF="https://www.benefits.gov/">Benefits.gov</A>
    <DT><A HREF="https://www.211.org/">211 Essential Community Services</A>
    <DT><A HREF="https://www.usa.gov/">USA.gov</A>
    <DT><A HREF="https://www.ssa.gov/disability">SSA Disability</A>
    <DT><A HREF="https://acl.gov/">Administration for Community Living</A>
    <DT><A HREF="https://www.childwelfare.gov/">Child Welfare Info Gateway</A>
    <DT><A HREF="https://www.acf.hhs.gov/">Administration for Children and Families</A>
    <DT><A HREF="https://www.va.gov/">Veterans Affairs</A>
    <DT><A HREF="https://eldercare.acl.gov/">Eldercare Locator</A>
    <DT><A HREF="https://www.medicaid.gov/">Medicaid</A>
    <DT><A HREF="https://www.mhanational.org/">Mental Health America</A>
</DL><p>
HTML_EOF

# 5. Generate the Agency Browser Guide
cat > "/home/ga/Desktop/agency_browser_guide.txt" << 'GUIDE_EOF'
FAMILY RESOURCE CENTER - BROWSER CONFIGURATION GUIDE v1.0

You are setting up a shared intake workstation. Please configure Chrome exactly as follows:

1. BOOKMARK IMPORT & ORGANIZATION
Import the "colleague_bookmarks.html" file from the Desktop (Bookmark Manager -> Import).
Organize ALL imported bookmarks into exactly 5 folders on the Bookmark Bar:
  - "Housing & Basic Needs": HUD, NLIHC, Salvation Army, End Homelessness, SNAP, Feeding America, Meals on Wheels
  - "Health & Crisis Services": Healthcare.gov, HRSA, SAMHSA, MentalHealth, Find Treatment, DV Hotline, NCADV, Veterans/Suicide Lifeline, MHA
  - "Legal & Immigration": LSC, LawHelp, ABA, USCIS, Immigration Advocates
  - "Employment & Education": CareerOneStop, DOL, Goodwill, StudentAid, ED.gov, Great Lakes
  - "Benefits & Government": Benefits.gov, 211, USA.gov, SSA, ACL, Child Welfare, ACF, VA, Eldercare, Medicaid

2. SEARCH ENGINE SHORTCUTS (Settings -> Search engine -> Manage search engines and site search -> Site search)
Add these 3 site search shortcuts:
  - Search engine: 211 / Shortcut: 211 / URL: https://www.211.org/search?q=%s
  - Search engine: LawHelp / Shortcut: law / URL: https://www.lawhelp.org/search?q=%s
  - Search engine: Benefits / Shortcut: benefits / URL: https://www.benefits.gov/search?q=%s

3. HOMEPAGE & STARTUP
  - Show Home button -> Custom web address: https://www.211.org
  - On startup -> Open a specific page or set of pages: Add https://www.211.org AND https://www.benefits.gov

4. ACCESSIBILITY SETTINGS (Settings -> Appearance)
Because we screen-share with clients, make the text larger:
  - Font size: Go to "Customize fonts"
  - Set "Font size" (Default) to 20
  - Set "Minimum font size" to 14

5. CHROME FLAGS (chrome://flags)
Enable these two experimental features for better reading performance:
  - Search for "Smooth Scrolling" and set to Enabled
  - Search for "Reader Mode" and set to Enabled

6. PRIVACY & SECURITY (Shared Workstation hardening)
  - Settings -> Privacy and security -> Third-party cookies -> Select "Block third-party cookies"
  - Settings -> Autofill and passwords -> Google Password Manager -> Settings -> Turn OFF "Offer to save passwords"
  - Settings -> Autofill and passwords -> Addresses and more -> Turn OFF "Save and fill addresses"
GUIDE_EOF

chown ga:ga "/home/ga/Desktop/colleague_bookmarks.html"
chown ga:ga "/home/ga/Desktop/agency_browser_guide.txt"

# 6. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check about:blank > /dev/null 2>&1 &"
sleep 4

# Wait for Chrome window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        break
    fi
    sleep 1
done

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="