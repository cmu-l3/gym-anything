-- =============================================================================
-- OpenEMR Realistic Patient Data
-- Generated from Synthea Synthetic Health Data
-- https://github.com/synthetichealth/synthea
--
-- This data includes:
--   - Patient demographics with diverse backgrounds
--   - Medical conditions/problems (ICD/SNOMED coded)
--   - Medications/prescriptions (RxNorm coded)
--   - Allergies
--   - Encounter history
--
-- The data is synthetic but medically realistic, suitable for:
--   - AI agent testing
--   - EHR workflow demonstrations
--   - Training and education
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 0;


-- Synthea-generated patient data
-- Realistic synthetic patients with full demographics

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    1, 1, 'P1001', 'Jacinto', 'Kris',
    '', '2017-08-24',
    'Male', '999-68-6630',
    '888 Hickle Ferry Suite 38', 'Springfield', 'MA', '01106', 'US',
    '(011) 555-8169', '(011) 555-5919',
    'jacinto.kris@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    2, 2, 'P1002', 'Alva', 'Krajcik',
    '', '2016-08-01',
    'Female', '999-15-5895',
    '1048 Skiles Trailer', 'Walpole', 'MA', '02081', 'US',
    '(020) 555-9452', '(020) 555-9306',
    'alva.krajcik@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    3, 3, 'P1003', 'Jayson', 'Fadel',
    '', '1992-06-30',
    'Male', '999-27-3385',
    '1056 Harris Lane Suite 70', 'Chicopee', 'MA', '01020', 'US',
    '(010) 555-1605', '(010) 555-5881',
    'jayson.fadel@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99971451', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    4, 4, 'P1004', 'Jimmie', 'Harris',
    '', '2004-01-09',
    'Female', '999-73-2461',
    '201 Mitchell Lodge Unit 67', 'Pembroke', 'MA', '', 'US',
    '(555) 555-8836', '(555) 555-6606',
    'jimmie.harris@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99956432', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    5, 5, 'P1005', 'Gregorio', 'Auer',
    '', '1996-11-15',
    'Male', '999-60-7372',
    '1050 Lindgren Extension Apt 38', 'Boston', 'MA', '02135', 'US',
    '(021) 555-1942', '(021) 555-5086',
    'gregorio.auer@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99917327', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    6, 6, 'P1006', 'Karyn', 'Mueller',
    '', '2019-06-12',
    'Female', '999-81-4349',
    '570 Abshire Forge Suite 32', 'Colrain', 'MA', '', 'US',
    '(555) 555-9518', '(555) 555-1583',
    'karyn.mueller@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    7, 7, 'P1007', 'Milo', 'Feil',
    '', '1983-12-12',
    'Male', '999-73-5361',
    '422 Farrell Path Unit 69', 'Somerville', 'MA', '02143', 'US',
    '(021) 555-4691', '(021) 555-8718',
    'milo.feil@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99960247', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    8, 8, 'P1008', 'José Eduardo', 'Gómez',
    '', '1989-06-22',
    'Male', '999-76-6866',
    '427 Balistreri Way Unit 19', 'Chicopee', 'MA', '01013', 'US',
    '(010) 555-8407', '(010) 555-9574',
    'josé eduardo.gómez@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99979025', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    9, 9, 'P1009', 'Karyn', 'Metz',
    '', '1991-07-31',
    'Female', '999-74-9712',
    '181 Feest Passage Suite 64', 'Medfield', 'MA', '02052', 'US',
    '(020) 555-7442', '(020) 555-4972',
    'karyn.metz@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99966383', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    10, 10, 'P1010', 'Jeffrey', 'Greenfelder',
    '', '2005-01-16',
    'Male', '999-78-4480',
    '428 Wiza Glen Unit 91', 'Springfield', 'MA', '01104', 'US',
    '(011) 555-6293', '(011) 555-8008',
    'jeffrey.greenfelder@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    11, 11, 'P1011', 'Mariana', 'Hane',
    '', '1978-06-24',
    'Female', '999-85-4926',
    '999 Kuhn Forge', 'Lowell', 'MA', '01851', 'US',
    '(018) 555-3235', '(018) 555-2673',
    'mariana.hane@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99982373', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    12, 12, 'P1012', 'Leann', 'Deckow',
    '', '1989-07-05',
    'Female', '999-24-1237',
    '118 Bailey Orchard Suite 34', 'Needham', 'MA', '', 'US',
    '(555) 555-3441', '(555) 555-9561',
    'leann.deckow@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99910262', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    13, 13, 'P1013', 'Christal', 'Brown',
    '', '1982-09-29',
    'Female', '999-21-5604',
    '1060 Hansen Overpass Suite 86', 'Boston', 'MA', '02118', 'US',
    '(021) 555-6054', '(021) 555-8113',
    'christal.brown@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99921528', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    14, 14, 'P1014', 'Lisbeth', 'Rowe',
    '', '1983-09-30',
    'Female', '999-57-9112',
    '290 Hyatt Lane', 'Malden', 'MA', '02155', 'US',
    '(021) 555-3116', '(021) 555-7254',
    'lisbeth.rowe@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99937871', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    15, 15, 'P1015', 'Carmelia', 'Konopelski',
    '', '2000-12-19',
    'Female', '999-28-2716',
    '1025 Collier Arcade', 'Ashland', 'MA', '', 'US',
    '(555) 555-8048', '(555) 555-4586',
    'carmelia.konopelski@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99985509', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    16, 16, 'P1016', 'Raye', 'Wyman',
    '', '1957-03-25',
    'Female', '999-66-4231',
    '585 Greenfelder Camp', 'Quincy', 'MA', '02169', 'US',
    '(021) 555-5647', '(021) 555-7606',
    'raye.wyman@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99961255', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    17, 17, 'P1017', 'Amada', 'Spinka',
    '', '1958-07-29',
    'Female', '999-76-2715',
    '970 Grant Highlands', 'Foxborough', 'MA', '', 'US',
    '(555) 555-5676', '(555) 555-7708',
    'amada.spinka@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99916782', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    18, 18, 'P1018', 'Cythia', 'Reichel',
    '', '1999-03-03',
    'Female', '999-85-6755',
    '211 Effertz Quay', 'Peabody', 'MA', '01960', 'US',
    '(019) 555-5428', '(019) 555-5378',
    'cythia.reichel@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99938879', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    19, 19, 'P1019', 'Yolanda', 'Gollum',
    '', '1970-06-13',
    'Female', '999-38-7030',
    '540 Gibson Green', 'Fall River', 'MA', '', 'US',
    '(555) 555-7888', '(555) 555-1239',
    'yolanda.gollum@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99955092', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    20, 20, 'P1020', 'María Soledad', 'Aparicio',
    '', '2017-03-23',
    'Female', '999-40-3169',
    '547 Ziemann Burg', 'Boston', 'MA', '02215', 'US',
    '(022) 555-8907', '(022) 555-3097',
    'maría soledad.aparicio@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    21, 21, 'P1021', 'Anissa', 'Mueller',
    '', '1959-06-23',
    'Female', '999-59-1261',
    '661 Schulist Highlands', 'Waltham', 'MA', '02452', 'US',
    '(024) 555-7558', '(024) 555-5663',
    'anissa.mueller@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99928544', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    22, 22, 'P1022', 'Danae', 'Franecki',
    '', '1958-05-09',
    'Female', '999-49-5916',
    '1062 Conn Well Suite 4', 'Framingham', 'MA', '01702', 'US',
    '(017) 555-2063', '(017) 555-2462',
    'danae.franecki@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99935194', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    23, 23, 'P1023', 'Margurite', 'Bernhard',
    '', '1986-02-25',
    'Female', '999-89-1141',
    '471 Mayert Flat Unit 54', 'Peabody', 'MA', '', 'US',
    '(555) 555-4372', '(555) 555-1070',
    'margurite.bernhard@email.com',
    'amer_ind_or_alaska_native', 'hisp_or_latin',
    'English', 'married',
    'S99986137', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    24, 24, 'P1024', 'Frankie', 'Bernier',
    '', '1983-10-10',
    'Female', '999-45-5448',
    '687 Howell Frontage road Apt 68', 'Abington', 'MA', '02351', 'US',
    '(023) 555-7628', '(023) 555-6759',
    'frankie.bernier@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99951460', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    25, 25, 'P1025', 'Edmund', 'Walker',
    '', '1954-05-02',
    'Male', '999-88-9161',
    '383 Crooks Camp', 'Norwell', 'MA', '', 'US',
    '(555) 555-9428', '(555) 555-8425',
    'edmund.walker@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99952034', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    26, 26, 'P1026', 'Margert', 'DuBuque',
    '', '1971-01-19',
    'Female', '999-95-4888',
    '560 Herman Bridge', 'Malden', 'MA', '', 'US',
    '(555) 555-7680', '(555) 555-3281',
    'margert.dubuque@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99959100', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    27, 27, 'P1027', 'Luciana', 'Williamson',
    '', '1993-04-06',
    'Female', '999-21-6421',
    '703 Stehr Walk', 'Chelmsford', 'MA', '', 'US',
    '(555) 555-2800', '(555) 555-9416',
    'luciana.williamson@email.com',
    'asian', 'hisp_or_latin',
    'English', 'married',
    'S99974558', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    28, 28, 'P1028', 'Victor', 'Dickinson',
    '', '2005-12-28',
    'Male', '999-75-9476',
    '765 Harber Club', 'Winchester', 'MA', '01890', 'US',
    '(018) 555-4988', '(018) 555-3173',
    'victor.dickinson@email.com',
    'asian', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    29, 29, 'P1029', 'Erwin', 'Weimann',
    '', '1987-08-31',
    'Male', '999-47-3790',
    '297 Fritsch Estate Apt 24', 'Lynnfield', 'MA', '', 'US',
    '(555) 555-8389', '(555) 555-8919',
    'erwin.weimann@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99987128', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    30, 30, 'P1030', 'Kim', 'Donnelly',
    '', '1967-04-23',
    'Female', '999-30-3779',
    '562 Windler Tunnel', 'Fitchburg', 'MA', '', 'US',
    '(555) 555-1311', '(555) 555-6806',
    'kim.donnelly@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99929765', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    31, 31, 'P1031', 'Ashton', 'Goldner',
    '', '1967-07-12',
    'Female', '999-95-2422',
    '257 Jerde Rue', 'Quincy', 'MA', '02170', 'US',
    '(021) 555-8539', '(021) 555-8857',
    'ashton.goldner@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99922379', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    32, 32, 'P1032', 'Louie', 'Jacobi',
    '', '1973-08-01',
    'Male', '999-85-9257',
    '255 Ondricka Common', 'Deerfield', 'MA', '', 'US',
    '(555) 555-1868', '(555) 555-2942',
    'louie.jacobi@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99981102', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    33, 33, 'P1033', 'Marvel', 'Wyman',
    '', '1965-11-11',
    'Female', '999-85-8713',
    '913 Schiller Well Apt 80', 'Burlington', 'MA', '01803', 'US',
    '(018) 555-3368', '(018) 555-2313',
    'marvel.wyman@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99975142', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    34, 34, 'P1034', 'Christene', 'Brakus',
    '', '1994-06-28',
    'Female', '999-33-5858',
    '229 Feest Landing Unit 4', 'Plymouth', 'MA', '02360', 'US',
    '(023) 555-8055', '(023) 555-1649',
    'christene.brakus@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99973245', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    35, 35, 'P1035', 'Wesley', 'Rau',
    '', '1967-07-12',
    'Male', '999-15-5162',
    '788 Wilderman Vale', 'New Bedford', 'MA', '', 'US',
    '(555) 555-1520', '(555) 555-9323',
    'wesley.rau@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99965704', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    36, 36, 'P1036', 'Dorothea', 'Ward',
    '', '2018-08-16',
    'Female', '999-65-5107',
    '1079 Kuhn Orchard', 'Lowell', 'MA', '01854', 'US',
    '(018) 555-4105', '(018) 555-7305',
    'dorothea.ward@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    37, 37, 'P1037', 'Lorrie', 'Leannon',
    '', '2013-07-30',
    'Female', '999-82-6451',
    '813 Casper Street', 'Peabody', 'MA', '01940', 'US',
    '(019) 555-2082', '(019) 555-3941',
    'lorrie.leannon@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    38, 38, 'P1038', 'Mabel', 'Dach',
    '', '1986-09-20',
    'Female', '999-39-5390',
    '844 Hammes Byway', 'Framingham', 'MA', '01702', 'US',
    '(017) 555-8521', '(017) 555-5583',
    'mabel.dach@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99940973', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    39, 39, 'P1039', 'Joleen', 'Quitzon',
    '', '2002-01-24',
    'Female', '999-83-2956',
    '976 Bode Parade Apt 52', 'Greenfield', 'MA', '', 'US',
    '(555) 555-1392', '(555) 555-3464',
    'joleen.quitzon@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99962510', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    40, 40, 'P1040', 'Cesar', 'Klein',
    '', '1972-09-22',
    'Male', '999-58-9266',
    '907 Ernser Parade Unit 37', 'Amherst', 'MA', '', 'US',
    '(555) 555-7568', '(555) 555-5048',
    'cesar.klein@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99951549', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    41, 41, 'P1041', 'Carlton', 'Breitenberg',
    'JD', '1979-06-13',
    'Male', '999-19-9482',
    '789 Torphy Trafficway Suite 59', 'Medfield', 'MA', '', 'US',
    '(555) 555-1763', '(555) 555-3908',
    'carlton.breitenberg@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99923892', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    42, 42, 'P1042', 'Carol', 'Harber',
    '', '1968-09-12',
    'Male', '999-88-9678',
    '119 Steuber Key', 'Salisbury', 'MA', '', 'US',
    '(555) 555-6398', '(555) 555-2049',
    'carol.harber@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    'S99949484', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    43, 43, 'P1043', 'Stanford', 'Goodwin',
    '', '1969-03-22',
    'Male', '999-12-7459',
    '314 Torp Byway', 'Somerville', 'MA', '02140', 'US',
    '(021) 555-9926', '(021) 555-4789',
    'stanford.goodwin@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99953931', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    44, 44, 'P1044', 'Richie', 'Goyette',
    '', '2012-05-26',
    'Male', '999-69-6192',
    '369 Friesen Manor Suite 94', 'Framingham', 'MA', '', 'US',
    '(555) 555-1186', '(555) 555-5935',
    'richie.goyette@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    45, 45, 'P1045', 'Ira', 'Stark',
    '', '1982-06-19',
    'Male', '999-95-2021',
    '1040 Morar Approach', 'Weymouth', 'MA', '02189', 'US',
    '(021) 555-9980', '(021) 555-6435',
    'ira.stark@email.com',
    'white', 'hisp_or_latin',
    'English', 'married',
    'S99923556', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);

INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    46, 46, 'P1046', 'Timmy', 'Macejkovic',
    '', '2007-06-18',
    'Male', '999-36-9345',
    '385 Sipes Orchard Apt 71', 'Brockton', 'MA', '02301', 'US',
    '(023) 555-1067', '(023) 555-6964',
    'timmy.macejkovic@email.com',
    'white', 'hisp_or_latin',
    'English', 'single',
    '', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);


-- Patient medical problems/conditions
-- Lists (problems list)

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (1, 1, 'medical_problem', 'Otitis media', 'SNOMED:65363002',
    '2019-02-15', '2019-08-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (2, 1, 'medical_problem', 'Otitis media', 'SNOMED:65363002',
    '2019-10-30', '2020-01-30', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (3, 1, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-01', '2020-03-30', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (4, 1, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-01', '2020-03-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (5, 1, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-01', '2020-03-30', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (6, 2, 'medical_problem', 'Sprain of ankle', 'SNOMED:44465007',
    '2020-02-12', '2020-02-26', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (7, 2, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-13', '2020-04-14', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (8, 2, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-03-13', '2020-04-14', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (9, 2, 'medical_problem', 'Diarrhea symptom (finding)', 'SNOMED:267060006',
    '2020-03-13', '2020-04-14', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (10, 2, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-13', '2020-04-14', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (11, 2, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-13', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (12, 2, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-13', '2020-04-14', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (13, 2, 'medical_problem', 'Streptococcal sore throat (disorder)', 'SNOMED:43878008',
    '2020-04-28', '2020-05-08', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (14, 3, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '2010-08-24', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (15, 3, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '2019-11-24', '2019-12-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (16, 3, 'medical_problem', 'Headache (finding)', 'SNOMED:25064002',
    '2020-03-11', '2020-04-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (17, 3, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-11', '2020-04-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (18, 3, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-11', '2020-04-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (19, 3, 'medical_problem', 'Nausea (finding)', 'SNOMED:422587007',
    '2020-03-11', '2020-04-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (20, 3, 'medical_problem', 'Vomiting symptom (finding)', 'SNOMED:249497008',
    '2020-03-11', '2020-04-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (21, 3, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-11', '2020-04-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (22, 3, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-11', '2020-04-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (23, 3, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-11', '2020-03-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (24, 4, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-01', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (25, 4, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-03-01', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (26, 4, 'medical_problem', 'Nausea (finding)', 'SNOMED:422587007',
    '2020-03-01', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (27, 4, 'medical_problem', 'Vomiting symptom (finding)', 'SNOMED:249497008',
    '2020-03-01', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (28, 4, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-01', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (29, 4, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-01', '2020-03-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (30, 4, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-02', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (31, 5, 'medical_problem', 'Nasal congestion (finding)', 'SNOMED:68235000',
    '2020-03-02', '2020-03-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (32, 5, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-02', '2020-03-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (33, 5, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-03-02', '2020-03-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (34, 5, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-02', '2020-03-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (35, 5, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-02', '2020-03-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (36, 5, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-02', '2020-03-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (37, 5, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-02', '2020-03-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (38, 6, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-02-18', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (39, 6, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-02-18', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (40, 6, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-02-18', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (41, 6, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-02-18', '2020-02-19', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (42, 6, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-02-19', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (43, 6, 'medical_problem', 'Pneumonia (disorder)', 'SNOMED:233604007',
    '2020-02-19', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (44, 6, 'medical_problem', 'Hypoxemia (disorder)', 'SNOMED:389087006',
    '2020-02-19', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (45, 6, 'medical_problem', 'Respiratory distress (finding)', 'SNOMED:271825005',
    '2020-02-19', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (46, 6, 'medical_problem', 'Acute pulmonary embolism (disorder)', 'SNOMED:706870000',
    '2020-02-25', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (47, 7, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '2020-01-16', '2020-01-23', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (48, 7, 'medical_problem', 'Headache (finding)', 'SNOMED:25064002',
    '2020-02-25', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (49, 7, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-02-25', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (50, 7, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-02-25', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (51, 7, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-02-25', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (52, 7, 'medical_problem', 'Joint pain (finding)', 'SNOMED:57676002',
    '2020-02-25', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (53, 7, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-02-25', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (54, 7, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-02-25', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (55, 7, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-02-25', '2020-02-25', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (56, 7, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-02-25', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (57, 8, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2007-08-16', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (58, 8, 'medical_problem', 'Prediabetes', 'SNOMED:15777000',
    '2014-08-28', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (59, 8, 'medical_problem', 'Fracture of clavicle', 'SNOMED:58150001',
    '2019-09-13', '2019-12-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (60, 8, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-07', '2020-04-04', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (61, 8, 'medical_problem', 'Sore throat symptom (finding)', 'SNOMED:267102003',
    '2020-03-07', '2020-04-04', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (62, 8, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-07', '2020-04-04', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (63, 8, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-07', '2020-03-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (64, 8, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-07', '2020-04-04', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (65, 9, 'medical_problem', 'Brain damage - traumatic', 'SNOMED:275272006',
    '1995-04-11', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (66, 9, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2011-09-28', '2011-10-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (67, 9, 'medical_problem', 'Miscarriage in first trimester', 'SNOMED:19169002',
    '2011-09-28', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (68, 9, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2012-04-25', '2012-05-23', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (69, 9, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2019-12-03', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (70, 9, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-02-28', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (71, 9, 'medical_problem', 'Joint pain (finding)', 'SNOMED:57676002',
    '2020-02-28', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (72, 9, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-02-28', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (73, 9, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-02-28', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (74, 9, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-02-28', '2020-02-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (75, 10, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2017-02-05', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (76, 10, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (77, 10, 'medical_problem', 'Sore throat symptom (finding)', 'SNOMED:267102003',
    '2020-03-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (78, 10, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (79, 10, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-03-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (80, 10, 'medical_problem', 'Joint pain (finding)', 'SNOMED:57676002',
    '2020-03-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (81, 10, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (82, 10, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-02', '2020-03-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (83, 11, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '1996-08-17', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (84, 11, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-11', '2020-04-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (85, 11, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-11', '2020-04-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (86, 11, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-03-11', '2020-04-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (87, 11, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-03-11', '2020-04-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (88, 11, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-11', '2020-04-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (89, 11, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-11', '2020-03-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (90, 11, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-11', '2020-04-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (91, 12, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2011-09-07', '2012-04-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (92, 12, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2015-10-21', '2016-05-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (93, 12, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2019-02-20', '2019-10-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (94, 12, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2020-03-11', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (95, 12, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-08', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (96, 12, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-03-08', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (97, 12, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-08', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (98, 12, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-08', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (99, 12, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-08', '2020-03-08', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (100, 12, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-08', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (101, 13, 'medical_problem', 'Perennial allergic rhinitis', 'SNOMED:446096008',
    '1984-10-05', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (102, 13, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '2000-11-22', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (103, 13, 'medical_problem', 'Pulmonary emphysema (disorder)', 'SNOMED:87433001',
    '2015-02-11', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (104, 13, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-13', '2020-04-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (105, 13, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-13', '2020-04-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (106, 13, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-13', '2020-04-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (107, 13, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-13', '2020-04-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (108, 13, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-13', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (109, 13, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-13', '2020-04-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (110, 14, 'medical_problem', 'Chronic sinusitis (disorder)', 'SNOMED:40055000',
    '1989-06-14', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (111, 14, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2008-12-05', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (112, 14, 'medical_problem', 'Miscarriage in first trimester', 'SNOMED:19169002',
    '2011-06-17', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (113, 14, 'medical_problem', 'Coronary Heart Disease', 'SNOMED:53741008',
    '2017-10-13', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (114, 14, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-07', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (115, 14, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-07', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (116, 14, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-03-07', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (117, 14, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-03-07', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (118, 14, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-07', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (119, 14, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-07', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (120, 15, 'medical_problem', 'Perennial allergic rhinitis', 'SNOMED:446096008',
    '2002-12-26', '2019-12-24', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (121, 15, 'medical_problem', 'Childhood asthma', 'SNOMED:233678006',
    '2004-12-25', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (122, 15, 'medical_problem', 'Malignant neoplasm of breast (disorder)', 'SNOMED:254837009',
    '2010-12-17', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (123, 15, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-03-13', '2020-04-08', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (124, 15, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-03-13', '2020-04-08', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (125, 15, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-13', '2020-04-08', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (126, 15, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-13', '2020-04-08', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (127, 15, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-13', '2020-03-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (128, 15, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-13', '2020-04-08', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (129, 16, 'medical_problem', 'Brain damage - traumatic', 'SNOMED:275272006',
    '1962-10-25', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (130, 16, 'medical_problem', 'Stroke', 'SNOMED:230690007',
    '1990-06-11', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (131, 16, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '1994-06-13', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (132, 16, 'medical_problem', 'Chronic sinusitis (disorder)', 'SNOMED:40055000',
    '2012-07-08', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (133, 16, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '2019-06-04', '2019-06-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (134, 16, 'medical_problem', 'Headache (finding)', 'SNOMED:25064002',
    '2020-03-06', '2020-03-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (135, 16, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-06', '2020-03-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (136, 16, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-03-06', '2020-03-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (137, 16, 'medical_problem', 'Diarrhea symptom (finding)', 'SNOMED:267060006',
    '2020-03-06', '2020-03-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (138, 16, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-06', '2020-03-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (139, 17, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2000-08-08', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (140, 17, 'medical_problem', 'Drug overdose', 'SNOMED:55680006',
    '2003-09-08', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (141, 17, 'medical_problem', 'Prediabetes', 'SNOMED:15777000',
    '2010-08-10', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (142, 17, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-03-05', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (143, 17, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-05', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (144, 17, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-05', '2020-03-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (145, 17, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-05', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (146, 18, 'medical_problem', 'Miscarriage in first trimester', 'SNOMED:19169002',
    '2016-07-06', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (147, 19, 'medical_problem', 'Perennial allergic rhinitis', 'SNOMED:446096008',
    '1972-06-19', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (148, 19, 'medical_problem', 'Cardiac Arrest', 'SNOMED:410429000',
    '1983-04-16', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (149, 19, 'medical_problem', 'History of cardiac arrest (situation)', 'SNOMED:429007001',
    '1983-04-16', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (150, 19, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2001-08-25', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (151, 19, 'medical_problem', 'Osteoarthritis of knee', 'SNOMED:239873007',
    '2014-06-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (152, 19, 'medical_problem', 'Miscarriage in first trimester', 'SNOMED:19169002',
    '2017-02-18', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (153, 19, 'medical_problem', 'Headache (finding)', 'SNOMED:25064002',
    '2020-03-10', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (154, 19, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-10', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (155, 19, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-03-10', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (156, 19, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-03-10', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (157, 20, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-02-28', '2020-03-19', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (158, 20, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-02-28', '2020-03-19', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (159, 20, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-02-28', '2020-03-19', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (160, 20, 'medical_problem', 'Joint pain (finding)', 'SNOMED:57676002',
    '2020-02-28', '2020-03-19', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (161, 20, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-02-28', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (162, 20, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-02-28', '2020-03-19', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (163, 20, 'medical_problem', 'Perennial allergic rhinitis with seasonal variation', 'SNOMED:232353008',
    '2020-03-29', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (164, 20, 'medical_problem', 'Childhood asthma', 'SNOMED:233678006',
    '2020-03-29', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (165, 21, 'medical_problem', 'Chronic sinusitis (disorder)', 'SNOMED:40055000',
    '1972-12-13', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (166, 21, 'medical_problem', 'Miscarriage in first trimester', 'SNOMED:19169002',
    '1984-11-13', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (167, 21, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '1990-09-04', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (168, 21, 'medical_problem', 'Osteoarthritis of hip', 'SNOMED:239872002',
    '2006-06-11', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (169, 21, 'medical_problem', 'Malignant neoplasm of breast (disorder)', 'SNOMED:254837009',
    '2007-06-11', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (170, 21, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '2019-05-28', '2019-06-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (171, 21, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-14', '2020-03-27', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (172, 21, 'medical_problem', 'Sore throat symptom (finding)', 'SNOMED:267102003',
    '2020-03-14', '2020-03-27', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (173, 21, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-14', '2020-03-27', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (174, 21, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-14', '2020-03-14', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (175, 22, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '1976-07-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (176, 22, 'medical_problem', 'Chronic sinusitis (disorder)', 'SNOMED:40055000',
    '1982-08-04', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (177, 22, 'medical_problem', 'Cardiac Arrest', 'SNOMED:410429000',
    '1986-07-04', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (178, 22, 'medical_problem', 'History of cardiac arrest (situation)', 'SNOMED:429007001',
    '1986-07-04', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (179, 22, 'medical_problem', 'Miscarriage in first trimester', 'SNOMED:19169002',
    '1992-07-03', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (180, 22, 'medical_problem', 'Osteoarthritis of hip', 'SNOMED:239872002',
    '1995-04-30', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (181, 22, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2000-11-17', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (182, 22, 'medical_problem', 'Malignant neoplasm of breast (disorder)', 'SNOMED:254837009',
    '2007-04-27', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (183, 22, 'medical_problem', 'Hyperlipidemia', 'SNOMED:55822004',
    '2014-01-31', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (184, 22, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-02-29', '2020-03-08', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (185, 23, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '2004-04-20', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (186, 23, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2005-10-11', '2005-11-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (187, 23, 'medical_problem', 'Prediabetes', 'SNOMED:15777000',
    '2012-06-05', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (188, 23, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-02-27', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (189, 23, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-02-27', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (190, 23, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-02-27', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (191, 23, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-02-27', '2020-02-27', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (192, 23, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-02-27', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (193, 23, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2020-03-17', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (194, 24, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2017-12-25', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (195, 24, 'medical_problem', 'Sputum finding (finding)', 'SNOMED:248595008',
    '2020-03-05', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (196, 24, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-03-05', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (197, 24, 'medical_problem', 'Joint pain (finding)', 'SNOMED:57676002',
    '2020-03-05', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (198, 24, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-05', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (199, 24, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-05', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (200, 24, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-05', '2020-03-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (201, 24, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-05', '2020-03-20', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (202, 25, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '1989-04-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (203, 25, 'medical_problem', 'Hyperlipidemia', 'SNOMED:55822004',
    '2005-05-08', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (204, 25, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-04', '2020-03-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (205, 25, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-04', '2020-03-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (206, 25, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-04', '2020-03-04', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (207, 25, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-04', '2020-03-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (208, 26, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '1981-01-27', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (209, 26, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-02', '2020-04-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (210, 26, 'medical_problem', 'Nausea (finding)', 'SNOMED:422587007',
    '2020-03-02', '2020-04-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (211, 26, 'medical_problem', 'Vomiting symptom (finding)', 'SNOMED:249497008',
    '2020-03-02', '2020-04-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (212, 26, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-02', '2020-04-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (213, 26, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-02', '2020-04-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (214, 26, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-02', '2020-03-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (215, 26, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-02', '2020-04-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (216, 27, 'medical_problem', 'Normal pregnancy', 'SNOMED:72892002',
    '2019-06-25', '2020-01-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (217, 27, 'medical_problem', 'Anemia (disorder)', 'SNOMED:271737000',
    '2019-06-25', '2020-01-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (218, 27, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-07', '2020-04-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (219, 27, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-07', '2020-04-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (220, 27, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-07', '2020-04-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (221, 27, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-07', '2020-04-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (222, 27, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-07', '2020-03-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (223, 27, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-07', '2020-04-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (224, 28, 'medical_problem', 'Atopic dermatitis', 'SNOMED:24079001',
    '2009-09-15', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (225, 28, 'medical_problem', 'Seasonal allergic rhinitis', 'SNOMED:367498001',
    '2011-01-03', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (226, 29, 'medical_problem', 'Perennial allergic rhinitis with seasonal variation', 'SNOMED:232353008',
    '1989-09-06', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (227, 29, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '2005-10-24', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (228, 29, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2010-11-21', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (229, 29, 'medical_problem', 'Chronic intractable migraine without aura', 'SNOMED:124171000119105',
    '2013-10-30', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (230, 29, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-10', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (231, 29, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-03-10', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (232, 29, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-03-10', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (233, 29, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-10', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (234, 29, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-10', '2020-03-10', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (235, 29, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-10', '2020-03-21', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (236, 30, 'medical_problem', 'Miscarriage in first trimester', 'SNOMED:19169002',
    '1998-11-15', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (237, 30, 'medical_problem', 'Recurrent urinary tract infection', 'SNOMED:197927001',
    '1999-06-18', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (238, 30, 'medical_problem', 'Tubal pregnancy', 'SNOMED:79586000',
    '1999-11-14', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (239, 30, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2001-07-08', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (240, 30, 'medical_problem', 'Nasal congestion (finding)', 'SNOMED:68235000',
    '2020-02-24', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (241, 30, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-02-24', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (242, 30, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-02-24', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (243, 30, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-02-24', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (244, 30, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-02-24', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (245, 30, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-02-24', '2020-03-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (246, 31, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '1997-08-06', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (247, 31, 'medical_problem', 'Prediabetes', 'SNOMED:15777000',
    '2015-08-05', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (248, 32, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2015-08-12', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (249, 32, 'medical_problem', 'Prediabetes', 'SNOMED:15777000',
    '2017-08-16', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (250, 32, 'medical_problem', 'Anemia (disorder)', 'SNOMED:271737000',
    '2017-08-16', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (251, 32, 'medical_problem', 'Streptococcal sore throat (disorder)', 'SNOMED:43878008',
    '2019-08-30', '2019-09-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (252, 32, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '2019-11-09', '2019-11-23', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (253, 33, 'medical_problem', 'Chronic sinusitis (disorder)', 'SNOMED:40055000',
    '1976-06-14', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (254, 33, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '1984-01-05', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (255, 33, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-03', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (256, 33, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-03-03', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (257, 33, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-03-03', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (258, 33, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-03', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (259, 33, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-03', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (260, 33, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-03', '2020-03-03', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (261, 33, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-03', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (262, 33, 'medical_problem', 'Pneumonia (disorder)', 'SNOMED:233604007',
    '2020-03-03', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (263, 34, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2007-07-24', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (264, 34, 'medical_problem', 'Acute bronchitis (disorder)', 'SNOMED:10509002',
    '2019-11-22', '2019-11-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (265, 34, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-11', '2020-03-31', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (266, 34, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-11', '2020-03-31', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (267, 34, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-11', '2020-03-31', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (268, 34, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-11', '2020-03-11', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (269, 34, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-11', '2020-03-31', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (270, 35, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '1978-10-20', '1978-10-27', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (271, 35, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '1979-12-30', '1980-01-13', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (272, 35, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '1981-07-15', '1981-07-29', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (273, 35, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '1982-07-02', '1982-07-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (274, 35, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '1984-03-08', '1984-03-22', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (275, 35, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '1985-09-04', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (276, 35, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '1991-09-17', '1991-10-01', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (277, 35, 'medical_problem', 'Viral sinusitis (disorder)', 'SNOMED:444814009',
    '1992-12-29', '1993-01-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (278, 35, 'medical_problem', 'Prediabetes', 'SNOMED:15777000',
    '1999-11-24', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (279, 35, 'medical_problem', 'Anemia (disorder)', 'SNOMED:271737000',
    '1999-11-24', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (280, 36, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-02', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (281, 36, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-02', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (282, 36, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-02', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (283, 36, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-02', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (284, 36, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-02', '2020-03-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (285, 36, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-02', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (286, 36, 'medical_problem', 'Pneumonia (disorder)', 'SNOMED:233604007',
    '2020-03-02', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (287, 36, 'medical_problem', 'Hypoxemia (disorder)', 'SNOMED:389087006',
    '2020-03-02', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (288, 36, 'medical_problem', 'Respiratory distress (finding)', 'SNOMED:271825005',
    '2020-03-02', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (289, 36, 'medical_problem', 'Acute respiratory failure (disorder)', 'SNOMED:65710008',
    '2020-03-02', '2020-03-12', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (290, 37, 'medical_problem', 'Perennial allergic rhinitis with seasonal variation', 'SNOMED:232353008',
    '2017-08-05', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (291, 37, 'medical_problem', 'Otitis media', 'SNOMED:65363002',
    '2019-04-14', '2019-07-16', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (292, 37, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-03', '2020-03-24', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (293, 37, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-03-03', '2020-03-24', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (294, 37, 'medical_problem', 'Joint pain (finding)', 'SNOMED:57676002',
    '2020-03-03', '2020-03-24', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (295, 37, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-03', '2020-03-24', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (296, 37, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-03', '2020-03-03', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (297, 37, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-03', '2020-03-24', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (298, 37, 'medical_problem', 'Acute bronchitis (disorder)', 'SNOMED:10509002',
    '2020-03-26', '2020-04-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (299, 38, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-17', '2020-04-10', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (300, 38, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-03-17', '2020-04-10', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (301, 38, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-03-17', '2020-04-10', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (302, 38, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-17', '2020-04-10', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (303, 38, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-17', '2020-03-18', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (304, 38, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-18', '2020-04-10', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (305, 39, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-06', '2020-04-06', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (306, 39, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-06', '2020-04-06', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (307, 39, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-06', '2020-04-06', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (308, 39, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-06', '2020-03-06', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (309, 39, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-06', '2020-04-06', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (310, 40, 'medical_problem', 'Prediabetes', 'SNOMED:15777000',
    '1994-11-25', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (311, 40, 'medical_problem', 'Anemia (disorder)', 'SNOMED:271737000',
    '1994-11-25', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (312, 40, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-02', '2020-03-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (313, 40, 'medical_problem', 'Dyspnea (finding)', 'SNOMED:267036007',
    '2020-03-02', '2020-03-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (314, 40, 'medical_problem', 'Wheezing (finding)', 'SNOMED:56018004',
    '2020-03-02', '2020-03-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (315, 40, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-03-02', '2020-03-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (316, 40, 'medical_problem', 'Joint pain (finding)', 'SNOMED:57676002',
    '2020-03-02', '2020-03-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (317, 40, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-02', '2020-03-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (318, 40, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-02', '2020-03-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (319, 40, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-02', '2020-03-02', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (320, 41, 'medical_problem', 'Hypertension', 'SNOMED:59621000',
    '1997-08-06', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (321, 41, 'medical_problem', 'Osteoarthritis of knee', 'SNOMED:239873007',
    '2018-06-03', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (322, 41, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-09', '2020-04-03', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (323, 41, 'medical_problem', 'Sore throat symptom (finding)', 'SNOMED:267102003',
    '2020-03-09', '2020-04-03', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (324, 41, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-09', '2020-04-03', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (325, 41, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-09', '2020-04-03', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (326, 41, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-09', '2020-04-03', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (327, 41, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-09', '2020-03-09', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (328, 41, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-09', '2020-04-03', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (329, 42, 'medical_problem', 'Cardiac Arrest', 'SNOMED:410429000',
    '1981-09-03', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (330, 42, 'medical_problem', 'History of cardiac arrest (situation)', 'SNOMED:429007001',
    '1981-09-03', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (331, 42, 'medical_problem', 'Body mass index 30+ - obesity (finding)', 'SNOMED:162864005',
    '2010-09-23', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (332, 42, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-02-28', '2020-03-16', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (333, 42, 'medical_problem', 'Muscle pain (finding)', 'SNOMED:68962001',
    '2020-02-28', '2020-03-16', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (334, 42, 'medical_problem', 'Joint pain (finding)', 'SNOMED:57676002',
    '2020-02-28', '2020-03-16', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (335, 42, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-02-28', '2020-03-16', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (336, 42, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-02-28', '2020-03-16', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (337, 42, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-02-28', '2020-02-28', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (338, 42, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-02-28', '2020-03-16', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (339, 43, 'medical_problem', 'Cardiac Arrest', 'SNOMED:410429000',
    '1992-03-21', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (340, 43, 'medical_problem', 'History of cardiac arrest (situation)', 'SNOMED:429007001',
    '1992-03-21', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (341, 43, 'medical_problem', 'Diabetes', 'SNOMED:44054006',
    '2015-04-11', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (342, 43, 'medical_problem', 'Hypertriglyceridemia (disorder)', 'SNOMED:302870006',
    '2017-04-15', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (343, 43, 'medical_problem', 'Diabetic retinopathy associated with type II diabetes mellitus (disorder)', 'SNOMED:422034002',
    '2017-04-15', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (344, 43, 'medical_problem', 'Hyperglycemia (disorder)', 'SNOMED:80394007',
    '2018-04-21', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (345, 43, 'medical_problem', 'Metabolic syndrome X (disorder)', 'SNOMED:237602007',
    '2018-04-21', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (346, 43, 'medical_problem', 'Headache (finding)', 'SNOMED:25064002',
    '2020-03-10', '2020-03-27', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (347, 43, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-10', '2020-03-27', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (348, 43, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-10', '2020-03-27', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (349, 45, 'medical_problem', 'Drug overdose', 'SNOMED:55680006',
    '2008-04-09', NULL, 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (350, 45, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-15', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (351, 45, 'medical_problem', 'Fatigue (finding)', 'SNOMED:84229001',
    '2020-03-15', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (352, 45, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-15', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (353, 45, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-15', '2020-03-15', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (354, 45, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-15', '2020-04-07', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (355, 46, 'medical_problem', 'Cough (finding)', 'SNOMED:49727002',
    '2020-03-05', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (356, 46, 'medical_problem', 'Sore throat symptom (finding)', 'SNOMED:267102003',
    '2020-03-05', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (357, 46, 'medical_problem', 'Fever (finding)', 'SNOMED:386661006',
    '2020-03-05', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (358, 46, 'medical_problem', 'Loss of taste (finding)', 'SNOMED:36955009',
    '2020-03-05', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (359, 46, 'medical_problem', 'Suspected COVID-19', 'SNOMED:840544004',
    '2020-03-05', '2020-03-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES (360, 46, 'medical_problem', 'COVID-19', 'SNOMED:840539006',
    '2020-03-05', '2020-04-05', 1)
ON DUPLICATE KEY UPDATE title = VALUES(title);


-- Patient medications/prescriptions
-- Prescriptions table

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (1, 1, 'Amoxicillin 250 MG Oral Capsule', '308182', '2019-10-30', '2019-10-30', 0, '2019-10-30', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (2, 1, 'Acetaminophen 160 MG Chewable Tablet', '313820', '2019-10-30', '2019-10-30', 0, '2019-10-30', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (3, 2, 'Acetaminophen 160 MG Chewable Tablet', '313820', '2020-02-12', '2020-02-12', 0, '2020-02-12', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (4, 2, 'Penicillin V Potassium 250 MG Oral Tablet', '834061', '2020-04-28', '2020-04-28', 0, '2020-04-28', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (5, 3, 'amLODIPine 5 MG / Hydrochlorothiazide 12.5 MG / Olmesartan medoxomil 20 MG Oral Tablet', '999967', '2010-11-22', '2010-11-22', 0, '2010-11-22', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (6, 3, 'amLODIPine 5 MG / Hydrochlorothiazide 12.5 MG / Olmesartan medoxomil 20 MG Oral Tablet', '999967', '2011-08-30', '2011-08-30', 0, '2011-08-30', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (7, 3, 'amLODIPine 5 MG / Hydrochlorothiazide 12.5 MG / Olmesartan medoxomil 20 MG Oral Tablet', '999967', '2012-09-04', '2012-09-04', 0, '2012-09-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (8, 3, 'amLODIPine 5 MG / Hydrochlorothiazide 12.5 MG / Olmesartan medoxomil 20 MG Oral Tablet', '999967', '2013-09-10', '2013-09-10', 0, '2013-09-10', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (9, 3, 'amLODIPine 5 MG / Hydrochlorothiazide 12.5 MG / Olmesartan medoxomil 20 MG Oral Tablet', '999967', '2014-09-16', '2014-09-16', 0, '2014-09-16', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (10, 4, 'Jolivette 28 Day Pack', '757594', '2019-12-26', '2019-12-26', 1, '2019-12-26', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (11, 6, '0.4 ML Enoxaparin sodium 100 MG/ML Prefilled Syringe', '854235', '2020-02-19', '2020-02-19', 1, '2020-02-19', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (12, 6, 'NDA020503 200 ACTUAT Albuterol 0.09 MG/ACTUAT Metered Dose Inhaler', '2123111', '2020-02-19', '2020-02-19', 1, '2020-02-19', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (13, 6, 'Acetaminophen 500 MG Oral Tablet', '198440', '2020-02-19', '2020-02-19', 1, '2020-02-19', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (14, 6, '1 ML Enoxaparin sodium 150 MG/ML Prefilled Syringe', '854252', '2020-02-25', '2020-02-25', 1, '2020-02-25', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (15, 8, 'Meperidine Hydrochloride 50 MG Oral Tablet', '861467', '2019-09-13', '2019-09-13', 0, '2019-09-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (16, 8, 'Acetaminophen 325 MG Oral Tablet', '313782', '2019-09-13', '2019-09-13', 0, '2019-09-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (17, 11, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1996-08-17', '1996-08-17', 0, '1996-08-17', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (18, 11, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1997-08-23', '1997-08-23', 0, '1997-08-23', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (19, 11, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1998-08-29', '1998-08-29', 0, '1998-08-29', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (20, 11, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1999-09-04', '1999-09-04', 0, '1999-09-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (21, 11, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '2000-09-09', '2000-09-09', 0, '2000-09-09', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (22, 13, 'Chlorpheniramine Maleate 2 MG/ML Oral Solution', '477045', '1983-01-22', '1983-01-22', 1, '1983-01-22', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (23, 13, 'Hydrochlorothiazide 12.5 MG', '429503', '2000-11-22', '2000-11-22', 0, '2000-11-22', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (24, 13, 'Hydrochlorothiazide 12.5 MG', '429503', '2001-11-28', '2001-11-28', 0, '2001-11-28', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (25, 13, 'Hydrochlorothiazide 12.5 MG', '429503', '2002-12-04', '2002-12-04', 0, '2002-12-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (26, 13, 'Hydrochlorothiazide 12.5 MG', '429503', '2003-12-10', '2003-12-10', 0, '2003-12-10', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (27, 14, 'Clopidogrel 75 MG Oral Tablet', '309362', '2017-10-13', '2017-10-13', 0, '2017-10-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (28, 14, 'Simvastatin 20 MG Oral Tablet', '312961', '2017-10-13', '2017-10-13', 0, '2017-10-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (29, 14, 'Amlodipine 5 MG Oral Tablet', '197361', '2017-10-13', '2017-10-13', 0, '2017-10-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (30, 14, 'Nitroglycerin 0.4 MG/ACTUAT Mucosal Spray', '705129', '2017-10-13', '2017-10-13', 0, '2017-10-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (31, 14, 'Clopidogrel 75 MG Oral Tablet', '309362', '2017-10-13', '2017-10-13', 0, '2017-10-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (32, 15, 'Fexofenadine hydrochloride 30 MG Oral Tablet', '997488', '2002-02-24', '2002-02-24', 1, '2002-02-24', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (33, 15, 'NDA020800 0.3 ML Epinephrine 1 MG/ML Auto-Injector', '1870230', '2002-02-24', '2002-02-24', 1, '2002-02-24', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (34, 15, '120 ACTUAT Fluticasone propionate 0.044 MG/ACTUAT Metered Dose Inhaler', '895994', '2004-12-25', '2004-12-25', 0, '2004-12-25', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (35, 15, 'NDA020503 200 ACTUAT Albuterol 0.09 MG/ACTUAT Metered Dose Inhaler', '2123111', '2004-12-25', '2004-12-25', 0, '2004-12-25', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (36, 15, '120 ACTUAT Fluticasone propionate 0.044 MG/ACTUAT Metered Dose Inhaler', '895994', '2005-11-29', '2005-11-29', 0, '2005-11-29', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (37, 18, 'Camila 28 Day Pack', '748962', '2018-08-18', '2018-08-18', 0, '2018-08-18', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (38, 18, '1 ML medroxyPROGESTERone acetate 150 MG/ML Injection', '1000126', '2019-08-13', '2019-08-13', 1, '2019-08-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (39, 19, 'diphenhydrAMINE Hydrochloride 25 MG Oral Tablet', '1049630', '1972-07-03', '1972-07-03', 1, '1972-07-03', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (40, 19, 'Mirena 52 MG Intrauterine System', '807283', '2006-05-20', '2006-05-20', 0, '2006-05-20', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (41, 19, 'Mirena 52 MG Intrauterine System', '807283', '2013-04-20', '2013-04-20', 0, '2013-04-20', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (42, 19, 'Etonogestrel 68 MG Drug Implant', '389221', '2019-04-05', '2019-04-05', 0, '2019-04-05', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (43, 19, 'Mirena 52 MG Intrauterine System', '807283', '2020-03-30', '2020-03-30', 1, '2020-03-30', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (44, 20, 'Loratadine 5 MG Chewable Tablet', '665078', '2018-08-26', '2018-08-26', 1, '2018-08-26', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (45, 20, 'NDA020800 0.3 ML Epinephrine 1 MG/ML Auto-Injector', '1870230', '2018-08-26', '2018-08-26', 1, '2018-08-26', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (46, 20, '120 ACTUAT Fluticasone propionate 0.044 MG/ACTUAT Metered Dose Inhaler', '895994', '2020-03-29', '2020-03-29', 1, '2020-03-29', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (47, 20, 'NDA020503 200 ACTUAT Albuterol 0.09 MG/ACTUAT Metered Dose Inhaler', '2123111', '2020-03-29', '2020-03-29', 1, '2020-03-29', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (48, 21, 'Naproxen sodium 220 MG Oral Tablet', '849574', '2006-06-11', '2006-06-11', 1, '2006-06-11', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (49, 21, '0.4 ML Enoxaparin sodium 100 MG/ML Prefilled Syringe', '854235', '2020-03-14', '2020-03-14', 1, '2020-03-14', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (50, 21, 'Acetaminophen 500 MG Oral Tablet', '198440', '2020-03-14', '2020-03-14', 1, '2020-03-14', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (51, 22, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1976-07-02', '1976-07-02', 0, '1976-07-02', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (52, 22, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1977-07-08', '1977-07-08', 0, '1977-07-08', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (53, 22, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1978-07-14', '1978-07-14', 0, '1978-07-14', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (54, 22, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1979-07-20', '1979-07-20', 0, '1979-07-20', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (55, 22, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1980-07-25', '1980-07-25', 0, '1980-07-25', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (56, 23, 'Hydrochlorothiazide 12.5 MG', '429503', '2004-04-20', '2004-04-20', 0, '2004-04-20', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (57, 23, 'Hydrochlorothiazide 12.5 MG', '429503', '2005-04-26', '2005-04-26', 0, '2005-04-26', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (58, 23, 'Hydrochlorothiazide 12.5 MG', '429503', '2006-05-02', '2006-05-02', 0, '2006-05-02', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (59, 23, 'Hydrochlorothiazide 12.5 MG', '429503', '2007-05-08', '2007-05-08', 0, '2007-05-08', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (60, 23, 'Hydrochlorothiazide 12.5 MG', '429503', '2008-05-13', '2008-05-13', 0, '2008-05-13', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (61, 25, 'Simvastatin 10 MG Oral Tablet', '314231', '2005-05-29', '2005-05-29', 0, '2005-05-29', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (62, 25, 'Simvastatin 10 MG Oral Tablet', '314231', '2006-05-29', '2006-05-29', 0, '2006-05-29', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (63, 25, 'Simvastatin 10 MG Oral Tablet', '314231', '2007-05-29', '2007-05-29', 0, '2007-05-29', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (64, 25, 'Simvastatin 10 MG Oral Tablet', '314231', '2008-05-28', '2008-05-28', 0, '2008-05-28', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (65, 25, 'Simvastatin 10 MG Oral Tablet', '314231', '2009-05-28', '2009-05-28', 0, '2009-05-28', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (66, 26, '120 ACTUAT Fluticasone propionate 0.044 MG/ACTUAT Metered Dose Inhaler', '895994', '1975-01-25', '1975-01-25', 0, '1975-01-25', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (67, 26, 'NDA020503 200 ACTUAT Albuterol 0.09 MG/ACTUAT Metered Dose Inhaler', '2123111', '1975-01-25', '1975-01-25', 0, '1975-01-25', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (68, 26, '120 ACTUAT Fluticasone propionate 0.044 MG/ACTUAT Metered Dose Inhaler', '895994', '1975-12-30', '1975-12-30', 0, '1975-12-30', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (69, 26, 'NDA020503 200 ACTUAT Albuterol 0.09 MG/ACTUAT Metered Dose Inhaler', '2123111', '1975-12-30', '1975-12-30', 0, '1975-12-30', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (70, 26, '120 ACTUAT Fluticasone propionate 0.044 MG/ACTUAT Metered Dose Inhaler', '895994', '1977-01-04', '1977-01-04', 0, '1977-01-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (71, 28, 'cetirizine hydrochloride 5 MG Oral Tablet', '1014676', '2009-10-01', '2009-10-01', 1, '2009-10-01', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (72, 28, 'NDA020800 0.3 ML Epinephrine 1 MG/ML Auto-Injector', '1870230', '2009-10-01', '2009-10-01', 1, '2009-10-01', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (73, 29, 'Terfenadine 60 MG Oral Tablet', '141918', '1988-11-05', '1988-11-05', 1, '1988-11-05', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (74, 29, 'NDA020800 0.3 ML Epinephrine 1 MG/ML Auto-Injector', '1870230', '1988-11-05', '1988-11-05', 1, '1988-11-05', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (75, 29, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '2005-10-24', '2005-10-24', 0, '2005-10-24', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (76, 29, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '2006-10-29', '2006-10-29', 0, '2006-10-29', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (77, 29, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '2007-11-04', '2007-11-04', 0, '2007-11-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (78, 32, 'Penicillin V Potassium 500 MG Oral Tablet', '834102', '2019-08-30', '2019-08-30', 0, '2019-08-30', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (79, 32, 'Amoxicillin 250 MG / Clavulanate 125 MG Oral Tablet', '562251', '2019-11-09', '2019-11-09', 0, '2019-11-09', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (80, 33, 'Atenolol 50 MG / Chlorthalidone 25 MG Oral Tablet', '746030', '1984-02-04', '1984-02-04', 0, '1984-02-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (81, 33, 'Atenolol 50 MG / Chlorthalidone 25 MG Oral Tablet', '746030', '1985-01-10', '1985-01-10', 0, '1985-01-10', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (82, 33, 'Atenolol 50 MG / Chlorthalidone 25 MG Oral Tablet', '746030', '1986-01-16', '1986-01-16', 0, '1986-01-16', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (83, 33, 'Atenolol 50 MG / Chlorthalidone 25 MG Oral Tablet', '746030', '1987-01-22', '1987-01-22', 0, '1987-01-22', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (84, 33, 'Atenolol 50 MG / Chlorthalidone 25 MG Oral Tablet', '746030', '1988-01-28', '1988-01-28', 0, '1988-01-28', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (85, 34, 'Camila 28 Day Pack', '748962', '2019-04-28', '2019-04-28', 0, '2019-04-28', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (86, 34, 'Acetaminophen 325 MG Oral Tablet', '313782', '2019-11-22', '2019-11-22', 0, '2019-11-22', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (87, 35, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1985-09-04', '1985-09-04', 0, '1985-09-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (88, 35, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1986-09-10', '1986-09-10', 0, '1986-09-10', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (89, 35, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1987-09-16', '1987-09-16', 0, '1987-09-16', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (90, 35, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1988-09-21', '1988-09-21', 0, '1988-09-21', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (91, 35, 'Hydrochlorothiazide 25 MG Oral Tablet', '310798', '1989-09-27', '1989-09-27', 0, '1989-09-27', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (92, 36, '0.4 ML Enoxaparin sodium 100 MG/ML Prefilled Syringe', '854235', '2020-03-02', '2020-03-02', 1, '2020-03-02', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (93, 36, 'Acetaminophen 500 MG Oral Tablet', '198440', '2020-03-02', '2020-03-02', 1, '2020-03-02', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (94, 37, 'cetirizine hydrochloride 5 MG Oral Tablet', '1014676', '2015-01-04', '2015-01-04', 1, '2015-01-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (95, 37, 'NDA020800 0.3 ML Epinephrine 1 MG/ML Auto-Injector', '1870230', '2015-01-04', '2015-01-04', 1, '2015-01-04', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (96, 37, 'Acetaminophen 325 MG Oral Tablet', '313782', '2020-03-26', '2020-03-26', 0, '2020-03-26', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (97, 38, 'Seasonique 91 Day Pack', '749762', '2019-02-23', '2019-02-23', 0, '2019-02-23', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (98, 38, '1 ML medroxyprogesterone acetate 150 MG/ML Injection', '1000126', '2020-02-18', '2020-02-18', 1, '2020-02-18', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (99, 39, 'Fexofenadine hydrochloride 30 MG Oral Tablet', '997488', '2002-09-03', '2002-09-03', 1, '2002-09-03', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (100, 39, 'NDA020800 0.3 ML Epinephrine 1 MG/ML Auto-Injector', '1870230', '2002-09-03', '2002-09-03', 1, '2002-09-03', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (101, 39, 'Camila 28 Day Pack', '748962', '2019-01-05', '2019-01-05', 0, '2019-01-05', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (102, 41, 'Hydrochlorothiazide 12.5 MG', '429503', '1997-08-06', '1997-08-06', 0, '1997-08-06', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (103, 41, 'Hydrochlorothiazide 12.5 MG', '429503', '1998-04-22', '1998-04-22', 0, '1998-04-22', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (104, 41, 'Hydrochlorothiazide 12.5 MG', '429503', '1998-08-12', '1998-08-12', 0, '1998-08-12', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (105, 41, 'Hydrochlorothiazide 12.5 MG', '429503', '1999-08-18', '1999-08-18', 0, '1999-08-18', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (106, 41, 'Hydrochlorothiazide 12.5 MG', '429503', '2000-08-23', '2000-08-23', 0, '2000-08-23', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (107, 40, '0.4 ML Enoxaparin sodium 100 MG/ML Prefilled Syringe', '854235', '2020-03-02', '2020-03-02', 1, '2020-03-02', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (108, 40, 'NDA020503 200 ACTUAT Albuterol 0.09 MG/ACTUAT Metered Dose Inhaler', '2123111', '2020-03-02', '2020-03-02', 1, '2020-03-02', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (109, 40, 'Acetaminophen 500 MG Oral Tablet', '198440', '2020-03-02', '2020-03-02', 1, '2020-03-02', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (110, 40, '1 ML Enoxaparin sodium 150 MG/ML Prefilled Syringe', '854252', '2020-03-09', '2020-03-09', 1, '2020-03-09', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (111, 43, 'Hydrocortisone 10 MG/ML Topical Cream', '106258', '1995-03-26', '1995-03-26', 1, '1995-03-26', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (112, 43, 'Loratadine 10 MG Oral Tablet', '311372', '1995-04-11', '1995-04-11', 1, '1995-04-11', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (113, 43, 'NDA020800 0.3 ML Epinephrine 1 MG/ML Auto-Injector', '1870230', '1995-04-11', '1995-04-11', 1, '1995-04-11', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (114, 43, '24 HR Metformin hydrochloride 500 MG Extended Release Oral Tablet', '860975', '2017-04-15', '2017-04-15', 0, '2017-04-15', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);

INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES (115, 43, '24 HR Metformin hydrochloride 500 MG Extended Release Oral Tablet', '860975', '2017-04-15', '2017-04-15', 0, '2017-04-15', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);


-- Patient allergies
-- Lists (allergy type)

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10000, 13, 'allergy', 'Allergy to bee venom', 'SNOMED:424213003', '1983-01-22', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10001, 13, 'allergy', 'Allergy to grass pollen', 'SNOMED:418689008', '1983-01-22', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10002, 13, 'allergy', 'Allergy to tree pollen', 'SNOMED:419263009', '1983-01-22', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10003, 13, 'allergy', 'Allergy to fish', 'SNOMED:417532002', '1983-01-22', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10004, 15, 'allergy', 'Allergy to nut', 'SNOMED:91934008', '2002-02-24', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10005, 19, 'allergy', 'Allergy to mould', 'SNOMED:419474003', '1971-04-23', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10006, 19, 'allergy', 'Dander (animal) allergy', 'SNOMED:232347008', '1971-04-23', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10007, 19, 'allergy', 'Allergy to grass pollen', 'SNOMED:418689008', '1971-04-23', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10008, 19, 'allergy', 'Shellfish allergy', 'SNOMED:300913006', '1971-04-23', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10009, 20, 'allergy', 'Allergy to mould', 'SNOMED:419474003', '2018-08-26', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10010, 20, 'allergy', 'House dust mite allergy', 'SNOMED:232350006', '2018-08-26', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10011, 20, 'allergy', 'Dander (animal) allergy', 'SNOMED:232347008', '2018-08-26', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10012, 20, 'allergy', 'Allergy to grass pollen', 'SNOMED:418689008', '2018-08-26', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10013, 20, 'allergy', 'Allergy to tree pollen', 'SNOMED:419263009', '2018-08-26', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10014, 28, 'allergy', 'Latex allergy', 'SNOMED:300916003', '2009-10-01', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10015, 28, 'allergy', 'Allergy to bee venom', 'SNOMED:424213003', '2009-10-01', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10016, 28, 'allergy', 'Allergy to mould', 'SNOMED:419474003', '2009-10-01', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10017, 28, 'allergy', 'House dust mite allergy', 'SNOMED:232350006', '2009-10-01', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10018, 28, 'allergy', 'Dander (animal) allergy', 'SNOMED:232347008', '2009-10-01', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10019, 29, 'allergy', 'Allergy to mould', 'SNOMED:419474003', '1988-11-05', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10020, 29, 'allergy', 'House dust mite allergy', 'SNOMED:232350006', '1988-11-05', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10021, 29, 'allergy', 'Dander (animal) allergy', 'SNOMED:232347008', '1988-11-05', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10022, 29, 'allergy', 'Allergy to grass pollen', 'SNOMED:418689008', '1988-11-05', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10023, 29, 'allergy', 'Allergy to tree pollen', 'SNOMED:419263009', '1988-11-05', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10024, 37, 'allergy', 'Latex allergy', 'SNOMED:300916003', '2015-01-04', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10025, 37, 'allergy', 'Allergy to bee venom', 'SNOMED:424213003', '2015-01-04', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10026, 37, 'allergy', 'Allergy to mould', 'SNOMED:419474003', '2015-01-04', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10027, 37, 'allergy', 'House dust mite allergy', 'SNOMED:232350006', '2015-01-04', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10028, 37, 'allergy', 'Dander (animal) allergy', 'SNOMED:232347008', '2015-01-04', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);

INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES (10029, 39, 'allergy', 'Allergy to fish', 'SNOMED:417532002', '2002-09-03', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);


-- Patient encounters/visits
-- form_encounter table

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (1, 1, 1, '2019-02-16', 'Otitis media', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (2, 1, 2, '2019-08-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (3, 1, 3, '2019-10-31', 'Otitis media', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (4, 1, 4, '2020-01-31', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (5, 1, 5, '2020-03-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (6, 2, 6, '2019-07-08', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (7, 2, 7, '2020-01-06', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (8, 2, 8, '2020-02-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (9, 2, 9, '2020-03-13', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (10, 2, 10, '2020-04-28', 'Streptococcal sore throat (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (11, 3, 11, '2010-08-24', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (12, 3, 12, '2010-11-22', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (13, 3, 13, '2011-08-30', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (14, 3, 14, '2012-09-04', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (15, 3, 15, '2013-09-10', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (16, 4, 16, '2019-12-27', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (17, 4, 17, '2020-02-22', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (18, 4, 18, '2020-03-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (19, 5, 19, '2020-03-03', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (20, 6, 20, '2019-06-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (21, 6, 21, '2019-07-17', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (22, 6, 22, '2019-09-18', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (23, 6, 23, '2019-11-20', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (24, 6, 24, '2020-02-19', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (25, 7, 25, '2020-01-16', 'Viral sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (26, 7, 26, '2020-02-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (27, 8, 27, '2007-08-16', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (28, 8, 28, '2014-08-28', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (29, 8, 29, '2019-09-13', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (30, 8, 30, '2019-12-12', 'Fracture of clavicle', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (31, 8, 31, '2020-03-07', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (32, 9, 32, '1995-04-11', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (33, 9, 33, '2011-09-28', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (34, 9, 34, '2012-04-25', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (35, 9, 35, '2019-10-09', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (36, 9, 36, '2019-12-04', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (37, 10, 37, '2017-02-05', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (38, 10, 38, '2020-02-23', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (39, 10, 39, '2020-03-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (40, 11, 40, '1996-08-17', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (41, 11, 41, '1997-08-23', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (42, 11, 42, '1998-08-29', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (43, 11, 43, '1999-09-04', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (44, 11, 44, '2000-09-09', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (45, 12, 45, '2011-09-07', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (46, 12, 46, '2015-10-21', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (47, 12, 47, '2019-02-20', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (48, 12, 48, '2019-06-12', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (49, 12, 49, '2019-07-10', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (50, 13, 50, '1983-01-22', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (51, 13, 51, '1984-10-05', 'Perennial allergic rhinitis', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (52, 13, 52, '2000-11-22', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (53, 13, 53, '2001-11-28', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (54, 13, 54, '2002-12-04', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (55, 14, 55, '1989-06-14', 'Sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (56, 14, 56, '2008-12-05', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (57, 14, 57, '2011-06-17', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (58, 14, 58, '2017-10-13', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (59, 14, 59, '2017-10-20', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (60, 15, 60, '2002-02-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (61, 15, 61, '2002-02-24', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (62, 15, 62, '2002-12-26', 'Perennial allergic rhinitis', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (63, 15, 63, '2004-12-25', 'Childhood asthma', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (64, 15, 64, '2005-11-29', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (65, 16, 65, '1962-10-26', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (66, 16, 66, '1990-06-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (67, 16, 67, '1994-06-14', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (68, 16, 68, '2012-07-09', 'Acute bacterial sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (69, 16, 69, '2019-06-04', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (70, 17, 70, '2000-08-08', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (71, 17, 71, '2003-09-08', 'Drug overdose', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (72, 17, 72, '2010-08-10', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (73, 17, 73, '2019-06-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (74, 17, 74, '2019-07-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (75, 18, 75, '2002-06-16', 'Acute bronchitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (76, 18, 76, '2016-07-06', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (77, 18, 77, '2018-08-18', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (78, 18, 78, '2019-02-11', 'Acute bronchitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (79, 18, 79, '2019-08-13', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (80, 19, 80, '1971-04-09', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (81, 19, 81, '1971-04-23', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (82, 19, 82, '1972-06-19', 'Perennial allergic rhinitis', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (83, 19, 83, '1983-04-16', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (84, 19, 84, '2001-08-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (85, 20, 85, '2018-08-16', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (86, 20, 86, '2018-08-27', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (87, 20, 87, '2019-08-30', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (88, 20, 88, '2019-09-10', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (89, 20, 89, '2020-02-28', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (90, 21, 90, '1972-12-14', 'Acute bacterial sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (91, 21, 91, '1984-11-14', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (92, 21, 92, '1990-09-05', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (93, 21, 93, '2006-06-12', 'Osteoarthritis of hip', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (94, 21, 94, '2007-06-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (95, 22, 95, '1976-07-03', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (96, 22, 96, '1977-07-09', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (97, 22, 97, '1978-07-15', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (98, 22, 98, '1979-07-21', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (99, 22, 99, '1980-07-26', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (100, 23, 100, '2004-04-20', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (101, 23, 101, '2005-04-26', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (102, 23, 102, '2005-10-11', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (103, 23, 103, '2006-05-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (104, 23, 104, '2007-05-08', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (105, 24, 105, '2017-12-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (106, 24, 106, '2020-03-05', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (107, 24, 107, '2020-05-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (108, 25, 108, '1989-04-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (109, 25, 109, '2005-05-08', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (110, 25, 110, '2005-05-29', 'Hyperlipidemia', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (111, 25, 111, '2006-05-29', 'Hyperlipidemia', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (112, 25, 112, '2007-05-29', 'Hyperlipidemia', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (113, 26, 113, '1975-01-25', 'Childhood asthma', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (114, 26, 114, '1975-12-30', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (115, 26, 115, '1977-01-04', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (116, 26, 116, '1978-01-10', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (117, 26, 117, '1979-01-16', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (118, 27, 118, '2019-06-26', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (119, 27, 119, '2019-06-26', 'Anemia (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (120, 27, 120, '2019-07-24', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (121, 27, 121, '2019-08-21', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (122, 27, 122, '2019-09-18', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (123, 28, 123, '2009-09-15', 'Atopic dermatitis', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (124, 28, 124, '2009-10-01', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (125, 28, 125, '2011-01-03', 'Seasonal allergic rhinitis', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (126, 28, 126, '2019-01-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (127, 28, 127, '2019-05-29', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (128, 29, 128, '1988-10-24', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (129, 29, 129, '1988-11-06', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (130, 29, 130, '1989-09-06', 'Perennial allergic rhinitis with seasonal variation', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (131, 29, 131, '2005-10-24', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (132, 29, 132, '2006-10-30', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (133, 30, 133, '1998-11-16', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (134, 30, 134, '1999-06-19', 'Escherichia coli urinary tract infection', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (135, 30, 135, '1999-11-15', 'Normal pregnancy', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (136, 30, 136, '2001-07-09', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (137, 30, 137, '2020-02-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (138, 31, 138, '1997-08-03', 'Acute viral pharyngitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (139, 31, 139, '2015-08-06', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (140, 31, 140, '2019-07-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (141, 32, 141, '1973-12-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (142, 32, 142, '2015-08-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (143, 32, 143, '2017-08-16', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (144, 32, 144, '2019-08-21', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (145, 32, 145, '2019-08-30', 'Streptococcal sore throat (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (146, 33, 146, '1976-06-15', 'Acute bacterial sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (147, 33, 147, '1984-01-06', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (148, 33, 148, '1984-02-05', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (149, 33, 149, '1985-01-11', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (150, 33, 150, '1986-01-17', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (151, 34, 151, '2001-11-19', 'Acute bronchitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (152, 34, 152, '2006-01-06', 'Acute bronchitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (153, 34, 153, '2007-07-24', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (154, 34, 154, '2010-06-29', 'Acute bronchitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (155, 34, 155, '2019-04-28', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (156, 35, 156, '1978-10-20', 'Viral sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (157, 35, 157, '1979-12-30', 'Viral sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (158, 35, 158, '1981-07-15', 'Viral sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (159, 35, 159, '1982-07-02', 'Viral sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (160, 35, 160, '1984-03-08', 'Viral sinusitis (disorder)', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (161, 36, 161, '2019-07-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (162, 36, 162, '2019-10-24', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (163, 36, 163, '2020-01-23', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (164, 36, 164, '2020-03-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (165, 36, 165, '2020-03-02', 'COVID-19', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (166, 37, 166, '2014-12-22', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (167, 37, 167, '2015-01-04', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (168, 37, 168, '2017-08-05', 'Perennial allergic rhinitis with seasonal variation', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (169, 37, 169, '2019-04-14', 'Otitis media', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (170, 37, 170, '2019-07-16', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (171, 38, 171, '2019-02-24', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (172, 38, 172, '2020-02-19', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (173, 38, 173, '2020-03-18', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (174, 39, 174, '2002-08-22', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (175, 39, 175, '2002-09-03', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (176, 39, 176, '2019-01-05', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (177, 39, 177, '2020-03-06', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (178, 39, 178, '2020-03-19', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (179, 40, 179, '1994-11-25', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (180, 40, 180, '2020-03-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (181, 40, 181, '2020-03-02', 'COVID-19', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (182, 41, 182, '1997-08-06', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (183, 41, 183, '1998-04-22', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (184, 41, 184, '1998-08-12', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (185, 41, 185, '1999-08-18', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (186, 41, 186, '2000-08-23', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (187, 42, 187, '1981-09-03', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (188, 42, 188, '2010-09-23', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (189, 42, 189, '2019-09-19', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (190, 42, 190, '2020-02-28', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (191, 43, 191, '1992-03-21', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (192, 43, 192, '1995-03-26', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (193, 43, 193, '1995-04-11', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (194, 43, 194, '2015-04-11', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (195, 43, 195, '2017-04-15', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (196, 44, 196, '2020-05-24', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (197, 45, 197, '2008-04-09', 'Drug overdose', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (198, 45, 198, '2019-06-03', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (199, 45, 199, '2019-07-03', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (200, 45, 200, '2019-08-02', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (201, 45, 201, '2019-09-07', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (202, 46, 202, '2019-07-08', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);

INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES (203, 46, 203, '2020-03-05', '', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);


-- Update auto_increment for new patients
ALTER TABLE patient_data AUTO_INCREMENT = 100;

-- Create default facility if not exists
INSERT INTO facility (id, name, street, city, state, postal_code, phone, service_location, billing_location, primary_business_entity)
VALUES (3, 'Springfield Medical Center', '100 Healthcare Blvd', 'Springfield', 'MA', '01101', '555-1000', 1, 1, 1)
ON DUPLICATE KEY UPDATE name = VALUES(name);

SET FOREIGN_KEY_CHECKS = 1;

SELECT CONCAT('Loaded ', COUNT(*), ' patients with medical histories') as status FROM patient_data WHERE pid < 100;
