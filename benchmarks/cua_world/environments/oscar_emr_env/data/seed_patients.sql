-- OSCAR EMR Seed Data
-- Synthea-style synthetic Canadian patient demographics
-- Generated for OSCAR EMR demo environment
-- Provider: Dr. Sarah Chen (999998) linked to oscardoc login

SET NAMES utf8;
SET @save_sql_mode = @@sql_mode;
SET sql_mode = '';

-- ============================================================
-- ENSURE PROVIDER EXISTS (linked to oscardoc login)
-- ============================================================
INSERT IGNORE INTO provider (provider_no, last_name, first_name, provider_type, sex, specialty,
    work_phone, status, ohip_no)
VALUES
('999998', 'Chen', 'Sarah', 'doctor', 'F', 'General Practice',
 '(416) 555-0100', '1', '123456789');

-- ============================================================
-- PATIENT DEMOGRAPHIC DATA (20 patients)
-- Schema: year_of_birth, month_of_birth, date_of_birth are separate varchar fields
--         hin = Health Insurance Number, patient_status = 'AC' for active
-- ============================================================

-- Patient 1: Paul Tremblay (schedule_appointment task target)
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Tremblay', 'Paul', 'M', '1954', '03', '15',
     '15 Birchwood Crescent', 'Mississauga', 'ON', 'L5B 2C3',
     '905-555-0116', 'paul.tremblay@email.ca',
     '999998', '1234567801', 'ON', 'AC', NOW());

-- Patient 2: Margaret Kowalski
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Kowalski', 'Margaret', 'F', '1958', '03', '12',
     '42 Maple Avenue', 'Toronto', 'ON', 'M4B 1V7',
     '416-555-0101', 'margaret.kowalski@email.ca',
     '999998', '1234567890', 'ON', 'AC', NOW());

-- Patient 3: Jonathan Carroll (document_encounter task target)
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Carroll', 'Jonathan', 'M', '1988', '10', '11',
     '77 Fall River Road', 'Fall River', 'ON', 'M0V 2K7',
     '416-555-0285', 'jonathan.carroll@email.ca',
     '999998', '8422813628', 'ON', 'AC', NOW());

-- Patient 4: Priya Patel
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Patel', 'Priya', 'F', '1982', '11', '05',
     '88 Lakeview Drive', 'Brampton', 'ON', 'L6T 3K8',
     '647-555-0103', 'priya.patel@email.ca',
     '999998', '3456789012', 'ON', 'AC', NOW());

-- Patient 5: Robert MacPherson
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('MacPherson', 'Robert', 'M', '1948', '09', '17',
     '233 Elm Street', 'Toronto', 'ON', 'M5T 1K2',
     '416-555-0104', 'robert.macpherson@email.ca',
     '999998', '4567890123', 'ON', 'AC', NOW());

-- Patient 6: Agnes Miller (prescribe_medication task target)
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Miller', 'Agnes', 'F', '1987', '06', '22',
     '55 Queenston Road', 'Hamilton', 'ON', 'L8K 1H1',
     '905-555-0187', 'agnes.miller@email.ca',
     '999998', '7623914850', 'ON', 'AC', NOW());

-- Patient 7: Fatima Al-Hassan
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Al-Hassan', 'Fatima', 'F', '1978', '08', '09',
     '301 Parliament Street', 'Toronto', 'ON', 'M5A 3B1',
     '416-555-0107', 'fatima.alhassan@email.ca',
     '999998', '7890123456', 'ON', 'AC', NOW());

-- Patient 8: Eliseo Nader (add_allergy task target)
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Nader', 'Eliseo', 'M', '1981', '04', '17',
     '89 Harbord Street', 'Toronto', 'ON', 'M5S 1G1',
     '416-555-0108', 'eliseo.nader@email.ca',
     '999998', '8901234567', 'ON', 'AC', NOW());

-- Patient 9: Jean-Pierre Bouchard
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Bouchard', 'Jean-Pierre', 'M', '1965', '06', '30',
     '19 Rideau Terrace', 'Ottawa', 'ON', 'K1N 7B8',
     '613-555-0106', 'jpierre.bouchard@email.ca',
     '999998', '6789012345', 'ON', 'AC', NOW());

