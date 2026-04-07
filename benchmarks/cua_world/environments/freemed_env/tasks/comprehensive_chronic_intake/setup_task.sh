#!/bin/bash
# Setup task: comprehensive_chronic_intake
# New patient: Elena Vasquez-Moreno (DOB 1966-04-23, F) — must NOT exist at task start
# Also cleans insurance company "Northeastern Health Partners" for fresh admin setup

echo "=== Setting up comprehensive_chronic_intake ==="

source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Clean up any prior attempt data (delete stale outputs FIRST)
# ---------------------------------------------------------------

rm -f /tmp/comprehensive_chronic_intake_result.json 2>/dev/null || true
rm -f /tmp/comprehensive_chronic_intake_start.png 2>/dev/null || true
rm -f /tmp/comprehensive_chronic_intake_end.png 2>/dev/null || true
rm -f /tmp/cci_initial_* 2>/dev/null || true
rm -f /tmp/task_start_timestamp 2>/dev/null || true

# ---------------------------------------------------------------
# 2. Ensure all required tables exist (FreeMED creates some lazily)
# ---------------------------------------------------------------

echo "Ensuring required database tables exist..."

# Create tables directly (FreeMED schema SOURCE directives are fragile)
mysql -u root freemed -e "
CREATE TABLE IF NOT EXISTS current_problems (
    pdate DATE NOT NULL, problem VARCHAR(250) NOT NULL DEFAULT '',
    ppatient BIGINT UNSIGNED NOT NULL DEFAULT 0,
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, KEY (ppatient, pdate));
CREATE TABLE IF NOT EXISTS allergies (
    allergies VARCHAR(250), patient BIGINT UNSIGNED NOT NULL DEFAULT 0,
    reviewed TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user INT UNSIGNED NOT NULL DEFAULT 0,
    active ENUM('active','inactive') NOT NULL DEFAULT 'active',
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, KEY (patient, allergies));
CREATE TABLE IF NOT EXISTS allergies_atomic (
    aid BIGINT UNSIGNED NOT NULL DEFAULT 0, allergy VARCHAR(150) NOT NULL,
    reaction VARCHAR(150) NOT NULL, severity VARCHAR(150) NOT NULL,
    patient BIGINT UNSIGNED NOT NULL DEFAULT 0, reviewed DATE,
    user INT UNSIGNED NOT NULL DEFAULT 0,
    active ENUM('active','inactive') NOT NULL DEFAULT 'active',
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, KEY (allergy, reviewed));
CREATE TABLE IF NOT EXISTS medications (
    mpatient BIGINT UNSIGNED NOT NULL DEFAULT 0, mdate DATE,
    mdrugs VARCHAR(250), locked INT UNSIGNED NOT NULL DEFAULT 0,
    user INT UNSIGNED NOT NULL DEFAULT 0,
    active ENUM('active','inactive') NOT NULL DEFAULT 'active',
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, KEY (mpatient, mdate));
CREATE TABLE IF NOT EXISTS medications_atomic (
    mid BIGINT UNSIGNED NOT NULL DEFAULT 0, mdrug VARCHAR(150),
    mdosage VARCHAR(150), mroute VARCHAR(150),
    minterval ENUM('BID','TID','QID','Q3H','Q4H','Q5H','Q6H','Q8H','QD','HS','QHS','QAM','QPM','AC','PC','PRN','QSHIFT','QOD','C','Once') NOT NULL DEFAULT 'Once',
    mprescriber INT UNSIGNED NOT NULL DEFAULT 0,
    mpatient BIGINT UNSIGNED NOT NULL DEFAULT 0, mdate DATE,
    user INT UNSIGNED NOT NULL DEFAULT 0,
    active ENUM('active','inactive') NOT NULL DEFAULT 'active',
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, KEY (mpatient, mdate));
CREATE TABLE IF NOT EXISTS coverage (
    covdtadd DATE, covdtmod DATE,
    covpatient BIGINT UNSIGNED NOT NULL DEFAULT 0, coveffdt TEXT,
    covinsco INT UNSIGNED, covpatinsno VARCHAR(50) NOT NULL,
    covpatgrpno VARCHAR(50), covtype INT UNSIGNED,
    covstatus INT UNSIGNED DEFAULT 0, covrel CHAR(2) NOT NULL DEFAULT 'S',
    covlname VARCHAR(50), covfname VARCHAR(50), covmname CHAR(1),
    covaddr1 VARCHAR(25), covaddr2 VARCHAR(25), covcity VARCHAR(25),
    covstate CHAR(3), covzip VARCHAR(10), covdob DATE,
    covsex ENUM('m','f','t'), covssn CHAR(9), covinstp INT UNSIGNED,
    covprovasgn INT UNSIGNED, covbenasgn INT UNSIGNED, covrelinfo INT UNSIGNED,
    covrelinfodt DATE, covplanname VARCHAR(33),
    covisassigning INT UNSIGNED NOT NULL DEFAULT 1, covschool VARCHAR(50),
    covemployer VARCHAR(50), covcopay REAL, covdeduct REAL,
    user INT UNSIGNED NOT NULL DEFAULT 0,
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    KEY (covpatient, covinsco, covrel), KEY (covpatinsno));
" 2>/dev/null || true

