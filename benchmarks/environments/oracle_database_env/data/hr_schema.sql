-- Oracle HR Sample Schema
-- Based on Oracle's official db-sample-schemas repository
-- https://github.com/oracle-samples/db-sample-schemas
-- This creates the Human Resources sample schema with realistic employee data

-- =============================================
-- Create Tables
-- =============================================

-- REGIONS table
CREATE TABLE regions (
    region_id NUMBER CONSTRAINT region_id_nn NOT NULL,
    region_name VARCHAR2(25)
);

CREATE UNIQUE INDEX reg_id_pk ON regions (region_id);
ALTER TABLE regions ADD CONSTRAINT reg_id_pk PRIMARY KEY (region_id);

-- COUNTRIES table
CREATE TABLE countries (
    country_id CHAR(2) CONSTRAINT country_id_nn NOT NULL,
    country_name VARCHAR2(40),
    region_id NUMBER,
    CONSTRAINT country_c_id_pk PRIMARY KEY (country_id)
);

ALTER TABLE countries ADD CONSTRAINT countr_reg_fk
    FOREIGN KEY (region_id) REFERENCES regions(region_id);

-- LOCATIONS table
CREATE TABLE locations (
    location_id NUMBER(4),
    street_address VARCHAR2(40),
    postal_code VARCHAR2(12),
    city VARCHAR2(30) CONSTRAINT loc_city_nn NOT NULL,
    state_province VARCHAR2(25),
    country_id CHAR(2)
);

CREATE UNIQUE INDEX loc_id_pk ON locations (location_id);
ALTER TABLE locations ADD CONSTRAINT loc_id_pk PRIMARY KEY (location_id);
ALTER TABLE locations ADD CONSTRAINT loc_c_id_fk
    FOREIGN KEY (country_id) REFERENCES countries(country_id);

-- DEPARTMENTS table
CREATE TABLE departments (
    department_id NUMBER(4),
    department_name VARCHAR2(30) CONSTRAINT dept_name_nn NOT NULL,
    manager_id NUMBER(6),
    location_id NUMBER(4)
);

CREATE UNIQUE INDEX dept_id_pk ON departments (department_id);
ALTER TABLE departments ADD CONSTRAINT dept_id_pk PRIMARY KEY (department_id);
ALTER TABLE departments ADD CONSTRAINT dept_loc_fk
    FOREIGN KEY (location_id) REFERENCES locations(location_id);

-- JOBS table
CREATE TABLE jobs (
    job_id VARCHAR2(10),
    job_title VARCHAR2(35) CONSTRAINT job_title_nn NOT NULL,
    min_salary NUMBER(6),
    max_salary NUMBER(6)
);

CREATE UNIQUE INDEX job_id_pk ON jobs (job_id);
ALTER TABLE jobs ADD CONSTRAINT job_id_pk PRIMARY KEY (job_id);

-- EMPLOYEES table
CREATE TABLE employees (
    employee_id NUMBER(6),
    first_name VARCHAR2(20),
    last_name VARCHAR2(25) CONSTRAINT emp_last_name_nn NOT NULL,
    email VARCHAR2(25) CONSTRAINT emp_email_nn NOT NULL,
    phone_number VARCHAR2(20),
    hire_date DATE CONSTRAINT emp_hire_date_nn NOT NULL,
    job_id VARCHAR2(10) CONSTRAINT emp_job_nn NOT NULL,
    salary NUMBER(8,2),
    commission_pct NUMBER(2,2),
    manager_id NUMBER(6),
    department_id NUMBER(4),
    CONSTRAINT emp_salary_min CHECK (salary > 0),
    CONSTRAINT emp_email_uk UNIQUE (email)
);

CREATE UNIQUE INDEX emp_emp_id_pk ON employees (employee_id);
ALTER TABLE employees ADD CONSTRAINT emp_emp_id_pk PRIMARY KEY (employee_id);
ALTER TABLE employees ADD CONSTRAINT emp_dept_fk
    FOREIGN KEY (department_id) REFERENCES departments(department_id);
ALTER TABLE employees ADD CONSTRAINT emp_job_fk
    FOREIGN KEY (job_id) REFERENCES jobs(job_id);
ALTER TABLE employees ADD CONSTRAINT emp_manager_fk
    FOREIGN KEY (manager_id) REFERENCES employees(employee_id);

-- Add foreign key from departments to employees (for manager_id)
ALTER TABLE departments ADD CONSTRAINT dept_mgr_fk
    FOREIGN KEY (manager_id) REFERENCES employees(employee_id);

-- JOB_HISTORY table
CREATE TABLE job_history (
    employee_id NUMBER(6) CONSTRAINT jhist_employee_nn NOT NULL,
    start_date DATE CONSTRAINT jhist_start_date_nn NOT NULL,
    end_date DATE CONSTRAINT jhist_end_date_nn NOT NULL,
    job_id VARCHAR2(10) CONSTRAINT jhist_job_nn NOT NULL,
    department_id NUMBER(4),
    CONSTRAINT jhist_date_interval CHECK (end_date > start_date)
);

CREATE UNIQUE INDEX jhist_emp_id_st_date_pk ON job_history (employee_id, start_date);
ALTER TABLE job_history ADD CONSTRAINT jhist_emp_id_st_date_pk
    PRIMARY KEY (employee_id, start_date);
ALTER TABLE job_history ADD CONSTRAINT jhist_job_fk
    FOREIGN KEY (job_id) REFERENCES jobs(job_id);
ALTER TABLE job_history ADD CONSTRAINT jhist_emp_fk
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id);
ALTER TABLE job_history ADD CONSTRAINT jhist_dept_fk
    FOREIGN KEY (department_id) REFERENCES departments(department_id);

-- =============================================
-- Create Sequences
-- =============================================

