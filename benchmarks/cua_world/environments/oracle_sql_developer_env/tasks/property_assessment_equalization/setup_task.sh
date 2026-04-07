#!/bin/bash
echo "=== Setting up Property Assessment Equalization Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# Wait for DB to be responsive
sleep 5

# --- Drop and recreate the COUNTY_ASSESSOR user cleanly ---
echo "Setting up COUNTY_ASSESSOR schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER county_assessor CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER county_assessor IDENTIFIED BY Assess2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO county_assessor;
GRANT RESOURCE TO county_assessor;
GRANT CREATE VIEW TO county_assessor;
GRANT CREATE PROCEDURE TO county_assessor;
GRANT CREATE SESSION TO county_assessor;
GRANT CREATE TABLE TO county_assessor;
GRANT CREATE SEQUENCE TO county_assessor;
EXIT;" "system"

echo "COUNTY_ASSESSOR user created with required privileges"

# --- Create tables in COUNTY_ASSESSOR schema ---
echo "Creating tables..."
oracle_query "
CREATE TABLE neighborhoods (
    neighborhood_id NUMBER PRIMARY KEY,
    neighborhood_name VARCHAR2(100),
    township VARCHAR2(50),
    land_use_primary VARCHAR2(30),
    median_household_income NUMBER,
    total_parcels NUMBER
);

CREATE TABLE properties (
    parcel_id VARCHAR2(14) PRIMARY KEY,
    neighborhood_id NUMBER REFERENCES neighborhoods(neighborhood_id),
    address VARCHAR2(200),
    city VARCHAR2(50),
    zip_code VARCHAR2(10),
    property_class NUMBER(3),
    year_built NUMBER(4),
    living_area_sqft NUMBER,
    lot_size_sqft NUMBER,
    bedrooms NUMBER(2),
    bathrooms NUMBER(3,1),
    stories NUMBER(3,1),
    condition_code VARCHAR2(1)
);

CREATE TABLE assessments (
    assessment_id NUMBER PRIMARY KEY,
    parcel_id VARCHAR2(14) REFERENCES properties(parcel_id),
    tax_year NUMBER(4),
    land_value NUMBER(12,2),
    improvement_value NUMBER(12,2),
    total_assessed_value NUMBER(12,2),
    assessment_level NUMBER(5,4),
    last_reassessment_date DATE,
    CONSTRAINT uk_parcel_year UNIQUE (parcel_id, tax_year)
);

CREATE TABLE sales (
    sale_id NUMBER PRIMARY KEY,
    parcel_id VARCHAR2(14) REFERENCES properties(parcel_id),
    sale_date DATE,
    sale_price NUMBER(12,2),
    sale_type VARCHAR2(30),
    instrument_number VARCHAR2(20),
    grantor VARCHAR2(100),
    grantee VARCHAR2(100),
    is_arms_length VARCHAR2(1)
);

CREATE TABLE property_features (
    parcel_id VARCHAR2(14) REFERENCES properties(parcel_id),
    has_fireplace VARCHAR2(1),
    has_pool VARCHAR2(1),
    has_garage VARCHAR2(1),
    has_basement VARCHAR2(1),
    has_central_air VARCHAR2(1),
    has_deck VARCHAR2(1)
);

CREATE TABLE tax_districts (
    district_id NUMBER PRIMARY KEY,
    district_name VARCHAR2(100),
    district_type VARCHAR2(30),
    tax_rate NUMBER(8,6),
    levy_amount NUMBER(14,2)
);

CREATE TABLE parcel_districts (
    parcel_id VARCHAR2(14) REFERENCES properties(parcel_id),
    district_id NUMBER REFERENCES tax_districts(district_id),
    PRIMARY KEY (parcel_id, district_id)
);
EXIT;" "county_assessor" "Assess2024"

# --- Generate Data using PL/SQL ---
echo "Generating property, assessment, and sales data..."
oracle_query "
DECLARE
    v_parcel_id VARCHAR2(14);
    v_sale_price NUMBER;
    v_total_av NUMBER;
    v_land_av NUMBER;
    v_imp_av NUMBER;