-- Patient 10: Mei-Ling Wong
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Wong', 'Mei-Ling', 'F', '1990', '02', '14',
     '7 Harbourfront Way', 'Toronto', 'ON', 'M5J 1A7',
     '416-555-0105', 'meiling.wong@email.ca',
     '999998', '5678901234', 'ON', 'AC', NOW());

-- Patient 11: James Okafor
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Okafor', 'James', 'M', '1971', '12', '03',
     '142 Bloor Street West', 'Toronto', 'ON', 'M5S 1P5',
     '416-555-0111', 'james.okafor@email.ca',
     '999998', '1234509876', 'ON', 'AC', NOW());

-- Patient 12: Maria Santos
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Santos', 'Maria', 'F', '1994', '04', '27',
     '56 Dufferin Street', 'Toronto', 'ON', 'M6H 1Z9',
     '416-555-0112', 'maria.santos@email.ca',
     '999998', '2345098765', 'ON', 'AC', NOW());

-- Patient 13: Thomas Bergmann
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Bergmann', 'Thomas', 'M', '1960', '01', '19',
     '311 King Street East', 'Kitchener', 'ON', 'N2G 2L5',
     '519-555-0113', 'thomas.bergmann@email.ca',
     '999998', '3450987654', 'ON', 'AC', NOW());

-- Patient 14: Ananya Krishnamurthy
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Krishnamurthy', 'Ananya', 'F', '1986', '09', '08',
     '25 University Avenue', 'Toronto', 'ON', 'M5J 2N7',
     '416-555-0114', 'ananya.krishnamurthy@email.ca',
     '999998', '4509876543', 'ON', 'AC', NOW());

-- Patient 15: Liam Fitzgerald
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Fitzgerald', 'Liam', 'M', '2001', '07', '23',
     '78 Yonge Street', 'Toronto', 'ON', 'M5E 1G1',
     '647-555-0115', 'liam.fitzgerald@email.ca',
     '999998', '5098765432', 'ON', 'AC', NOW());

-- Patient 16: Olena Petrenko
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Petrenko', 'Olena', 'F', '1975', '11', '30',
     '44 Davisville Avenue', 'Toronto', 'ON', 'M4S 1G3',
     '416-555-0116', 'olena.petrenko@email.ca',
     '999998', '0987654321', 'ON', 'AC', NOW());

-- Patient 17: Mohammed Al-Rashid
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Al-Rashid', 'Mohammed', 'M', '1969', '05', '14',
     '201 Bay Street', 'Toronto', 'ON', 'M5J 2W6',
     '416-555-0117', 'mohammed.alrashid@email.ca',
     '999998', '9876543210', 'ON', 'AC', NOW());

-- Patient 18: Sophie Larochelle
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Larochelle', 'Sophie', 'F', '1993', '02', '28',
     '35 Sparks Street', 'Ottawa', 'ON', 'K1P 5A8',
     '613-555-0118', 'sophie.larochelle@email.ca',
     '999998', '8765432109', 'ON', 'AC', NOW());

-- Patient 19: Victor Chukwuemeka
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Chukwuemeka', 'Victor', 'M', '1979', '08', '22',
     '90 Eglinton Avenue East', 'Toronto', 'ON', 'M4P 2Y3',
     '416-555-0119', 'victor.chukwuemeka@email.ca',
     '999998', '7654321098', 'ON', 'AC', NOW());

-- Patient 20: Helena Varga
INSERT IGNORE INTO demographic
    (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
     address, city, province, postal, phone, email,
     provider_no, hin, hc_type, patient_status, lastUpdateDate)
VALUES
    ('Varga', 'Helena', 'F', '1963', '12', '05',
     '12 Queensway', 'Etobicoke', 'ON', 'M8Y 1J3',
     '416-555-0120', 'helena.varga@email.ca',
     '999998', '6543210987', 'ON', 'AC', NOW());

