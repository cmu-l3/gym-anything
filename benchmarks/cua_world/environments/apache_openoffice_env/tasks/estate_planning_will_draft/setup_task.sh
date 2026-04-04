#!/bin/bash
echo "=== Setting up Estate Planning Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/Draft_Will_Thorne.odt 2>/dev/null
rm -f /home/ga/Documents/client_intake.json 2>/dev/null
rm -f /home/ga/Documents/standard_clauses.txt 2>/dev/null

# 3. Create Client Intake JSON
cat > /home/ga/Documents/client_intake.json << 'EOF'
{
  "client": {
    "full_name": "Elias Thorne",
    "address": "42 Oak Ridge Ln, Asheville, NC 28803",
    "dob": "1965-04-12"
  },
  "family": {
    "spouse": "Clara Thorne",
    "children": [
      { "name": "Marcus Thorne", "dob": "1990-06-15", "relation": "Son" },
      { "name": "Sophie Thorne", "dob": "2014-11-02", "relation": "Daughter" }
    ]
  },
  "appointments": {
    "executor_primary": "Clara Thorne",
    "executor_alternate": "Marcus Thorne",
    "guardians_primary": "Sarah and James Miller"
  },
  "disposition": {
    "specific_bequests": [
      { "item": "1978 Gibson Les Paul Custom guitar", "beneficiary": "David Thorne (Brother)" },
      { "item": "Rolex Submariner Date watch", "beneficiary": "Marcus Thorne (Son)" }
    ],
    "residuary_beneficiary": "Clara Thorne"
  }
}
EOF
chown ga:ga /home/ga/Documents/client_intake.json

# 4. Create Standard Clauses Text
cat > /home/ga/Documents/standard_clauses.txt << 'EOF'
STANDARD WILL PROVISIONS - HIGHLAND ESTATE LAW

[INSTRUCTIONS: Copy text below. Replace bracketed placeholders like [CLIENT_NAME] with actual data.]

TITLE:
LAST WILL AND TESTAMENT OF [CLIENT_NAME]

INTRO:
I, [CLIENT_NAME], a resident of [CITY_STATE], being of sound mind, do hereby make, publish, and declare this to be my Last Will and Testament, revoking all prior Wills and Codicils.

ARTICLE I
IDENTIFICATION OF FAMILY
I am married to [SPOUSE_NAME], referred to herein as my "Spouse." I have the following children: [LIST_CHILDREN_NAMES].

ARTICLE II
APPOINTMENT OF EXECUTOR
I appoint my Spouse, [EXECUTOR_PRIMARY_NAME], as Executor of this Will. If they are unable or unwilling to serve, I appoint [EXECUTOR_ALTERNATE_NAME] as alternate Executor.

ARTICLE III
SPECIFIC BEQUESTS
I give, devise, and bequeath the following specific items:
[INSERT LIST OF BEQUESTS HERE: "I give [ITEM] to [BENEFICIARY]."]

ARTICLE IV
RESIDUARY ESTATE
I give all the rest, residue, and remainder of my estate, both real and personal, to my Spouse, [RESIDUARY_BENEFICIARY_NAME], if they survive me.

ARTICLE V
APPOINTMENT OF GUARDIAN
[INSTRUCTION: Include this Article ONLY if client has minor children (under 18).]
If my Spouse does not survive me, I appoint [GUARDIAN_NAMES] as Guardian(s) of the person and property of my minor children.

ARTICLE VI
POWERS OF EXECUTOR
My Executor shall have all powers granted by law, including the power to sell, lease, or mortgage real estate, and to settle claims for or against the estate.

SIGNATURE BLOCK:
IN WITNESS WHEREOF, I have signed this Will on this ____ day of __________, 20__.

____________________________________
[CLIENT_NAME], Testator

Witnesses:
____________________________________
____________________________________
EOF
chown ga:ga /home/ga/Documents/standard_clauses.txt

# 5. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Ensure OpenOffice Writer is running (Blank Document)
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="