BEGIN
    -- Insert Neighborhoods
    INSERT INTO neighborhoods VALUES (1, 'Oakwood Estates', 'Northfield', 'RESIDENTIAL', 95000, 100);
    INSERT INTO neighborhoods VALUES (2, 'Pine Valley', 'Southfield', 'RESIDENTIAL', 85000, 100);
    INSERT INTO neighborhoods VALUES (3, 'River Walk', 'Eastfield', 'RESIDENTIAL', 120000, 100);

    -- Insert Tax Districts
    INSERT INTO tax_districts VALUES (1, 'Northfield School District 101', 'SCHOOL', 0.0450, 1500000);
    INSERT INTO tax_districts VALUES (2, 'Southfield School District 102', 'SCHOOL', 0.0520, 1800000);
    INSERT INTO tax_districts VALUES (3, 'County General Fund', 'COUNTY', 0.0120, 5000000);
    INSERT INTO tax_districts VALUES (4, 'Oakwood Park District', 'PARK', 0.0050, 250000);
    
    -- Generate 30 properties (10 per neighborhood)
    FOR i IN 1..30 LOOP
        v_parcel_id := '14-' || TO_CHAR(i, 'FM00000');
        
        -- Neighborhood 1: Compliant (Ratio ~ 0.33)
        -- Neighborhood 2: Non-Compliant / Under-assessed (Ratio ~ 0.25)
        -- Neighborhood 3: Non-Compliant / High Dispersion (COD > 15)
        
        IF i <= 10 THEN
            INSERT INTO properties VALUES (v_parcel_id, 1, i || ' Oak St', 'Northfield', '60001', 200, 1990, 2000, 10000, 3, 2, 2, 'A');
            v_sale_price := 300000 + MOD(i*10000, 50000);
            v_total_av := v_sale_price * 0.33; -- Perfect assessment
        ELSIF i <= 20 THEN
            INSERT INTO properties VALUES (v_parcel_id, 2, i || ' Pine St', 'Southfield', '60002', 200, 1985, 1800, 8000, 3, 1.5, 1, 'A');
            v_sale_price := 400000 + MOD(i*15000, 60000);
            v_total_av := v_sale_price * 0.25; -- Under-assessed
        ELSE
            INSERT INTO properties VALUES (v_parcel_id, 3, i || ' River Rd', 'Eastfield', '60003', 200, 2005, 2500, 12000, 4, 2.5, 2, 'G');
            v_sale_price := 500000 + MOD(i*20000, 80000);
            -- High dispersion: alternate between over and under assessed
            IF MOD(i, 2) = 0 THEN
                v_total_av := v_sale_price * 0.20; 
            ELSE
                v_total_av := v_sale_price * 0.46;
            END IF;
        END IF;

        v_land_av := ROUND(v_total_av * 0.2, 2);
        v_imp_av := ROUND(v_total_av * 0.8, 2);
        v_total_av := v_land_av + v_imp_av;

        INSERT INTO assessments VALUES (i, v_parcel_id, 2024, v_land_av, v_imp_av, v_total_av, 0.33, SYSDATE - 365);
        INSERT INTO sales VALUES (i, v_parcel_id, SYSDATE - MOD(i*10, 300), v_sale_price, 'ARM_LENGTH', 'DOC-'||i, 'Seller '||i, 'Buyer '||i, 'Y');
        
        -- Insert features for UNPIVOT
        INSERT INTO property_features VALUES (
            v_parcel_id,
            CASE WHEN MOD(i, 2) = 0 THEN 'Y' ELSE 'N' END, -- fireplace
            CASE WHEN MOD(i, 5) = 0 THEN 'Y' ELSE 'N' END, -- pool
            'Y', -- garage
            CASE WHEN MOD(i, 3) = 0 THEN 'Y' ELSE 'N' END, -- basement
            'Y', -- central_air
            CASE WHEN MOD(i, 4) = 0 THEN 'Y' ELSE 'N' END  -- deck
        );

        -- Insert tax districts for LISTAGG
        INSERT INTO parcel_districts VALUES (v_parcel_id, 3); -- everyone in county
        IF i <= 10 THEN
            INSERT INTO parcel_districts VALUES (v_parcel_id, 1);
            INSERT INTO parcel_districts VALUES (v_parcel_id, 4);
        ELSE
            INSERT INTO parcel_districts VALUES (v_parcel_id, 2);
        END IF;

    END LOOP;
    COMMIT;
END;
/
EXIT;" "county_assessor" "Assess2024"

# Ensure we have a clean EQUALIZATION_FACTORS table drop just in case
oracle_query "BEGIN EXECUTE IMMEDIATE 'DROP TABLE equalization_factors'; EXCEPTION WHEN OTHERS THEN NULL; END; / EXIT;" "county_assessor" "Assess2024" 2>/dev/null

# Record initial sum of assessments to verify MERGE success
INITIAL_ASSESSMENT_SUM=$(oracle_query_raw "SELECT SUM(total_assessed_value) FROM county_assessor.assessments WHERE tax_year = 2024;" "system" | tr -d '[:space:]')
echo "$INITIAL_ASSESSMENT_SUM" > /tmp/initial_assessment_sum.txt
echo "Initial assessment sum: $INITIAL_ASSESSMENT_SUM"

# Ensure connections are prepared for the user in SQL Developer
ensure_hr_connection "County Assessor" "county_assessor" "Assess2024"

# Open SQL Developer
echo "Launching Oracle SQL Developer..."
if ! pgrep -f "sqldeveloper" > /dev/null; then
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 /opt/sqldeveloper/sqldeveloper.sh > /dev/null 2>&1 &"
    
    # Wait for window to appear
    for i in {1..40}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "sql developer\|oracle sql"; then
            break
        fi
        sleep 1
    done
fi

# Maximize SQL Developer
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Try to open the connection
open_hr_connection_in_sqldeveloper

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="