CREATE SEQUENCE employees_seq
    START WITH 207
    INCREMENT BY 1
    NOMAXVALUE
    NOCACHE
    NOCYCLE;

CREATE SEQUENCE departments_seq
    START WITH 280
    INCREMENT BY 10
    NOMAXVALUE
    NOCACHE
    NOCYCLE;

CREATE SEQUENCE locations_seq
    START WITH 3300
    INCREMENT BY 100
    NOMAXVALUE
    NOCACHE
    NOCYCLE;

-- =============================================
-- Populate Tables with Data
-- =============================================

-- REGIONS
INSERT INTO regions VALUES (1, 'Europe');
INSERT INTO regions VALUES (2, 'Americas');
INSERT INTO regions VALUES (3, 'Asia');
INSERT INTO regions VALUES (4, 'Middle East and Africa');

-- COUNTRIES
INSERT INTO countries VALUES ('AR', 'Argentina', 2);
INSERT INTO countries VALUES ('AU', 'Australia', 3);
INSERT INTO countries VALUES ('BE', 'Belgium', 1);
INSERT INTO countries VALUES ('BR', 'Brazil', 2);
INSERT INTO countries VALUES ('CA', 'Canada', 2);
INSERT INTO countries VALUES ('CH', 'Switzerland', 1);
INSERT INTO countries VALUES ('CN', 'China', 3);
INSERT INTO countries VALUES ('DE', 'Germany', 1);
INSERT INTO countries VALUES ('DK', 'Denmark', 1);
INSERT INTO countries VALUES ('EG', 'Egypt', 4);
INSERT INTO countries VALUES ('FR', 'France', 1);
INSERT INTO countries VALUES ('IL', 'Israel', 4);
INSERT INTO countries VALUES ('IN', 'India', 3);
INSERT INTO countries VALUES ('IT', 'Italy', 1);
INSERT INTO countries VALUES ('JP', 'Japan', 3);
INSERT INTO countries VALUES ('KW', 'Kuwait', 4);
INSERT INTO countries VALUES ('ML', 'Malaysia', 3);
INSERT INTO countries VALUES ('MX', 'Mexico', 2);
INSERT INTO countries VALUES ('NG', 'Nigeria', 4);
INSERT INTO countries VALUES ('NL', 'Netherlands', 1);
INSERT INTO countries VALUES ('SG', 'Singapore', 3);
INSERT INTO countries VALUES ('UK', 'United Kingdom', 1);
INSERT INTO countries VALUES ('US', 'United States of America', 2);
INSERT INTO countries VALUES ('ZM', 'Zambia', 4);
INSERT INTO countries VALUES ('ZW', 'Zimbabwe', 4);

-- LOCATIONS
INSERT INTO locations VALUES (1000, '1297 Via Cola di Rie', '00989', 'Roma', NULL, 'IT');
INSERT INTO locations VALUES (1100, '93091 Calle della Testa', '10934', 'Venice', NULL, 'IT');
INSERT INTO locations VALUES (1200, '2017 Shinjuku-ku', '1689', 'Tokyo', 'Tokyo Prefecture', 'JP');
INSERT INTO locations VALUES (1300, '9450 Kamiya-cho', '6823', 'Hiroshima', NULL, 'JP');
INSERT INTO locations VALUES (1400, '2014 Jabberwocky Rd', '26192', 'Southlake', 'Texas', 'US');
INSERT INTO locations VALUES (1500, '2011 Interiors Blvd', '99236', 'South San Francisco', 'California', 'US');
INSERT INTO locations VALUES (1600, '2007 Zagora St', '50090', 'South Brunswick', 'New Jersey', 'US');
INSERT INTO locations VALUES (1700, '2004 Charade Rd', '98199', 'Seattle', 'Washington', 'US');
INSERT INTO locations VALUES (1800, '147 Spadina Ave', 'M5V 2L7', 'Toronto', 'Ontario', 'CA');
INSERT INTO locations VALUES (1900, '6092 Boxwood St', 'YSW 9T2', 'Whitehorse', 'Yukon', 'CA');
INSERT INTO locations VALUES (2000, '40-5-12 Laogianggen', '190518', 'Beijing', NULL, 'CN');
INSERT INTO locations VALUES (2100, '1298 Vileparle (E)', '490231', 'Bombay', 'Maharashtra', 'IN');
INSERT INTO locations VALUES (2200, '12-98 Victoria Street', '2901', 'Sydney', 'New South Wales', 'AU');
INSERT INTO locations VALUES (2300, '198 Clementi North', '540198', 'Singapore', NULL, 'SG');
INSERT INTO locations VALUES (2400, '8204 Arthur St', NULL, 'London', NULL, 'UK');
INSERT INTO locations VALUES (2500, 'Magdalen Centre, The Oxford Science Park', 'OX9 9ZB', 'Oxford', 'Oxford', 'UK');
INSERT INTO locations VALUES (2600, '9702 Chester Road', '09629850293', 'Stretford', 'Manchester', 'UK');
INSERT INTO locations VALUES (2700, 'Schwanthalerstr. 7031', '80925', 'Munich', 'Bavaria', 'DE');
INSERT INTO locations VALUES (2800, 'Rua Frei Caneca 1360', '01307-002', 'Sao Paulo', 'Sao Paulo', 'BR');
INSERT INTO locations VALUES (2900, '20 Rue des Corps-Saints', '1730', 'Geneva', 'Geneve', 'CH');
INSERT INTO locations VALUES (3000, 'Murtenstrasse 921', '3095', 'Bern', 'BE', 'CH');
INSERT INTO locations VALUES (3100, 'Pieter Breughellaan 837', '3029SK', 'Utrecht', 'Utrecht', 'NL');
INSERT INTO locations VALUES (3200, 'Mariano Escobedo 9991', '11932', 'Mexico City', 'Distrito Federal', 'MX');

