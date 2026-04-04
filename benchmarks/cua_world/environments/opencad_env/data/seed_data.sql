-- OpenCAD Seed Data
-- Uses the official OpenCAD schema column names discovered from oc_install.sql
-- Users are NOT inserted here; they are created via PHP registration for proper
-- bcrypt password hashing (see setup_opencad.sh).

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;

-- --------------------------------------------------------
-- NCIC Names (person records / driver licenses)
-- Official schema: single `name` field (not first_name/last_name),
--   submittedByName, submittedById, set-type columns for gender/race/dl_status
-- --------------------------------------------------------
INSERT INTO `ncic_names` (`id`, `submittedByName`, `submittedById`, `name`, `dob`, `address`, `gender`, `race`, `dl_status`, `hair_color`, `build`, `weapon_permit`, `deceased`)
VALUES
(1, 'Admin User', '1A-01', 'Michael De Santa', '1965-08-09', '2112 Portola Drive, Rockford Hills', 'Male', 'Caucasian', 'Valid', 'Brown', 'Average', 'Vaild', 'NO'),
(2, 'Admin User', '1A-01', 'Franklin Clinton', '1988-06-11', '3671 Whispymound Drive, Vinewood Hills', 'Male', 'Black or African American', 'Valid', 'Black', 'Fit', 'Unobtained', 'NO'),
(3, 'Admin User', '1A-01', 'Trevor Philips', '1968-11-14', 'Zancudo Avenue, Sandy Shores', 'Male', 'Caucasian', 'Suspended', 'Brown', 'Average', 'Vaild', 'NO'),
(4, 'Admin User', '1A-01', 'Amanda De Santa', '1970-03-22', '2112 Portola Drive, Rockford Hills', 'Female', 'Caucasian', 'Valid', 'Brown', 'Average', 'Unobtained', 'NO');

-- --------------------------------------------------------
-- Civilian name links (junction table: user_id -> names_id)
-- These link user accounts to their NCIC civilian identities.
-- user_id 2 = admin user (created by setup_opencad.sh via PHP; ID 1 is the placeholder from oc_install.sql)
-- names_id = ncic_names.id above
-- --------------------------------------------------------
INSERT INTO `civilian_names` (`user_id`, `names_id`)
VALUES
(2, 1),
(2, 2),
(2, 3),
(2, 4);

-- --------------------------------------------------------
-- NCIC Plates (vehicle registrations)
-- Official schema: veh_pcolor/veh_scolor (not veh_color),
--   veh_insurance_type, flags (not veh_flags)
-- --------------------------------------------------------
INSERT INTO `ncic_plates` (`id`, `name_id`, `veh_plate`, `veh_make`, `veh_model`, `veh_pcolor`, `veh_scolor`, `veh_insurance`, `veh_insurance_type`, `flags`, `veh_reg_state`, `notes`, `user_id`)
VALUES
(1, 1, '59CKR315', 'Obey', 'Tailgater', 'Silver', 'Silver', 'VALID', 'Comprehensive', 'NONE', 'Los Santos', 'Registered to Michael De Santa', 2),
(2, 2, '63JIG803', 'Bravado', 'Buffalo', 'Green', 'Black', 'VALID', 'Comprehensive', 'NONE', 'Los Santos', 'Registered to Franklin Clinton', 2),
(3, 3, '42BRK991', 'Canis', 'Bodhi', 'Brown', 'Brown', 'EXPIRED', 'CTP', 'INSURANCE FLAG', 'Blaine County', 'Registered to Trevor Philips - insurance expired', 2),
(4, 4, '88QEN547', 'Benefactor', 'Feltzer', 'Red', 'Red', 'VALID', 'Comprehensive', 'NONE', 'Los Santos', 'Registered to Amanda De Santa', 2);