-- ============================================================
-- ALLERGIES (for Eliseo Nader and others)
-- Table: allergies (ALLERGY_ID, DEMOGRAPHIC_NO, ENTRY_DATE, DESCRIPTION,
--                   REACTION, SEVERITY_OF_REACTION, TYPECODE, ARCHIVED, ONSET, LASTUPDATE)
-- TYPECODE: 0=Drug, 1=Food, 2=Other/Environmental
-- ============================================================

-- Allergy: Eliseo Nader - Penicillin (pre-existing, different from task allergy)
-- severity_of_reaction is char(1): M=Mild, Mo=Moderate, S=Severe
INSERT IGNORE INTO allergies
    (demographic_no, entry_date, DESCRIPTION, reaction, severity_of_reaction, TYPECODE, archived, lastUpdateDate)
SELECT d.demographic_no, CURDATE(), 'Penicillin', 'Skin rash', 'M', 0, 0, NOW()
FROM demographic d WHERE d.first_name='Eliseo' AND d.last_name='Nader' LIMIT 1;

-- Allergy: Agnes Miller - Sulfa drugs
INSERT IGNORE INTO allergies
    (demographic_no, entry_date, DESCRIPTION, reaction, severity_of_reaction, TYPECODE, archived, lastUpdateDate)
SELECT d.demographic_no, CURDATE(), 'Sulfonamides', 'Hives', 'M', 0, 0, NOW()
FROM demographic d WHERE d.first_name='Agnes' AND d.last_name='Miller' LIMIT 1;

-- Allergy: Margaret Kowalski - Latex
INSERT IGNORE INTO allergies
    (demographic_no, entry_date, DESCRIPTION, reaction, severity_of_reaction, TYPECODE, archived, lastUpdateDate)
SELECT d.demographic_no, CURDATE(), 'Latex', 'Contact dermatitis', 'M', 2, 0, NOW()
FROM demographic d WHERE d.first_name='Margaret' AND d.last_name='Kowalski' LIMIT 1;

-- ============================================================
-- MEDICATIONS (drugs table)
-- Fields: id, demographic_no, provider_no, rx_date, end_date,
--         GN (generic name), BN (brand name), dosage, route, frequency
-- ============================================================

-- Jonathan Carroll - Lisinopril (for hypertension, ties into document_encounter task)
-- drugs schema: freqcode (varchar 6), duration (varchar 4), durunit (char 1: d=days), quantity (varchar 20), repeat (tinyint)
INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route, freqcode,
     duration, durunit, quantity, `repeat`, archived, lastUpdateDate)
SELECT d.demographic_no, '999998', CURDATE(), '0001-01-01',
       'Lisinopril', 'Prinivil', '10mg', 'PO', 'od',
       '90', 'd', '90', 3, 0, NOW()
FROM demographic d WHERE d.first_name='Jonathan' AND d.last_name='Carroll' LIMIT 1;

-- Paul Tremblay - Metformin
INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route, freqcode,
     duration, durunit, quantity, `repeat`, archived, lastUpdateDate)
SELECT d.demographic_no, '999998', CURDATE(), '0001-01-01',
       'Metformin', 'Glucophage', '500mg', 'PO', 'bid',
       '90', 'd', '180', 3, 0, NOW()
FROM demographic d WHERE d.first_name='Paul' AND d.last_name='Tremblay' LIMIT 1;

-- Agnes Miller - Atorvastatin
INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route, freqcode,
     duration, durunit, quantity, `repeat`, archived, lastUpdateDate)
SELECT d.demographic_no, '999998', CURDATE(), '0001-01-01',
       'Atorvastatin', 'Lipitor', '20mg', 'PO', 'od',
       '90', 'd', '90', 3, 0, NOW()
FROM demographic d WHERE d.first_name='Agnes' AND d.last_name='Miller' LIMIT 1;

-- Margaret Kowalski - Levothyroxine
INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route, freqcode,
     duration, durunit, quantity, `repeat`, archived, lastUpdateDate)
SELECT d.demographic_no, '999998', CURDATE(), '0001-01-01',
       'Levothyroxine', 'Synthroid', '50mcg', 'PO', 'od',
       '90', 'd', '90', 3, 0, NOW()
FROM demographic d WHERE d.first_name='Margaret' AND d.last_name='Kowalski' LIMIT 1;

SET sql_mode = @save_sql_mode;
