-- NOSH ChartingSystem Patient Data
-- Source: Synthea synthetic patient generator (Massachusetts cohort)
-- Generated: java -jar synthea-with-dependencies.jar -p 30 Massachusetts
-- 20 patients pre-loaded (PIDs 1-20); PID 21 reserved for register_new_patient task
--
-- Schema: demographics table (NOSH2)

SET FOREIGN_KEY_CHECKS=0;

INSERT IGNORE INTO `demographics` (
  `pid`, `id`, `lastname`, `firstname`, `middle`, `sex`, `DOB`,
  `address`, `city`, `state`, `zip`,
  `phone_home`, `phone_cell`, `email`,
  `race`, `ethnicity`, `language`,
  `marital_status`, `active`, `date`
) VALUES
-- 1: Conchita Hernandes
(1, 2, 'Hernandes', 'Conchita', 'M', 'f', '2006-12-04',
 '47 Washington St', 'Springfield', 'MA', '01108',
 '413-555-1001', '413-555-2001', 'conchita.hernandes@example.com',
 'White', 'Hispanic', 'English',
 'Single', 1, NOW()),

-- 2: Corine Ziemann
(2, 2, 'Ziemann', 'Corine', 'L', 'f', '2000-11-29',
 '22 Elm St', 'Chicopee', 'MA', '01020',
 '413-555-1002', '413-555-2002', 'corine.ziemann@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 3: Crysta Parisian
(3, 2, 'Parisian', 'Crysta', 'R', 'f', '2005-03-26',
 '88 Maple Ave', 'Holyoke', 'MA', '01040',
 '413-555-1003', '413-555-2003', 'crysta.parisian@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 4: Charles Nolan
(4, 2, 'Nolan', 'Charles', 'J', 'm', '2003-11-02',
 '15 Oak Rd', 'Springfield', 'MA', '01105',
 '413-555-1004', '413-555-2004', 'charles.nolan@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 5: Kent Zemlak
(5, 2, 'Zemlak', 'Kent', 'A', 'm', '2001-02-16',
 '321 Pine St', 'Ludlow', 'MA', '01056',
 '413-555-1005', '413-555-2005', 'kent.zemlak@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 6: Dwight Dach
(6, 2, 'Dach', 'Dwight', 'B', 'm', '1998-03-21',
 '76 Forest Dr', 'West Springfield', 'MA', '01089',
 '413-555-1006', '413-555-2006', 'dwight.dach@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 7: Ezequiel Hermiston
(7, 2, 'Hermiston', 'Ezequiel', 'C', 'm', '2002-05-19',
 '150 Willow Lane', 'Longmeadow', 'MA', '01106',
 '413-555-1007', '413-555-2007', 'ezequiel.hermiston@example.com',
 'White', 'Hispanic', 'English',
 'Single', 1, NOW()),

-- 8: Denny Lubowitz
(8, 2, 'Lubowitz', 'Denny', 'S', 'f', '2000-07-04',
 '44 Cedar Blvd', 'Agawam', 'MA', '01001',
 '413-555-1008', '413-555-2008', 'denny.lubowitz@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 9: Kelle Crist
(9, 2, 'Crist', 'Kelle', 'D', 'f', '2002-10-18',
 '200 Birch St', 'East Longmeadow', 'MA', '01028',
 '413-555-1009', '413-555-2009', 'kelle.crist@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 10: Sherill Botsford
(10, 2, 'Botsford', 'Sherill', 'T', 'f', '1995-01-24',
 '55 Highland Ave', 'Westfield', 'MA', '01085',
 '413-555-1010', '413-555-2010', 'sherill.botsford@example.com',
 'White', 'NonHispanic', 'English',
 'Married', 1, NOW()),

-- 11: Hobert Wuckert - used for add_medication task
(11, 2, 'Wuckert', 'Hobert', 'G', 'm', '2000-10-27',
 '17 Laurel St', 'Palmer', 'MA', '01069',
 '413-555-1011', '413-555-2011', 'hobert.wuckert@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 12: Malka Hartmann - used for add_immunization task
(12, 2, 'Hartmann', 'Malka', 'R', 'f', '1994-11-26',
 '38 Spruce Ave', 'Northampton', 'MA', '01060',
 '413-555-1012', '413-555-2012', 'malka.hartmann@example.com',
 'White', 'NonHispanic', 'English',
 'Single', 1, NOW()),

-- 13: Cordie King
(13, 2, 'King', 'Cordie', 'M', 'f', '1995-03-11',
 '90 Locust Dr', 'Springfield', 'MA', '01109',
 '413-555-1013', '413-555-2013', 'cordie.king@example.com',
 'Black', 'NonHispanic', 'English',
 'Married', 1, NOW()),

-- 14: Coreen Treutel - used for schedule_appointment task
(14, 2, 'Treutel', 'Coreen', 'A', 'f', '1990-07-20',
 '12 Chestnut St', 'Pittsfield', 'MA', '01201',
 '413-555-1014', '413-555-2014', 'coreen.treutel@example.com',
 'White', 'NonHispanic', 'English',
 'Divorced', 1, NOW()),

-- 15: Tracey Crona - used for document_vitals task
(15, 2, 'Crona', 'Tracey', 'B', 'm', '1981-07-02',
 '250 Poplar Rd', 'Amherst', 'MA', '01002',
 '413-555-1015', '413-555-2015', 'tracey.crona@example.com',
 'White', 'NonHispanic', 'English',
 'Married', 1, NOW()),

-- 16: Myrtis Armstrong - used for add_allergy task
(16, 2, 'Armstrong', 'Myrtis', 'J', 'f', '1985-04-08',
 '85 Magnolia Ct', 'Belchertown', 'MA', '01007',
 '413-555-1016', '413-555-2016', 'myrtis.armstrong@example.com',
 'White', 'NonHispanic', 'English',
 'Married', 1, NOW()),

-- 17: Arlie McClure - used for add_medical_problem task
(17, 2, 'McClure', 'Arlie', 'H', 'm', '1971-03-06',
 '33 Hickory Ln', 'Easthampton', 'MA', '01027',
 '413-555-1017', '413-555-2017', 'arlie.mcclure@example.com',
 'White', 'NonHispanic', 'English',
 'Married', 1, NOW()),

-- 18: Crystal Schroeder - used for create_encounter task
(18, 2, 'Schroeder', 'Crystal', 'M', 'f', '1972-07-19',
 '4 Walnut Ave', 'Ware', 'MA', '01082',
 '413-555-1018', '413-555-2018', 'crystal.schroeder@example.com',
 'White', 'NonHispanic', 'English',
 'Married', 1, NOW()),

-- 19: Luann Sanford - used for update_demographics task
(19, 2, 'Sanford', 'Luann', 'K', 'f', '1977-03-26',
 '71 Ash St', 'Greenfield', 'MA', '01301',
 '413-555-1019', '413-555-2019', 'luann.sanford.old@example.com',
 'White', 'NonHispanic', 'English',
 'Divorced', 1, NOW()),

-- 20: Horacio Santacruz - used for add_provider task (has existing encounter)
(20, 2, 'Santacruz', 'Horacio', 'F', 'm', '1954-02-19',
 '110 Sunset Blvd', 'Chicopee', 'MA', '01013',
 '413-555-1020', '413-555-2020', 'horacio.santacruz@example.com',
 'Hispanic', 'Hispanic', 'Spanish',
 'Married', 1, NOW());

-- Set up patient-to-user relationships (required for NOSH access control)
INSERT IGNORE INTO `demographics_relate` (`pid`, `id`, `practice_id`)
SELECT pid, 2, 1 FROM demographics WHERE pid BETWEEN 1 AND 20;

SET FOREIGN_KEY_CHECKS=1;
