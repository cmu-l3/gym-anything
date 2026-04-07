#!/bin/bash
echo "=== Setting up University Academic Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# 1. Verify Oracle is running
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER registrar CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
rm -f /home/ga/Documents/prereq_violations.csv 2>/dev/null || true
sleep 2

# ---------------------------------------------------------------
# 3. Create REGISTRAR schema
# ---------------------------------------------------------------
echo "Creating REGISTRAR schema..."
oracle_query "CREATE USER registrar IDENTIFIED BY Registrar2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE MATERIALIZED VIEW TO registrar;
GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE TO registrar;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create registrar user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create schema and generate realistic data using PL/SQL
# ---------------------------------------------------------------
echo "Generating realistic university dataset (this may take a minute)..."

sudo docker exec -i oracle-xe sqlplus -s registrar/Registrar2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE terms (
    term_id NUMBER PRIMARY KEY,
    term_code VARCHAR2(10) UNIQUE NOT NULL,
    term_name VARCHAR2(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL
);

CREATE TABLE departments (
    dept_id NUMBER PRIMARY KEY,
    department_code VARCHAR2(10) UNIQUE NOT NULL,
    department_name VARCHAR2(100) NOT NULL
);

CREATE TABLE courses (
    course_id NUMBER PRIMARY KEY,
    department VARCHAR2(10) NOT NULL REFERENCES departments(department_code),
    course_number VARCHAR2(10) NOT NULL,
    course_name VARCHAR2(100) NOT NULL,
    credits NUMBER NOT NULL
);

CREATE TABLE grade_points (
    grade_letter VARCHAR2(2) PRIMARY KEY,
    numeric_points NUMBER(3,1)
);

CREATE TABLE course_prerequisites (
    prereq_rule_id NUMBER PRIMARY KEY,
    course_id NUMBER REFERENCES courses(course_id),
    prereq_course_id NUMBER REFERENCES courses(course_id),
    min_grade_required VARCHAR2(2) REFERENCES grade_points(grade_letter)
);

CREATE TABLE students (
    student_id NUMBER PRIMARY KEY,
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    enrollment_term_id NUMBER REFERENCES terms(term_id),
    status VARCHAR2(20)
);

CREATE TABLE transcripts (
    transcript_id NUMBER PRIMARY KEY,
    student_id NUMBER REFERENCES students(student_id),
    term_id NUMBER REFERENCES terms(term_id),
    course_id NUMBER REFERENCES courses(course_id),
    grade_letter VARCHAR2(2) REFERENCES grade_points(grade_letter)
);

-- Seed Reference Data
INSERT INTO grade_points VALUES ('A', 4.0);
INSERT INTO grade_points VALUES ('B', 3.0);
INSERT INTO grade_points VALUES ('C', 2.0);
INSERT INTO grade_points VALUES ('D', 1.0);
INSERT INTO grade_points VALUES ('F', 0.0);
INSERT INTO grade_points VALUES ('W', NULL);

INSERT INTO terms VALUES (1, 'FA22', 'Fall 2022', DATE '2022-08-25', DATE '2022-12-15');
INSERT INTO terms VALUES (2, 'SP23', 'Spring 2023', DATE '2023-01-15', DATE '2023-05-15');
INSERT INTO terms VALUES (3, 'FA23', 'Fall 2023', DATE '2023-08-25', DATE '2023-12-15');
INSERT INTO terms VALUES (4, 'SP24', 'Spring 2024', DATE '2024-01-15', DATE '2024-05-15');

INSERT INTO departments VALUES (1, 'CS', 'Computer Science');
INSERT INTO departments VALUES (2, 'MATH', 'Mathematics');
INSERT INTO departments VALUES (3, 'PHYS', 'Physics');

-- Courses
INSERT INTO courses VALUES (101, 'CS', '101', 'Intro to Programming', 4);
INSERT INTO courses VALUES (102, 'CS', '201', 'Data Structures', 4);
INSERT INTO courses VALUES (103, 'CS', '301', 'Algorithms', 4);
INSERT INTO courses VALUES (201, 'MATH', '101', 'Calculus I', 4);
INSERT INTO courses VALUES (202, 'MATH', '201', 'Calculus II', 4);
INSERT INTO courses VALUES (203, 'MATH', '301', 'Linear Algebra', 3);
INSERT INTO courses VALUES (301, 'PHYS', '101', 'Physics Mechanics', 4);

-- Prerequisites
INSERT INTO course_prerequisites VALUES (1, 102, 101, 'C'); -- CS201 requires CS101 >= C
INSERT INTO course_prerequisites VALUES (2, 103, 102, 'C'); -- CS301 requires CS201 >= C
INSERT INTO course_prerequisites VALUES (3, 202, 201, 'C'); -- MATH201 requires MATH101 >= C
INSERT INTO course_prerequisites VALUES (4, 301, 201, 'C'); -- PHYS101 requires MATH101 >= C

-- Generate synthetic student and transcript data
DECLARE
    v_transcript_id NUMBER := 1;
    v_grade VARCHAR2(2);
    v_rand NUMBER;
BEGIN
    DBMS_RANDOM.SEED(42);
    
    -- Generate 200 normal students
    FOR s IN 1..200 LOOP
        INSERT INTO students VALUES (s, 'Student'||s, 'Last'||s, 1, 'ACTIVE');
        -- Term 1
        v_rand := DBMS_RANDOM.VALUE(0, 100);
        IF v_rand < 40 THEN v_grade := 'A'; ELSIF v_rand < 75 THEN v_grade := 'B'; ELSIF v_rand < 90 THEN v_grade := 'C'; ELSE v_grade := 'W'; END IF;
        INSERT INTO transcripts VALUES (v_transcript_id, s, 1, 101, v_grade); v_transcript_id := v_transcript_id + 1;
        
        -- Term 2
        IF v_grade IN ('A','B','C') THEN
            INSERT INTO transcripts VALUES (v_transcript_id, s, 2, 102, 'B'); v_transcript_id := v_transcript_id + 1;
        END IF;
    END LOOP;

    -- Inject Specific Test Cases for Verification
    
    -- Case 1: Prerequisite Violation (Student 9991 takes MATH201 without taking MATH101)
    INSERT INTO students VALUES (9991, 'Rule', 'Breaker', 1, 'ACTIVE');
    INSERT INTO transcripts VALUES (v_transcript_id, 9991, 1, 101, 'A'); v_transcript_id := v_transcript_id + 1;
    INSERT INTO transcripts VALUES (v_transcript_id, 9991, 2, 202, 'B'); v_transcript_id := v_transcript_id + 1; -- VIOLATION: Course 202 requires 201
    
    -- Case 2: Prerequisite Violation (Student 9992 fails CS101 but takes CS201 anyway)
    INSERT INTO students VALUES (9992, 'Grade', 'Ignorer', 1, 'ACTIVE');
    INSERT INTO transcripts VALUES (v_transcript_id, 9992, 1, 101, 'D'); v_transcript_id := v_transcript_id + 1; -- Min grade is C
    INSERT INTO transcripts VALUES (v_transcript_id, 9992, 2, 102, 'C'); v_transcript_id := v_transcript_id + 1; -- VIOLATION: Got D in 101
    
    -- Case 3: Academic Probation (Student 9993 gets < 2.0 for two consecutive terms)
    INSERT INTO students VALUES (9993, 'Struggling', 'Student', 1, 'PROBATION');
    INSERT INTO transcripts VALUES (v_transcript_id, 9993, 1, 101, 'D'); v_transcript_id := v_transcript_id + 1; -- Term 1 GPA = 1.0
    INSERT INTO transcripts VALUES (v_transcript_id, 9993, 1, 201, 'F'); v_transcript_id := v_transcript_id + 1; 
    INSERT INTO transcripts VALUES (v_transcript_id, 9993, 2, 101, 'C'); v_transcript_id := v_transcript_id + 1; -- Term 2 GPA = 1.5
    INSERT INTO transcripts VALUES (v_transcript_id, 9993, 2, 301, 'D'); v_transcript_id := v_transcript_id + 1; 
    -- Flag should be raised for Term 2.
    
    -- Case 4: Gap Term Probation (Student 9994 gets < 2.0, takes term off, gets < 2.0)
    INSERT INTO students VALUES (9994, 'Gap', 'Student', 1, 'PROBATION');
    INSERT INTO transcripts VALUES (v_transcript_id, 9994, 1, 101, 'D'); v_transcript_id := v_transcript_id + 1; -- Term 1
    -- Skipped Term 2
    INSERT INTO transcripts VALUES (v_transcript_id, 9994, 3, 201, 'D'); v_transcript_id := v_transcript_id + 1; -- Term 3
    -- Flag should be raised for Term 3.
    
    -- Case 5: W grades do not affect GPA (Student 9995)
    INSERT INTO students VALUES (9995, 'Withdraw', 'Student', 1, 'ACTIVE');
    INSERT INTO transcripts VALUES (v_transcript_id, 9995, 1, 101, 'A'); v_transcript_id := v_transcript_id + 1; -- 4 credits, 4.0
    INSERT INTO transcripts VALUES (v_transcript_id, 9995, 1, 201, 'W'); v_transcript_id := v_transcript_id + 1; -- 4 credits, W
    -- Term GPA should be exactly 4.0, not 2.0.

    COMMIT;
END;
/
EXIT;
EOSQL

echo "Dataset generated successfully."

# ---------------------------------------------------------------
# 5. Configure SQL Developer
# ---------------------------------------------------------------
# Use shared utility to pre-configure the connection so the agent doesn't waste time typing credentials
ensure_hr_connection "Registrar DB" "registrar" "Registrar2024"

# ---------------------------------------------------------------
# 6. Launch SQL Developer & Record Initial State
# ---------------------------------------------------------------
echo "Launching Oracle SQL Developer..."
# Kill existing instance if any
pkill -f sqldeveloper 2>/dev/null || true

su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 JAVA_TOOL_OPTIONS='--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED -Dsun.java2d.xrender=false -Dsun.java2d.opengl=false' /opt/sqldeveloper/sqldeveloper.sh > /tmp/sqldeveloper.log 2>&1 &"

# Wait for window and maximize
sleep 15
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Try to open the connection in the GUI
open_hr_connection_in_sqldeveloper "Registrar DB" || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="