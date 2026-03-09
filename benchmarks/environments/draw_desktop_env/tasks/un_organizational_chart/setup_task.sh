#!/bin/bash
echo "=== Setting up UN Organizational Chart task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Desktop/un_org_chart.drawio
rm -f /home/ga/Desktop/un_org_chart.png
rm -f /tmp/task_result.json

# Create the UN system reference file (real data from official UN documentation)
cat > /home/ga/Desktop/un_system_reference.txt << 'REFEOF'
============================================================
UNITED NATIONS SYSTEM — ORGANIZATIONAL REFERENCE
Source: UN System Chief Executives Board for Coordination (CEB)
        UN Charter (1945), Chapters III–XV
============================================================

THE UNITED NATIONS

The UN system comprises six PRINCIPAL ORGANS established by the Charter,
numerous subsidiary bodies, programmes and funds, and specialized agencies.

--------------------------------------------------------------
1. GENERAL ASSEMBLY (GA)
--------------------------------------------------------------
   The main deliberative organ. All 193 Member States represented.
   Key subsidiary bodies, programmes, and funds:
   - UNHCR  (UN High Commissioner for Refugees)
   - UNICEF (UN Children's Fund)
   - UNDP   (UN Development Programme)
   - UNEP   (UN Environment Programme)
   - WFP    (World Food Programme)
   - Human Rights Council
   - UN Women (UN Entity for Gender Equality)
   - UNCTAD (UN Conference on Trade and Development)
   - UNODC  (UN Office on Drugs and Crime)
   - UNRWA  (UN Relief and Works Agency)

--------------------------------------------------------------
2. SECURITY COUNCIL (SC)
--------------------------------------------------------------
   Primary responsibility for maintenance of international
   peace and security. 5 permanent + 10 non-permanent members.
   Key subsidiary bodies:
   - Peacekeeping Operations (DPKO missions)
   - Sanctions Committees (per-country/per-regime)
   - Counter-Terrorism Committee (CTC)
   - International Criminal Tribunals (ICTY, ICTR legacy)
   - Military Staff Committee
   - Peacebuilding Commission (joint with GA)

--------------------------------------------------------------
3. ECONOMIC AND SOCIAL COUNCIL (ECOSOC)
--------------------------------------------------------------
   Coordinates economic, social, and environmental work of
   14 specialized agencies, functional commissions, and
   5 regional commissions. 54 members elected by GA.
   Functional Commissions:
   - Commission on the Status of Women (CSW)
   - Commission on Narcotic Drugs (CND)
   - Statistical Commission
   - Commission on Population and Development
   - Commission on Crime Prevention and Criminal Justice
   Regional Commissions:
   - ECA  (Economic Commission for Africa)
   - ECE  (Economic Commission for Europe)
   - ECLAC (Economic Commission for Latin America and the Caribbean)
   - ESCAP (Economic and Social Commission for Asia and the Pacific)
   - ESCWA (Economic and Social Commission for Western Asia)

--------------------------------------------------------------
4. INTERNATIONAL COURT OF JUSTICE (ICJ)
--------------------------------------------------------------
   Principal judicial organ. Seated in The Hague, Netherlands.
   15 judges elected jointly by GA and SC for 9-year terms.
   Settles legal disputes between States and gives advisory opinions.

--------------------------------------------------------------
5. SECRETARIAT
--------------------------------------------------------------
   International staff carrying out the day-to-day work of the UN.
   Headed by the Secretary-General.
   Key departments and offices:
   - Office of the Secretary-General (OSG)
   - DPPA  (Department of Political and Peacebuilding Affairs)
   - DPO   (Department of Peace Operations)
   - OCHA  (Office for the Coordination of Humanitarian Affairs)
   - DESA  (Department of Economic and Social Affairs)
   - OLA   (Office of Legal Affairs)
   - DSS   (Department of Safety and Security)
   - DGACM (Department for General Assembly and Conference Management)

--------------------------------------------------------------
6. TRUSTEESHIP COUNCIL
--------------------------------------------------------------
   Established to oversee Trust Territories' transition to
   self-governance. Operations suspended on 1 November 1994
   when the last Trust Territory (Palau) gained independence.
   The Council has amended its rules to meet as occasion requires.

==============================================================
SPECIALIZED AGENCIES
==============================================================
Autonomous organizations linked to the UN through formal
agreements. They coordinate with ECOSOC and report to the GA.

- WHO    — World Health Organization (Health)
- UNESCO — UN Educational, Scientific and Cultural Organization
           (Education, Science, Culture)
- FAO    — Food and Agriculture Organization (Food, Agriculture)
- ILO    — International Labour Organization (Labour Standards)
- IMF    — International Monetary Fund (Monetary Cooperation)
- World Bank Group — IBRD/IDA (Development Finance)
- ICAO   — International Civil Aviation Organization (Aviation)
- WMO    — World Meteorological Organization (Weather, Climate)
- WIPO   — World Intellectual Property Organization (IP)
- ITU    — International Telecommunication Union (Telecom)
- UNIDO  — UN Industrial Development Organization (Industry)
- IFAD   — International Fund for Agricultural Development
           (Rural Development)
- UNWTO  — UN World Tourism Organization (Tourism)
- UPU    — Universal Postal Union (Postal Services)
- IMO    — International Maritime Organization (Shipping)

==============================================================
DIAGRAM INSTRUCTIONS
==============================================================
Page 1: "UN Principal Organs"
  - Place "United Nations" at the top
  - Show 6 principal organs in a row below
  - Under each organ, list its key subsidiary bodies
  - Use hierarchical connecting lines
  - Color-code each branch with a distinct fill color

Page 2: "Specialized Agencies"
  - Show the 15 specialized agencies
  - Label each with abbreviation and domain
  - Connect to ECOSOC/General Assembly coordination path
==============================================================
REFEOF

chown ga:ga /home/ga/Desktop/un_system_reference.txt
echo "  - Created un_system_reference.txt"

# Ensure draw.io is not running (clean state)
pkill -f drawio 2>/dev/null || true
sleep 2

# Remove singleton locks
rm -f /home/ga/.config/draw.io/SingletonCookie \
      /home/ga/.config/draw.io/SingletonLock \
      /home/ga/.config/draw.io/SingletonSocket 2>/dev/null || true

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true drawio --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# Wait for window to appear
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw\\.io\|drawio\|diagram"; then
        echo "  - draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done
sleep 3

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss the startup dialog (Create New / Open Existing)
# Pressing Escape twice usually clears the dialog and any "Untitled Diagram" prompt
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== UN Org Chart task setup complete ==="
echo "Reference file: ~/Desktop/un_system_reference.txt"