-- JOBS
INSERT INTO jobs VALUES ('AD_PRES', 'President', 20080, 40000);
INSERT INTO jobs VALUES ('AD_VP', 'Administration Vice President', 15000, 30000);
INSERT INTO jobs VALUES ('AD_ASST', 'Administration Assistant', 3000, 6000);
INSERT INTO jobs VALUES ('FI_MGR', 'Finance Manager', 8200, 16000);
INSERT INTO jobs VALUES ('FI_ACCOUNT', 'Accountant', 4200, 9000);
INSERT INTO jobs VALUES ('AC_MGR', 'Accounting Manager', 8200, 16000);
INSERT INTO jobs VALUES ('AC_ACCOUNT', 'Public Accountant', 4200, 9000);
INSERT INTO jobs VALUES ('SA_MAN', 'Sales Manager', 10000, 20080);
INSERT INTO jobs VALUES ('SA_REP', 'Sales Representative', 6000, 12008);
INSERT INTO jobs VALUES ('PU_MAN', 'Purchasing Manager', 8000, 15000);
INSERT INTO jobs VALUES ('PU_CLERK', 'Purchasing Clerk', 2500, 5500);
INSERT INTO jobs VALUES ('ST_MAN', 'Stock Manager', 5500, 8500);
INSERT INTO jobs VALUES ('ST_CLERK', 'Stock Clerk', 2008, 5000);
INSERT INTO jobs VALUES ('SH_CLERK', 'Shipping Clerk', 2500, 5500);
INSERT INTO jobs VALUES ('IT_PROG', 'Programmer', 4000, 10000);
INSERT INTO jobs VALUES ('MK_MAN', 'Marketing Manager', 9000, 15000);
INSERT INTO jobs VALUES ('MK_REP', 'Marketing Representative', 4000, 9000);
INSERT INTO jobs VALUES ('HR_REP', 'Human Resources Representative', 4000, 9000);
INSERT INTO jobs VALUES ('PR_REP', 'Public Relations Representative', 4500, 10500);

-- DEPARTMENTS (initial without manager_id)
INSERT INTO departments VALUES (10, 'Administration', NULL, 1700);
INSERT INTO departments VALUES (20, 'Marketing', NULL, 1800);
INSERT INTO departments VALUES (30, 'Purchasing', NULL, 1700);
INSERT INTO departments VALUES (40, 'Human Resources', NULL, 2400);
INSERT INTO departments VALUES (50, 'Shipping', NULL, 1500);
INSERT INTO departments VALUES (60, 'IT', NULL, 1400);
INSERT INTO departments VALUES (70, 'Public Relations', NULL, 2700);
INSERT INTO departments VALUES (80, 'Sales', NULL, 2500);
INSERT INTO departments VALUES (90, 'Executive', NULL, 1700);
INSERT INTO departments VALUES (100, 'Finance', NULL, 1700);
INSERT INTO departments VALUES (110, 'Accounting', NULL, 1700);
INSERT INTO departments VALUES (120, 'Treasury', NULL, 1700);
INSERT INTO departments VALUES (130, 'Corporate Tax', NULL, 1700);
INSERT INTO departments VALUES (140, 'Control And Credit', NULL, 1700);
INSERT INTO departments VALUES (150, 'Shareholder Services', NULL, 1700);
INSERT INTO departments VALUES (160, 'Benefits', NULL, 1700);
INSERT INTO departments VALUES (170, 'Manufacturing', NULL, 1700);
INSERT INTO departments VALUES (180, 'Construction', NULL, 1700);
INSERT INTO departments VALUES (190, 'Contracting', NULL, 1700);
INSERT INTO departments VALUES (200, 'Operations', NULL, 1700);
INSERT INTO departments VALUES (210, 'IT Support', NULL, 1700);
INSERT INTO departments VALUES (220, 'NOC', NULL, 1700);
INSERT INTO departments VALUES (230, 'IT Helpdesk', NULL, 1700);
INSERT INTO departments VALUES (240, 'Government Sales', NULL, 1700);
INSERT INTO departments VALUES (250, 'Retail Sales', NULL, 1700);
INSERT INTO departments VALUES (260, 'Recruiting', NULL, 1700);
INSERT INTO departments VALUES (270, 'Payroll', NULL, 1700);

