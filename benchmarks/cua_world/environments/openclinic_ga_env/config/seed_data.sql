-- OpenClinic GA Seed Data
-- Run against BOTH databases (see setup_openclinic.sh which calls this correctly):
--   admin data → ocadmin_dbo (patients, demographics)
--   clinical data → openclinic_dbo (lab, medications, encounters, planning)
--
-- MySQL: /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root
-- Tables are lowercase in OpenClinic GA v5.09.12
-- labcodeother is varchar(1) — only single character allowed
-- No "frequency" column in labanalysis — removed

-- ---------------------------------------------------------------
-- SECTION 1: Patient demographics → ocadmin_dbo
-- ---------------------------------------------------------------
-- Patients use personid starting at 10001 to avoid conflicts with
-- the demo developer account (personid=9966).
-- 10 realistic patients from diverse backgrounds:
--   personid 10001: Ana Ferreira   (used in record_lab_result task)
--   personid 10002: Carlos Mendoza (used in add_prescription task)
--   personid 10003: Fatima Al-Rashid
--   personid 10004: David Okonkwo
--   personid 10005: Maria Santos
--   personid 10006: James Kariuki  (used in register_patient task — but created by agent)
--     NOTE: James Kariuki is NOT pre-seeded here; the agent registers him fresh.
--   personid 10007: Priya Sharma
--   personid 10008: Mohammed Hassan
--   personid 10009: Li Wei
--   personid 10010: Elena Popescu

-- Switch to admin database for patient records
USE ocadmin_dbo;

INSERT IGNORE INTO adminview
    (personid, lastname, firstname, gender, dateofbirth, searchname, updatetime, updateuserid, person_type, updateserverid)
VALUES
    (10001, 'FERREIRA',   'ANA',       'F', '1978-06-14 00:00:00', 'FERREIRA ANA',       NOW(), 1, 'P', 1),
    (10002, 'MENDOZA',    'CARLOS',    'M', '1965-03-22 00:00:00', 'MENDOZA CARLOS',     NOW(), 1, 'P', 1),
    (10003, 'AL-RASHID',  'FATIMA',    'F', '1990-11-05 00:00:00', 'AL-RASHID FATIMA',   NOW(), 1, 'P', 1),
    (10004, 'OKONKWO',    'DAVID',     'M', '1982-08-17 00:00:00', 'OKONKWO DAVID',      NOW(), 1, 'P', 1),
    (10005, 'SANTOS',     'MARIA',     'F', '1955-01-30 00:00:00', 'SANTOS MARIA',       NOW(), 1, 'P', 1),
    (10007, 'SHARMA',     'PRIYA',     'F', '1988-09-12 00:00:00', 'SHARMA PRIYA',       NOW(), 1, 'P', 1),
    (10008, 'HASSAN',     'MOHAMMED',  'M', '1973-04-28 00:00:00', 'HASSAN MOHAMMED',    NOW(), 1, 'P', 1),
    (10009, 'WEI',        'LI',        'M', '1995-07-03 00:00:00', 'WEI LI',             NOW(), 1, 'P', 1),
    (10010, 'POPESCU',    'ELENA',     'F', '1968-12-19 00:00:00', 'POPESCU ELENA',      NOW(), 1, 'P', 1);

-- Address/contact info for these patients
INSERT IGNORE INTO adminprivate
    (privateid, personid, start, address, city, country, telephone, updatetime, type, updateserverid)
VALUES
    (10001, 10001, NOW(), '14 Rua das Flores',  'Lisbon',    'PT', '+351912345001', NOW(), 'H', 1),
    (10002, 10002, NOW(), '27 Calle Mayor',      'Madrid',    'ES', '+34612345002',  NOW(), 'H', 1),
    (10003, 10003, NOW(), '5 Al Nuzha Street',   'Amman',     'JO', '+96279345003',  NOW(), 'H', 1),
    (10004, 10004, NOW(), '33 Lagos Road',       'Lagos',     'NG', '+23480345004',  NOW(), 'H', 1),
    (10005, 10005, NOW(), '88 Avenida Brasil',   'Sao Paulo', 'BR', '+5511345005',   NOW(), 'H', 1),
    (10007, 10007, NOW(), '12 MG Road',          'Bangalore', 'IN', '+91987345007',  NOW(), 'H', 1),
    (10008, 10008, NOW(), '6 Tahrir Square',     'Cairo',     'EG', '+20100345008',  NOW(), 'H', 1),
    (10009, 10009, NOW(), '42 Wangfujing Ave',   'Beijing',   'CN', '+8613845009',   NOW(), 'H', 1),
    (10010, 10010, NOW(), '3 Strada Victoriei',  'Bucharest', 'RO', '+40721345010',  NOW(), 'H', 1);

-- ---------------------------------------------------------------
-- SECTION 2: Health records → openclinic_dbo
-- (Each patient needs a health record to have lab/encounter data)
-- ---------------------------------------------------------------
USE openclinic_dbo;

INSERT IGNORE INTO healthrecord
    (healthRecordId, dateBegin, personId, serverid, version, versionserverid)
