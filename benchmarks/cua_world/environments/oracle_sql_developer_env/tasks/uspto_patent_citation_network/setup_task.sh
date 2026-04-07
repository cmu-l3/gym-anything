#!/bin/bash
# Setup script for USPTO Patent Citation Network Analysis task
echo "=== Setting up USPTO Patent Citation Network Analysis ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# --- Drop and recreate the USPTO_ANALYST user cleanly ---
echo "Setting up USPTO_ANALYST schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER uspto_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER uspto_analyst IDENTIFIED BY Uspto2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO uspto_analyst;
GRANT RESOURCE TO uspto_analyst;
GRANT CREATE VIEW TO uspto_analyst;
GRANT CREATE MATERIALIZED VIEW TO uspto_analyst;
GRANT CREATE SESSION TO uspto_analyst;
GRANT CREATE TABLE TO uspto_analyst;
EXIT;" "system"

echo "USPTO_ANALYST user created with required privileges"

# --- Create tables in USPTO schema ---
echo "Creating USPTO tables..."
sudo docker exec -i oracle-xe sqlplus -s uspto_analyst/Uspto2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE patents (
    patent_id NUMBER PRIMARY KEY,
    title VARCHAR2(500) NOT NULL,
    abstract CLOB,
    grant_date DATE NOT NULL,
    grant_year NUMBER(4) NOT NULL,
    num_claims NUMBER
);

CREATE TABLE assignees (
    assignee_id NUMBER PRIMARY KEY,
    organization VARCHAR2(200) NOT NULL,
    organization_type VARCHAR2(50),
    country VARCHAR2(2)
);

CREATE TABLE patent_assignees (
    patent_id NUMBER REFERENCES patents(patent_id),
    assignee_id NUMBER REFERENCES assignees(assignee_id),
    PRIMARY KEY (patent_id, assignee_id)
);

CREATE TABLE citations (
    citing_patent_id NUMBER REFERENCES patents(patent_id),
    cited_patent_id NUMBER REFERENCES patents(patent_id),
    citation_date DATE,
    PRIMARY KEY (citing_patent_id, cited_patent_id)
);

CREATE TABLE cpc_titles (
    cpc_subclass_id VARCHAR2(20) PRIMARY KEY,
    subclass_title VARCHAR2(200) NOT NULL
);

CREATE TABLE cpc_classifications (
    patent_id NUMBER REFERENCES patents(patent_id),
    cpc_section VARCHAR2(1),
    cpc_class VARCHAR2(5),
    cpc_subclass_id VARCHAR2(20) REFERENCES cpc_titles(cpc_subclass_id),
    is_primary NUMBER(1) DEFAULT 0,
    PRIMARY KEY (patent_id, cpc_subclass_id)
);

-- Insert baseline real-world anchors
INSERT INTO cpc_titles VALUES ('G06N 3/00', 'Computer systems based on biological models');
INSERT INTO cpc_titles VALUES ('G06N 5/00', 'Computer systems utilizing knowledge based models');
INSERT INTO cpc_titles VALUES ('G06N 20/00', 'Machine learning');
INSERT INTO cpc_titles VALUES ('G06N 7/00', 'Computer systems based on specific mathematical models');

INSERT INTO assignees VALUES (1, 'Google LLC', 'Corporation', 'US');
INSERT INTO assignees VALUES (2, 'International Business Machines Corporation', 'Corporation', 'US');
INSERT INTO assignees VALUES (3, 'Microsoft Technology Licensing, LLC', 'Corporation', 'US');
INSERT INTO assignees VALUES (4, 'Amazon Technologies, Inc.', 'Corporation', 'US');
INSERT INTO assignees VALUES (5, 'Stanford University', 'University', 'US');
INSERT INTO assignees VALUES (6, 'DeepMind Technologies Limited', 'Corporation', 'GB');

-- Anchor Patent (Google NN Patent)
INSERT INTO patents VALUES (8615473, 'System and method for training a neural network', 'Methods and systems for training neural networks...', DATE '2013-12-24', 2013, 20);
INSERT INTO patent_assignees VALUES (8615473, 1);
INSERT INTO cpc_classifications VALUES (8615473, 'G', 'G06', 'G06N 3/00', 1);

-- Forward citation level 1
INSERT INTO patents VALUES (9000001, 'Deep learning accelerator', 'Hardware...', DATE '2015-05-10', 2015, 15);
INSERT INTO patent_assignees VALUES (9000001, 1);
INSERT INTO citations VALUES (9000001, 8615473, DATE '2015-05-10');
INSERT INTO cpc_classifications VALUES (9000001, 'G', 'G06', 'G06N 3/00', 1);

INSERT INTO patents VALUES (9000002, 'Knowledge distillation framework', 'Software...', DATE '2015-08-12', 2015, 12);
INSERT INTO patent_assignees VALUES (9000002, 6);
INSERT INTO citations VALUES (9000002, 8615473, DATE '2015-08-12');