-- EMPLOYEES
INSERT INTO employees VALUES (100, 'Steven', 'King', 'SKING', '515.123.4567', TO_DATE('17-06-2003', 'DD-MM-YYYY'), 'AD_PRES', 24000, NULL, NULL, 90);
INSERT INTO employees VALUES (101, 'Neena', 'Kochhar', 'NKOCHHAR', '515.123.4568', TO_DATE('21-09-2005', 'DD-MM-YYYY'), 'AD_VP', 17000, NULL, 100, 90);
INSERT INTO employees VALUES (102, 'Lex', 'De Haan', 'LDEHAAN', '515.123.4569', TO_DATE('13-01-2001', 'DD-MM-YYYY'), 'AD_VP', 17000, NULL, 100, 90);
INSERT INTO employees VALUES (103, 'Alexander', 'Hunold', 'AHUNOLD', '590.423.4567', TO_DATE('03-01-2006', 'DD-MM-YYYY'), 'IT_PROG', 9000, NULL, 102, 60);
INSERT INTO employees VALUES (104, 'Bruce', 'Ernst', 'BERNST', '590.423.4568', TO_DATE('21-05-2007', 'DD-MM-YYYY'), 'IT_PROG', 6000, NULL, 103, 60);
INSERT INTO employees VALUES (105, 'David', 'Austin', 'DAUSTIN', '590.423.4569', TO_DATE('25-06-2005', 'DD-MM-YYYY'), 'IT_PROG', 4800, NULL, 103, 60);
INSERT INTO employees VALUES (106, 'Valli', 'Pataballa', 'VPATABAL', '590.423.4560', TO_DATE('05-02-2006', 'DD-MM-YYYY'), 'IT_PROG', 4800, NULL, 103, 60);
INSERT INTO employees VALUES (107, 'Diana', 'Lorentz', 'DLORENTZ', '590.423.5567', TO_DATE('07-02-2007', 'DD-MM-YYYY'), 'IT_PROG', 4200, NULL, 103, 60);
INSERT INTO employees VALUES (108, 'Nancy', 'Greenberg', 'NGREENBE', '515.124.4569', TO_DATE('17-08-2002', 'DD-MM-YYYY'), 'FI_MGR', 12008, NULL, 101, 100);
INSERT INTO employees VALUES (109, 'Daniel', 'Faviet', 'DFAVIET', '515.124.4169', TO_DATE('16-08-2002', 'DD-MM-YYYY'), 'FI_ACCOUNT', 9000, NULL, 108, 100);
INSERT INTO employees VALUES (110, 'John', 'Chen', 'JCHEN', '515.124.4269', TO_DATE('28-09-2005', 'DD-MM-YYYY'), 'FI_ACCOUNT', 8200, NULL, 108, 100);
INSERT INTO employees VALUES (111, 'Ismael', 'Sciarra', 'ISCIARRA', '515.124.4369', TO_DATE('30-09-2005', 'DD-MM-YYYY'), 'FI_ACCOUNT', 7700, NULL, 108, 100);
INSERT INTO employees VALUES (112, 'Jose Manuel', 'Urman', 'JMURMAN', '515.124.4469', TO_DATE('07-03-2006', 'DD-MM-YYYY'), 'FI_ACCOUNT', 7800, NULL, 108, 100);
INSERT INTO employees VALUES (113, 'Luis', 'Popp', 'LPOPP', '515.124.4567', TO_DATE('07-12-2007', 'DD-MM-YYYY'), 'FI_ACCOUNT', 6900, NULL, 108, 100);
INSERT INTO employees VALUES (114, 'Den', 'Raphaely', 'DRAPHEAL', '515.127.4561', TO_DATE('07-12-2002', 'DD-MM-YYYY'), 'PU_MAN', 11000, NULL, 100, 30);
INSERT INTO employees VALUES (115, 'Alexander', 'Khoo', 'AKHOO', '515.127.4562', TO_DATE('18-05-2003', 'DD-MM-YYYY'), 'PU_CLERK', 3100, NULL, 114, 30);
INSERT INTO employees VALUES (116, 'Shelli', 'Baida', 'SBAIDA', '515.127.4563', TO_DATE('24-12-2005', 'DD-MM-YYYY'), 'PU_CLERK', 2900, NULL, 114, 30);
INSERT INTO employees VALUES (117, 'Sigal', 'Tobias', 'STOBIAS', '515.127.4564', TO_DATE('24-07-2005', 'DD-MM-YYYY'), 'PU_CLERK', 2800, NULL, 114, 30);
INSERT INTO employees VALUES (118, 'Guy', 'Himuro', 'GHIMURO', '515.127.4565', TO_DATE('15-11-2006', 'DD-MM-YYYY'), 'PU_CLERK', 2600, NULL, 114, 30);
INSERT INTO employees VALUES (119, 'Karen', 'Colmenares', 'KCOLMENA', '515.127.4566', TO_DATE('10-08-2007', 'DD-MM-YYYY'), 'PU_CLERK', 2500, NULL, 114, 30);
INSERT INTO employees VALUES (120, 'Matthew', 'Weiss', 'MWEISS', '650.123.1234', TO_DATE('18-07-2004', 'DD-MM-YYYY'), 'ST_MAN', 8000, NULL, 100, 50);
INSERT INTO employees VALUES (121, 'Adam', 'Fripp', 'AFRIPP', '650.123.2234', TO_DATE('10-04-2005', 'DD-MM-YYYY'), 'ST_MAN', 8200, NULL, 100, 50);
INSERT INTO employees VALUES (122, 'Payam', 'Kaufling', 'PKAUFLIN', '650.123.3234', TO_DATE('01-05-2003', 'DD-MM-YYYY'), 'ST_MAN', 7900, NULL, 100, 50);
INSERT INTO employees VALUES (123, 'Shanta', 'Vollman', 'SVOLLMAN', '650.123.4234', TO_DATE('10-10-2005', 'DD-MM-YYYY'), 'ST_MAN', 6500, NULL, 100, 50);
INSERT INTO employees VALUES (124, 'Kevin', 'Mourgos', 'KMOURGOS', '650.123.5234', TO_DATE('16-11-2007', 'DD-MM-YYYY'), 'ST_MAN', 5800, NULL, 100, 50);
INSERT INTO employees VALUES (125, 'Julia', 'Nayer', 'JNAYER', '650.124.1214', TO_DATE('16-07-2005', 'DD-MM-YYYY'), 'ST_CLERK', 3200, NULL, 120, 50);
INSERT INTO employees VALUES (126, 'Irene', 'Mikkilineni', 'IMIKKILI', '650.124.1224', TO_DATE('28-09-2006', 'DD-MM-YYYY'), 'ST_CLERK', 2700, NULL, 120, 50);
INSERT INTO employees VALUES (127, 'James', 'Landry', 'JLANDRY', '650.124.1334', TO_DATE('14-01-2007', 'DD-MM-YYYY'), 'ST_CLERK', 2400, NULL, 120, 50);
INSERT INTO employees VALUES (128, 'Steven', 'Markle', 'SMARKLE', '650.124.1434', TO_DATE('08-03-2008', 'DD-MM-YYYY'), 'ST_CLERK', 2200, NULL, 120, 50);
INSERT INTO employees VALUES (129, 'Laura', 'Bissot', 'LBISSOT', '650.124.5234', TO_DATE('20-08-2005', 'DD-MM-YYYY'), 'ST_CLERK', 3300, NULL, 121, 50);
INSERT INTO employees VALUES (130, 'Mozhe', 'Atkinson', 'MATKINSO', '650.124.6234', TO_DATE('30-10-2005', 'DD-MM-YYYY'), 'ST_CLERK', 2800, NULL, 121, 50);
INSERT INTO employees VALUES (131, 'James', 'Marlow', 'JAMRLOW', '650.124.7234', TO_DATE('16-02-2005', 'DD-MM-YYYY'), 'ST_CLERK', 2500, NULL, 121, 50);
INSERT INTO employees VALUES (132, 'TJ', 'Olson', 'TJOLSON', '650.124.8234', TO_DATE('10-04-2007', 'DD-MM-YYYY'), 'ST_CLERK', 2100, NULL, 121, 50);
INSERT INTO employees VALUES (133, 'Jason', 'Mallin', 'JMALLIN', '650.127.1934', TO_DATE('14-06-2004', 'DD-MM-YYYY'), 'ST_CLERK', 3300, NULL, 122, 50);
INSERT INTO employees VALUES (134, 'Michael', 'Rogers', 'MROGERS', '650.127.1834', TO_DATE('26-08-2006', 'DD-MM-YYYY'), 'ST_CLERK', 2900, NULL, 122, 50);
INSERT INTO employees VALUES (135, 'Ki', 'Gee', 'KGEE', '650.127.1734', TO_DATE('12-12-2007', 'DD-MM-YYYY'), 'ST_CLERK', 2400, NULL, 122, 50);
INSERT INTO employees VALUES (136, 'Hazel', 'Philtanker', 'HPHILTAN', '650.127.1634', TO_DATE('06-02-2008', 'DD-MM-YYYY'), 'ST_CLERK', 2200, NULL, 122, 50);
INSERT INTO employees VALUES (137, 'Renske', 'Ladwig', 'RLADWIG', '650.121.1234', TO_DATE('14-07-2003', 'DD-MM-YYYY'), 'ST_CLERK', 3600, NULL, 123, 50);
INSERT INTO employees VALUES (138, 'Stephen', 'Stiles', 'SSTILES', '650.121.2034', TO_DATE('26-10-2005', 'DD-MM-YYYY'), 'ST_CLERK', 3200, NULL, 123, 50);
INSERT INTO employees VALUES (139, 'John', 'Seo', 'JSEO', '650.121.2019', TO_DATE('12-02-2006', 'DD-MM-YYYY'), 'ST_CLERK', 2700, NULL, 123, 50);
INSERT INTO employees VALUES (140, 'Joshua', 'Patel', 'JPATEL', '650.121.1834', TO_DATE('06-04-2006', 'DD-MM-YYYY'), 'ST_CLERK', 2500, NULL, 123, 50);
INSERT INTO employees VALUES (141, 'Trenna', 'Rajs', 'TRAJS', '650.121.8009', TO_DATE('17-10-2003', 'DD-MM-YYYY'), 'ST_CLERK', 3500, NULL, 124, 50);
INSERT INTO employees VALUES (142, 'Curtis', 'Davies', 'CDAVIES', '650.121.2994', TO_DATE('29-01-2005', 'DD-MM-YYYY'), 'ST_CLERK', 3100, NULL, 124, 50);
INSERT INTO employees VALUES (143, 'Randall', 'Matos', 'RMATOS', '650.121.2874', TO_DATE('15-03-2006', 'DD-MM-YYYY'), 'ST_CLERK', 2600, NULL, 124, 50);
INSERT INTO employees VALUES (144, 'Peter', 'Vargas', 'PVARGAS', '650.121.2004', TO_DATE('09-07-2006', 'DD-MM-YYYY'), 'ST_CLERK', 2500, NULL, 124, 50);
INSERT INTO employees VALUES (145, 'John', 'Russell', 'JRUSSEL', '011.44.1344.429268', TO_DATE('01-10-2004', 'DD-MM-YYYY'), 'SA_MAN', 14000, .4, 100, 80);
INSERT INTO employees VALUES (146, 'Karen', 'Partners', 'KPARTNER', '011.44.1344.467268', TO_DATE('05-01-2005', 'DD-MM-YYYY'), 'SA_MAN', 13500, .3, 100, 80);
INSERT INTO employees VALUES (147, 'Alberto', 'Errazuriz', 'AERMDa', '011.44.1344.429278', TO_DATE('10-03-2005', 'DD-MM-YYYY'), 'SA_MAN', 12000, .3, 100, 80);
INSERT INTO employees VALUES (148, 'Gerald', 'Cambrault', 'GCAMBRAU', '011.44.1344.619268', TO_DATE('15-10-2007', 'DD-MM-YYYY'), 'SA_MAN', 11000, .3, 100, 80);
INSERT INTO employees VALUES (149, 'Eleni', 'Zlotkey', 'EZLOTKEY', '011.44.1344.429018', TO_DATE('29-01-2008', 'DD-MM-YYYY'), 'SA_MAN', 10500, .2, 100, 80);
INSERT INTO employees VALUES (150, 'Peter', 'Tucker', 'PTUCKER', '011.44.1344.129268', TO_DATE('30-01-2005', 'DD-MM-YYYY'), 'SA_REP', 10000, .3, 145, 80);
INSERT INTO employees VALUES (151, 'David', 'Bernstein', 'DBERNSTE', '011.44.1344.345268', TO_DATE('24-03-2005', 'DD-MM-YYYY'), 'SA_REP', 9500, .25, 145, 80);
INSERT INTO employees VALUES (152, 'Peter', 'Hall', 'PHALL', '011.44.1344.478968', TO_DATE('20-08-2005', 'DD-MM-YYYY'), 'SA_REP', 9000, .25, 145, 80);
INSERT INTO employees VALUES (153, 'Christopher', 'Olsen', 'COLSEN', '011.44.1344.498718', TO_DATE('30-03-2006', 'DD-MM-YYYY'), 'SA_REP', 8000, .2, 145, 80);
INSERT INTO employees VALUES (154, 'Nanette', 'Cambrault', 'NCAMBRAU', '011.44.1344.987668', TO_DATE('09-12-2006', 'DD-MM-YYYY'), 'SA_REP', 7500, .2, 145, 80);
INSERT INTO employees VALUES (155, 'Oliver', 'Tuvault', 'OTUVAULT', '011.44.1344.486508', TO_DATE('23-11-2007', 'DD-MM-YYYY'), 'SA_REP', 7000, .15, 145, 80);
INSERT INTO employees VALUES (156, 'Janette', 'King', 'JKING', '011.44.1345.429268', TO_DATE('30-01-2004', 'DD-MM-YYYY'), 'SA_REP', 10000, .35, 146, 80);
INSERT INTO employees VALUES (157, 'Patrick', 'Sully', 'PSULLY', '011.44.1345.929268', TO_DATE('04-03-2004', 'DD-MM-YYYY'), 'SA_REP', 9500, .35, 146, 80);
INSERT INTO employees VALUES (158, 'Allan', 'McEwen', 'AMCEWEN', '011.44.1345.829268', TO_DATE('01-08-2004', 'DD-MM-YYYY'), 'SA_REP', 9000, .35, 146, 80);
INSERT INTO employees VALUES (159, 'Lindsey', 'Smith', 'LSMITH', '011.44.1345.729268', TO_DATE('10-03-2005', 'DD-MM-YYYY'), 'SA_REP', 8000, .3, 146, 80);
INSERT INTO employees VALUES (160, 'Louise', 'Doran', 'LDORAN', '011.44.1345.629268', TO_DATE('15-12-2005', 'DD-MM-YYYY'), 'SA_REP', 7500, .3, 146, 80);
INSERT INTO employees VALUES (161, 'Sarath', 'Sewall', 'SSEWALL', '011.44.1345.529268', TO_DATE('03-11-2006', 'DD-MM-YYYY'), 'SA_REP', 7000, .25, 146, 80);
INSERT INTO employees VALUES (162, 'Clara', 'Vishney', 'CVISHNEY', '011.44.1346.129268', TO_DATE('11-11-2005', 'DD-MM-YYYY'), 'SA_REP', 10500, .25, 147, 80);
INSERT INTO employees VALUES (163, 'Danielle', 'Greene', 'DGREENE', '011.44.1346.229268', TO_DATE('19-03-2007', 'DD-MM-YYYY'), 'SA_REP', 9500, .15, 147, 80);
INSERT INTO employees VALUES (164, 'Mattea', 'Marvins', 'MMARVINS', '011.44.1346.329268', TO_DATE('24-01-2008', 'DD-MM-YYYY'), 'SA_REP', 7200, .1, 147, 80);
INSERT INTO employees VALUES (165, 'David', 'Lee', 'DLEE', '011.44.1346.529268', TO_DATE('23-02-2008', 'DD-MM-YYYY'), 'SA_REP', 6800, .1, 147, 80);
INSERT INTO employees VALUES (166, 'Sundar', 'Ande', 'SANDE', '011.44.1346.629268', TO_DATE('24-03-2008', 'DD-MM-YYYY'), 'SA_REP', 6400, .1, 147, 80);
INSERT INTO employees VALUES (167, 'Amit', 'Banda', 'ABANDA', '011.44.1346.729268', TO_DATE('21-04-2008', 'DD-MM-YYYY'), 'SA_REP', 6200, .1, 147, 80);
INSERT INTO employees VALUES (168, 'Lisa', 'Ozer', 'LOZER', '011.44.1343.929268', TO_DATE('11-03-2005', 'DD-MM-YYYY'), 'SA_REP', 11500, .25, 148, 80);
INSERT INTO employees VALUES (169, 'Harrison', 'Bloom', 'HBLOOM', '011.44.1343.829268', TO_DATE('23-03-2006', 'DD-MM-YYYY'), 'SA_REP', 10000, .2, 148, 80);
INSERT INTO employees VALUES (170, 'Tayler', 'Fox', 'TFOX', '011.44.1343.729268', TO_DATE('24-01-2006', 'DD-MM-YYYY'), 'SA_REP', 9600, .2, 148, 80);
INSERT INTO employees VALUES (171, 'William', 'Smith', 'WSMITH', '011.44.1343.629268', TO_DATE('23-02-2007', 'DD-MM-YYYY'), 'SA_REP', 7400, .15, 148, 80);
INSERT INTO employees VALUES (172, 'Elizabeth', 'Bates', 'EBATES', '011.44.1343.529268', TO_DATE('24-03-2007', 'DD-MM-YYYY'), 'SA_REP', 7300, .15, 148, 80);
INSERT INTO employees VALUES (173, 'Sundita', 'Kumar', 'SKUMAR', '011.44.1343.329268', TO_DATE('21-04-2008', 'DD-MM-YYYY'), 'SA_REP', 6100, .1, 148, 80);
INSERT INTO employees VALUES (174, 'Ellen', 'Abel', 'EABEL', '011.44.1644.429267', TO_DATE('11-05-2004', 'DD-MM-YYYY'), 'SA_REP', 11000, .3, 149, 80);
INSERT INTO employees VALUES (175, 'Alyssa', 'Hutton', 'AHUTTON', '011.44.1644.429266', TO_DATE('19-03-2005', 'DD-MM-YYYY'), 'SA_REP', 8800, .25, 149, 80);
INSERT INTO employees VALUES (176, 'Jonathon', 'Taylor', 'JTAYLOR', '011.44.1644.429265', TO_DATE('24-03-2006', 'DD-MM-YYYY'), 'SA_REP', 8600, .2, 149, 80);
INSERT INTO employees VALUES (177, 'Jack', 'Livingston', 'JLIVINGS', '011.44.1644.429264', TO_DATE('23-04-2006', 'DD-MM-YYYY'), 'SA_REP', 8400, .2, 149, 80);
INSERT INTO employees VALUES (178, 'Kimberely', 'Grant', 'KGRANT', '011.44.1644.429263', TO_DATE('24-05-2007', 'DD-MM-YYYY'), 'SA_REP', 7000, .15, 149, NULL);
INSERT INTO employees VALUES (179, 'Charles', 'Johnson', 'CJOHNSON', '011.44.1644.429262', TO_DATE('04-01-2008', 'DD-MM-YYYY'), 'SA_REP', 6200, .1, 149, 80);
INSERT INTO employees VALUES (180, 'Winston', 'Taylor', 'WTAYLOR', '650.507.9876', TO_DATE('24-01-2006', 'DD-MM-YYYY'), 'SH_CLERK', 3200, NULL, 120, 50);
INSERT INTO employees VALUES (181, 'Jean', 'Fleaur', 'JFLEAUR', '650.507.9877', TO_DATE('23-02-2006', 'DD-MM-YYYY'), 'SH_CLERK', 3100, NULL, 120, 50);
INSERT INTO employees VALUES (182, 'Martha', 'Sullivan', 'MSULLIVA', '650.507.9878', TO_DATE('21-06-2007', 'DD-MM-YYYY'), 'SH_CLERK', 2500, NULL, 120, 50);
INSERT INTO employees VALUES (183, 'Girard', 'Geoni', 'GGEONI', '650.507.9879', TO_DATE('03-02-2008', 'DD-MM-YYYY'), 'SH_CLERK', 2800, NULL, 120, 50);
INSERT INTO employees VALUES (184, 'Nandita', 'Sarchand', 'NSARCHAN', '650.509.1876', TO_DATE('27-01-2004', 'DD-MM-YYYY'), 'SH_CLERK', 4200, NULL, 121, 50);
INSERT INTO employees VALUES (185, 'Alexis', 'Bull', 'ABULL', '650.509.2876', TO_DATE('20-02-2005', 'DD-MM-YYYY'), 'SH_CLERK', 4100, NULL, 121, 50);
INSERT INTO employees VALUES (186, 'Julia', 'Dellinger', 'JDELLING', '650.509.3876', TO_DATE('24-06-2006', 'DD-MM-YYYY'), 'SH_CLERK', 3400, NULL, 121, 50);
INSERT INTO employees VALUES (187, 'Anthony', 'Cabrio', 'ACABRIO', '650.509.4876', TO_DATE('07-02-2007', 'DD-MM-YYYY'), 'SH_CLERK', 3000, NULL, 121, 50);
INSERT INTO employees VALUES (188, 'Kelly', 'Chung', 'KCHUNG', '650.505.1876', TO_DATE('14-06-2005', 'DD-MM-YYYY'), 'SH_CLERK', 3800, NULL, 122, 50);
INSERT INTO employees VALUES (189, 'Jennifer', 'Dilly', 'JDILLY', '650.505.2876', TO_DATE('13-08-2005', 'DD-MM-YYYY'), 'SH_CLERK', 3600, NULL, 122, 50);
INSERT INTO employees VALUES (190, 'Timothy', 'Gates', 'TGATES', '650.505.3876', TO_DATE('11-07-2006', 'DD-MM-YYYY'), 'SH_CLERK', 2900, NULL, 122, 50);
INSERT INTO employees VALUES (191, 'Randall', 'Perkins', 'RPERKINS', '650.505.4876', TO_DATE('19-12-2007', 'DD-MM-YYYY'), 'SH_CLERK', 2500, NULL, 122, 50);
INSERT INTO employees VALUES (192, 'Sarah', 'Bell', 'SBELL', '650.501.1876', TO_DATE('04-02-2004', 'DD-MM-YYYY'), 'SH_CLERK', 4000, NULL, 123, 50);
INSERT INTO employees VALUES (193, 'Britney', 'Everett', 'BEVERETT', '650.501.2876', TO_DATE('03-03-2005', 'DD-MM-YYYY'), 'SH_CLERK', 3900, NULL, 123, 50);
INSERT INTO employees VALUES (194, 'Samuel', 'McCain', 'SMCCAIN', '650.501.3876', TO_DATE('01-07-2006', 'DD-MM-YYYY'), 'SH_CLERK', 3200, NULL, 123, 50);
INSERT INTO employees VALUES (195, 'Vance', 'Jones', 'VJONES', '650.501.4876', TO_DATE('17-03-2007', 'DD-MM-YYYY'), 'SH_CLERK', 2800, NULL, 123, 50);
INSERT INTO employees VALUES (196, 'Alana', 'Walsh', 'AWALSH', '650.507.9811', TO_DATE('24-04-2006', 'DD-MM-YYYY'), 'SH_CLERK', 3100, NULL, 124, 50);
INSERT INTO employees VALUES (197, 'Kevin', 'Feeney', 'KFEENEY', '650.507.9822', TO_DATE('23-05-2006', 'DD-MM-YYYY'), 'SH_CLERK', 3000, NULL, 124, 50);
INSERT INTO employees VALUES (198, 'Donald', 'OConnell', 'DOCONNEL', '650.507.9833', TO_DATE('21-06-2007', 'DD-MM-YYYY'), 'SH_CLERK', 2600, NULL, 124, 50);
INSERT INTO employees VALUES (199, 'Douglas', 'Grant', 'DGRANT', '650.507.9844', TO_DATE('13-01-2008', 'DD-MM-YYYY'), 'SH_CLERK', 2600, NULL, 124, 50);
INSERT INTO employees VALUES (200, 'Jennifer', 'Whalen', 'JWHALEN', '515.123.4444', TO_DATE('17-09-2003', 'DD-MM-YYYY'), 'AD_ASST', 4400, NULL, 101, 10);
INSERT INTO employees VALUES (201, 'Michael', 'Hartstein', 'MHARTSTE', '515.123.5555', TO_DATE('17-02-2004', 'DD-MM-YYYY'), 'MK_MAN', 13000, NULL, 100, 20);
INSERT INTO employees VALUES (202, 'Pat', 'Fay', 'PFAY', '603.123.6666', TO_DATE('17-08-2005', 'DD-MM-YYYY'), 'MK_REP', 6000, NULL, 201, 20);
INSERT INTO employees VALUES (203, 'Susan', 'Mavris', 'SMAVRIS', '515.123.7777', TO_DATE('07-06-2002', 'DD-MM-YYYY'), 'HR_REP', 6500, NULL, 101, 40);
INSERT INTO employees VALUES (204, 'Hermann', 'Baer', 'HBAER', '515.123.8888', TO_DATE('07-06-2002', 'DD-MM-YYYY'), 'PR_REP', 10000, NULL, 101, 70);
INSERT INTO employees VALUES (205, 'Shelley', 'Higgins', 'SHIGGINS', '515.123.8080', TO_DATE('07-06-2002', 'DD-MM-YYYY'), 'AC_MGR', 12008, NULL, 101, 110);
INSERT INTO employees VALUES (206, 'William', 'Gietz', 'WGIETZ', '515.123.8181', TO_DATE('07-06-2002', 'DD-MM-YYYY'), 'AC_ACCOUNT', 8300, NULL, 205, 110);