-- --------------------------------------------------------
-- NCIC Warrants for Trevor Philips (name_id = 3)
-- Official schema: expiration_date, warrant_name, issuing_agency,
--   name_id, issued_date, status
-- --------------------------------------------------------
INSERT INTO `ncic_warrants` (`id`, `expiration_date`, `warrant_name`, `issuing_agency`, `name_id`, `issued_date`, `status`)
VALUES
(1, '2026-12-31', 'Assault with a Deadly Weapon', 'Blaine County Sheriff Office', 3, '2024-06-15', 'Active'),
(2, '2026-12-31', 'Reckless Endangerment', 'San Andreas Highway Patrol', 3, '2024-08-22', 'Active');

-- --------------------------------------------------------
-- NCIC Citations
-- Official schema: status, name_id, citation_name, citation_fine,
--   issued_date, issued_by
-- --------------------------------------------------------
INSERT INTO `ncic_citations` (`id`, `status`, `name_id`, `citation_name`, `citation_fine`, `issued_date`, `issued_by`)
VALUES
(1, 'Active', 3, 'Speeding', '250.00', '2024-07-10', 'Officer Davis - SAHP');

-- --------------------------------------------------------
-- Historical call records (call_history)
-- Official schema: call_id, call_type, call_primary, call_street1,
--   call_street2, call_street3, call_narrative
-- Using explicit call_id values for stable references
-- --------------------------------------------------------
INSERT INTO `call_history` (`call_id`, `call_type`, `call_primary`, `call_street1`, `call_street2`, `call_street3`, `call_narrative`)
VALUES
(1, '10-52', 'Medical Emergency - Pedestrian struck', 'Vinewood Boulevard', 'Hawick Avenue', NULL, 'Pedestrian struck by vehicle at intersection. Minor injuries reported. Traffic backed up eastbound. Units 1A-1 and 2B-7 responded.'),
(2, '10-31', 'Armed Robbery in Progress', 'Forum Drive', 'Strawberry Avenue', NULL, 'Suspect with handgun robbing 24/7 convenience store. Two employees inside. Suspect fled on foot southbound.'),
(3, '10-16', 'Domestic Disturbance', 'Grove Street', NULL, NULL, 'Neighbors report loud argument and sounds of breaking glass at residence. Parties separated on arrival.'),
(4, '10-70', 'Structure Fire', 'El Rancho Boulevard', 'Jamestown Street', NULL, 'Two-story residential structure fully involved. All occupants evacuated. LSFD Engine 7 on scene.'),
(5, '10-52', 'Medical Emergency', 'Del Perro Boulevard', NULL, NULL, 'Male subject collapsed on sidewalk, possible cardiac event. Bystanders performing CPR. EMS dispatched Code 3.');

-- --------------------------------------------------------
-- BOLOs - Vehicles
-- Official schema: vehicle_make, vehicle_model, vehicle_plate,
--   primary_color, secondary_color, reason_wanted, last_seen
-- --------------------------------------------------------
INSERT INTO `bolos_vehicles` (`id`, `vehicle_make`, `vehicle_model`, `vehicle_plate`, `primary_color`, `secondary_color`, `reason_wanted`, `last_seen`)
VALUES
(1, 'Vapid', 'Stanier', 'UNK-PLT', 'White', 'White', 'Suspect vehicle in 10-31 armed robbery on Forum Drive. Driver fled scene at high speed.', 'Forum Drive / Strawberry Avenue');

-- --------------------------------------------------------
-- BOLOs - Persons
-- Official schema: first_name, last_name, gender,
--   physical_description, reason_wanted, last_seen
-- --------------------------------------------------------
INSERT INTO `bolos_persons` (`id`, `first_name`, `last_name`, `gender`, `physical_description`, `reason_wanted`, `last_seen`)
VALUES
(1, 'Unknown', 'Male', 'Male', 'White male, approx 30-40, medium build, wearing black hoodie and jeans', 'Suspect in armed robbery of 24/7 store on Forum Drive. Armed with handgun.', 'Forum Drive / Strawberry Avenue, fled on foot southbound');

COMMIT;