-- Forward citation level 2
INSERT INTO patents VALUES (9500001, 'Distributed neural network training', 'Software...', DATE '2016-11-01', 2016, 25);
INSERT INTO patent_assignees VALUES (9500001, 3);
INSERT INTO citations VALUES (9500001, 9000001, DATE '2016-11-01');

INSERT INTO patents VALUES (9500002, 'Cloud TPU controller', 'Hardware...', DATE '2016-12-15', 2016, 18);
INSERT INTO patent_assignees VALUES (9500002, 1);
INSERT INTO citations VALUES (9500002, 9000001, DATE '2016-12-15');

-- Forward citation level 3
INSERT INTO patents VALUES (10000001, 'Dynamic precision scaling for AI', 'Hardware...', DATE '2018-06-20', 2018, 22);
INSERT INTO patent_assignees VALUES (10000001, 2);
INSERT INTO citations VALUES (10000001, 9500001, DATE '2018-06-20');

-- Forward citation level 4
INSERT INTO patents VALUES (10500001, 'Quantum neural node optimizer', 'Quantum...', DATE '2019-12-10', 2019, 30);
INSERT INTO patent_assignees VALUES (10500001, 2);
INSERT INTO citations VALUES (10500001, 10000001, DATE '2019-12-10');

-- Highly Influential Patent (Target for MV)
INSERT INTO patents VALUES (7000000, 'Foundation of Support Vector Machines', '...', DATE '2010-01-01', 2010, 50);
INSERT INTO patent_assignees VALUES (7000000, 5);

-- PL/SQL block to generate a realistic background dataset
DECLARE
    v_patent_id NUMBER;
    v_assignee_id NUMBER;
    v_cpc VARCHAR2(20);
    v_year NUMBER;
    v_date DATE;
    TYPE t_cpc IS VARRAY(4) OF VARCHAR2(20);
    v_cpcs t_cpc := t_cpc('G06N 3/00', 'G06N 5/00', 'G06N 20/00', 'G06N 7/00');
BEGIN
    -- Create 150 generic assignees
    FOR i IN 10..159 LOOP
        INSERT INTO assignees VALUES (i, 'Tech Corp ' || i, 'Corporation', 'US');
    END LOOP;

    -- Generate ~5,000 background patents
    FOR i IN 1..5000 LOOP
        v_patent_id := 10000000 + i;
        v_year := 2010 + MOD(i, 14);
        v_date := TO_DATE(TO_CHAR(v_year) || '-06-15', 'YYYY-MM-DD');
        
        INSERT INTO patents VALUES (v_patent_id, 'AI Method ' || i, 'Abstract ' || i, v_date, v_year, MOD(i, 20)+5);
        
        -- Assignee logic (IBM=2 gets lots of patents to trigger self-citation, Google=1 gets many too)
        IF MOD(i, 10) = 0 THEN v_assignee_id := 2; -- IBM heavily represented
        ELSIF MOD(i, 15) = 0 THEN v_assignee_id := 1;
        ELSIF MOD(i, 20) = 0 THEN v_assignee_id := 3;
        ELSE v_assignee_id := 10 + MOD(i, 150);
        END IF;
        
        INSERT INTO patent_assignees VALUES (v_patent_id, v_assignee_id);
        
        v_cpc := v_cpcs(MOD(i, 4) + 1);
        INSERT INTO cpc_classifications VALUES (v_patent_id, 'G', 'G06', v_cpc, 1);
        
        -- Generate citations
        -- 1. Cite the highly influential patent often (to reach 100+ unique assignees)
        IF MOD(i, 30) = 0 THEN
            INSERT INTO citations VALUES (v_patent_id, 7000000, v_date);
        END IF;
        
        -- 2. IBM self-citations (simulate inflation)
        IF v_assignee_id = 2 AND i > 100 AND MOD(i, 2) = 0 THEN
            BEGIN
                INSERT INTO citations VALUES (v_patent_id, 10000000 + MOD(i-10, i-1), v_date);
            EXCEPTION WHEN OTHERS THEN NULL; END;
        END IF;
    END LOOP;
    COMMIT;
END;
/
EXIT;
EOSQL

echo "Background dataset generated successfully."

# Pre-configure SQL Developer connection
ensure_hr_connection "USPTO Database" "uspto_analyst" "Uspto2024"

# Open SQL Developer
echo "Launching Oracle SQL Developer..."
if [ -x "/opt/sqldeveloper/sqldeveloper.sh" ]; then
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 JAVA_TOOL_OPTIONS='--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED --add-opens=java.base/sun.net.www=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false' /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"
    
    # Wait for window
    sleep 15
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
            break
        fi
        sleep 1
    done
    
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="