echo "Table creation complete"

# ---------------------------------------------------------------
# 3. Clean patient Elena Vasquez-Moreno and all associated records
# ---------------------------------------------------------------

# Delete clinical data linked to any Elena Vasquez patient (use || true since tables may still not exist)
freemed_query "DELETE FROM scheduler WHERE calpatient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM referrals WHERE refpatient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM pnotes WHERE pnotespat IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM vitals WHERE patient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM rx WHERE rxpatient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM medications WHERE mpatient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM medications_atomic WHERE mpatient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM current_problems WHERE ppatient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM allergies_atomic WHERE patient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM allergies WHERE patient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM coverage WHERE covpatient IN (SELECT id FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%')" 2>/dev/null || true
freemed_query "DELETE FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%'" 2>/dev/null || true

# Verify patient removed
PATIENT_CHECK=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%'" 2>/dev/null || echo "0")
echo "Elena Vasquez count after cleanup: $PATIENT_CHECK"

if [ "${PATIENT_CHECK:-0}" -gt 0 ]; then
    echo "ERROR: Could not remove existing Elena Vasquez entries!"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Clean insurance company "Northeastern Health Partners"
# ---------------------------------------------------------------

freemed_query "DELETE FROM insco WHERE insconame LIKE '%Northeastern Health%'" 2>/dev/null || true

INSCO_CHECK=$(freemed_query "SELECT COUNT(*) FROM insco WHERE insconame LIKE '%Northeastern Health%'" 2>/dev/null || echo "0")
echo "Northeastern Health Partners count after cleanup: $INSCO_CHECK"

# ---------------------------------------------------------------
# 5. Ensure referral target Dr. Anita Patel exists as a user/provider
#    (FreeMED stores providers in the 'user' table, not a separate physician table)
# ---------------------------------------------------------------

PATEL_EXISTS=$(freemed_query "SELECT COUNT(*) FROM user WHERE userfname='Anita' AND userlname='Patel'" 2>/dev/null || echo "0")
if [ "${PATEL_EXISTS:-0}" -eq 0 ]; then
    freemed_query "INSERT INTO user (username, userpassword, userdescrip, usertype, userfname, userlname, usermname, usertitle) VALUES ('apatel', MD5('apatel123'), 'Endocrinologist', 'phy', 'Anita', 'Patel', '', 'Dr.')" 2>/dev/null || true
    echo "Inserted Dr. Anita Patel into user table as provider"
else
    echo "Dr. Anita Patel already exists in user table"
fi

# ---------------------------------------------------------------
# 6. Record initial baselines
# ---------------------------------------------------------------

INITIAL_PATIENTS=$(freemed_query "SELECT COUNT(*) FROM patient" 2>/dev/null || echo "0")
INITIAL_INSCO=$(freemed_query "SELECT COUNT(*) FROM insco" 2>/dev/null || echo "0")

echo "$INITIAL_PATIENTS" > /tmp/cci_initial_patients
echo "$INITIAL_INSCO" > /tmp/cci_initial_insco

echo "Initial counts — patients: $INITIAL_PATIENTS, insco: $INITIAL_INSCO"

# ---------------------------------------------------------------
# 7. Record task start timestamp
# ---------------------------------------------------------------

date +%s > /tmp/task_start_timestamp

# ---------------------------------------------------------------
# 8. Launch FreeMED in Firefox
# ---------------------------------------------------------------

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/comprehensive_chronic_intake_start.png

echo ""
echo "=== Setup Complete ==="
echo "New patient: Elena Vasquez-Moreno (DOB: 1966-04-23, Female)"
echo "Insurance: Northeastern Health Partners (must be added to system)"
echo "Dr. Anita Patel available as referral target"
echo "Task: Register patient + insurance + coverage + 2 dx + allergy + Rx + vitals + referral + note + appointment"
echo "Login: admin / admin at http://localhost/freemed/"
echo ""