-- Update departments with manager_id
UPDATE departments SET manager_id = 200 WHERE department_id = 10;
UPDATE departments SET manager_id = 201 WHERE department_id = 20;
UPDATE departments SET manager_id = 114 WHERE department_id = 30;
UPDATE departments SET manager_id = 203 WHERE department_id = 40;
UPDATE departments SET manager_id = 121 WHERE department_id = 50;
UPDATE departments SET manager_id = 103 WHERE department_id = 60;
UPDATE departments SET manager_id = 204 WHERE department_id = 70;
UPDATE departments SET manager_id = 145 WHERE department_id = 80;
UPDATE departments SET manager_id = 100 WHERE department_id = 90;
UPDATE departments SET manager_id = 108 WHERE department_id = 100;
UPDATE departments SET manager_id = 205 WHERE department_id = 110;

-- JOB_HISTORY
INSERT INTO job_history VALUES (102, TO_DATE('13-01-2001', 'DD-MM-YYYY'), TO_DATE('24-07-2006', 'DD-MM-YYYY'), 'IT_PROG', 60);
INSERT INTO job_history VALUES (101, TO_DATE('21-09-1997', 'DD-MM-YYYY'), TO_DATE('27-10-2001', 'DD-MM-YYYY'), 'AC_ACCOUNT', 110);
INSERT INTO job_history VALUES (101, TO_DATE('28-10-2001', 'DD-MM-YYYY'), TO_DATE('15-03-2005', 'DD-MM-YYYY'), 'AC_MGR', 110);
INSERT INTO job_history VALUES (201, TO_DATE('17-02-2004', 'DD-MM-YYYY'), TO_DATE('19-12-2007', 'DD-MM-YYYY'), 'MK_REP', 20);
INSERT INTO job_history VALUES (114, TO_DATE('24-03-2006', 'DD-MM-YYYY'), TO_DATE('31-12-2007', 'DD-MM-YYYY'), 'ST_CLERK', 50);
INSERT INTO job_history VALUES (122, TO_DATE('01-01-2007', 'DD-MM-YYYY'), TO_DATE('31-12-2007', 'DD-MM-YYYY'), 'ST_CLERK', 50);
INSERT INTO job_history VALUES (200, TO_DATE('17-09-1995', 'DD-MM-YYYY'), TO_DATE('17-06-2001', 'DD-MM-YYYY'), 'AD_ASST', 90);
INSERT INTO job_history VALUES (176, TO_DATE('24-03-2006', 'DD-MM-YYYY'), TO_DATE('31-12-2006', 'DD-MM-YYYY'), 'SA_REP', 80);
INSERT INTO job_history VALUES (176, TO_DATE('01-01-2007', 'DD-MM-YYYY'), TO_DATE('31-12-2007', 'DD-MM-YYYY'), 'SA_MAN', 80);
INSERT INTO job_history VALUES (200, TO_DATE('01-07-2002', 'DD-MM-YYYY'), TO_DATE('31-12-2006', 'DD-MM-YYYY'), 'AC_ACCOUNT', 90);

COMMIT;

-- =============================================
-- Create Views
-- =============================================

CREATE OR REPLACE VIEW emp_details_view AS
SELECT
    e.employee_id,
    e.job_id,
    e.manager_id,
    e.department_id,
    d.location_id,
    l.country_id,
    e.first_name,
    e.last_name,
    e.salary,
    e.commission_pct,
    d.department_name,
    j.job_title,
    l.city,
    l.state_province,
    c.country_name,
    r.region_name
FROM
    employees e
    JOIN departments d ON e.department_id = d.department_id
    JOIN jobs j ON j.job_id = e.job_id
    JOIN locations l ON d.location_id = l.location_id
    JOIN countries c ON l.country_id = c.country_id
    JOIN regions r ON c.region_id = r.region_id;

-- Verify data loaded
SELECT 'Employees: ' || COUNT(*) AS count FROM employees;
SELECT 'Departments: ' || COUNT(*) AS count FROM departments;
SELECT 'Jobs: ' || COUNT(*) AS count FROM jobs;
SELECT 'Locations: ' || COUNT(*) AS count FROM locations;
SELECT 'Countries: ' || COUNT(*) AS count FROM countries;

EXIT;