VALUES
    (10001, '2020-01-15 00:00:00', 10001, 1, 1, 1),
    (10002, '2019-06-10 00:00:00', 10002, 1, 1, 1),
    (10003, '2021-03-22 00:00:00', 10003, 1, 1, 1),
    (10004, '2018-11-08 00:00:00', 10004, 1, 1, 1),
    (10005, '2016-04-01 00:00:00', 10005, 1, 1, 1),
    (10007, '2022-07-14 00:00:00', 10007, 1, 1, 1),
    (10008, '2017-09-30 00:00:00', 10008, 1, 1, 1),
    (10009, '2023-02-05 00:00:00', 10009, 1, 1, 1),
    (10010, '2015-12-20 00:00:00', 10010, 1, 1, 1);

-- ---------------------------------------------------------------
-- SECTION 3: Lab Analysis catalog entries → openclinic_dbo
-- Fixed schema: labcodeother is varchar(1), no 'frequency' column
-- ---------------------------------------------------------------
INSERT IGNORE INTO labanalysis
    (labcode, labtype, labcodeother, unavailable, limitedvisibility, labgroup, monster, biomonitoring, updateuserid, updatetime, unit, historydays, historyvalues, section)
VALUES
    ('GLUC',   'CHEM', 'G', 0, 0, 'CHEMISTRY',    'blood',    0, 1, NOW(), 'mg/dL',    365, 20, 'Chemistry'),
    ('HBA1C',  'CHEM', 'H', 0, 0, 'CHEMISTRY',    'blood',    0, 1, NOW(), '%',        365, 10, 'Chemistry'),
    ('CHOL',   'CHEM', 'C', 0, 0, 'CHEMISTRY',    'blood',    0, 1, NOW(), 'mg/dL',    365, 10, 'Chemistry'),
    ('CREAT',  'CHEM', 'R', 0, 0, 'CHEMISTRY',    'blood',    0, 1, NOW(), 'mg/dL',    365, 20, 'Chemistry'),
    ('CBC',    'HEMA', 'B', 0, 0, 'HEMATOLOGY',   'blood',    0, 1, NOW(), 'cells/uL', 365, 10, 'Hematology'),
    ('MALAR',  'MICRO','M', 0, 0, 'MICROBIOLOGY', 'blood',    0, 1, NOW(), 'P/F',      365,  5, 'Microbiology'),
    ('URINE',  'UA',   'U', 0, 0, 'URINALYSIS',   'urine',    0, 1, NOW(), NULL,       365,  5, 'Urinalysis'),
    ('BPSYS',  'VITA', 'V', 0, 0, 'VITALS',       'clinical', 0, 1, NOW(), 'mmHg',     365, 50, 'Vitals');

-- ---------------------------------------------------------------
-- SECTION 4: Medications catalog → openclinic_dbo
-- Real WHO Essential Medicines with accurate dosing info
-- ---------------------------------------------------------------
INSERT IGNORE INTO oc_products
    (OC_PRODUCT_SERVERID, OC_PRODUCT_OBJECTID, OC_PRODUCT_NAME, OC_PRODUCT_UNIT,
     OC_PRODUCT_UNITPRICE, OC_PRODUCT_PACKAGEUNITS, OC_PRODUCT_TOTALUNITS,
     OC_PRODUCT_CREATETIME, OC_PRODUCT_UPDATETIME, OC_PRODUCT_UPDATEUID, OC_PRODUCT_VERSION)
VALUES
    (1, 9001, 'Amoxicillin 500mg',               'capsule', 0.50,  30,  300, NOW(), NOW(), 1, 1),
    (1, 9002, 'Metformin 500mg',                  'tablet',  0.20,  60,  600, NOW(), NOW(), 1, 1),
    (1, 9003, 'Paracetamol 500mg',                'tablet',  0.10, 100, 1000, NOW(), NOW(), 1, 1),
    (1, 9004, 'Amlodipine 5mg',                   'tablet',  0.30,  30,  300, NOW(), NOW(), 1, 1),
    (1, 9005, 'Atorvastatin 20mg',                'tablet',  0.40,  30,  300, NOW(), NOW(), 1, 1),
    (1, 9006, 'Lisinopril 10mg',                  'tablet',  0.25,  30,  300, NOW(), NOW(), 1, 1),
    (1, 9007, 'Salbutamol Inhaler 100mcg',        'dose',    2.50, 200,  200, NOW(), NOW(), 1, 1),
    (1, 9008, 'Oral Rehydration Salts',           'sachet',  0.30,  20,  200, NOW(), NOW(), 1, 1),
    (1, 9009, 'Artemether/Lumefantrine 20/120mg', 'tablet',  1.50,  24,  240, NOW(), NOW(), 1, 1),
    (1, 9010, 'Omeprazole 20mg',                  'capsule', 0.35,  30,  300, NOW(), NOW(), 1, 1);

-- ---------------------------------------------------------------
-- Verification counts
-- ---------------------------------------------------------------
SELECT CONCAT('Patients seeded: ', COUNT(*)) AS status
  FROM ocadmin_dbo.adminview WHERE personid BETWEEN 10001 AND 10010;
SELECT CONCAT('Health records:  ', COUNT(*)) AS status
  FROM healthrecord WHERE personId BETWEEN 10001 AND 10010;
SELECT CONCAT('Lab tests:       ', COUNT(*)) AS status
  FROM labanalysis WHERE labcode IN ('GLUC','HBA1C','CHOL','CREAT','CBC','MALAR','URINE','BPSYS');
SELECT CONCAT('Medications:     ', COUNT(*)) AS status
  FROM oc_products WHERE OC_PRODUCT_OBJECTID BETWEEN 9001 AND 9010;
