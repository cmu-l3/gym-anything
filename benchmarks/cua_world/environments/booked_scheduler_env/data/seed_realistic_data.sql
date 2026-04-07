-- Booked Scheduler: Realistic seed data for a mid-size corporate office
-- Extends the default sample data with realistic resources, users, and reservations
-- Data modeled after a real corporate campus with multiple buildings

SET foreign_key_checks = 0;

-- ============================================================
-- ADDITIONAL RESOURCES (conference rooms, equipment, vehicles)
-- The default sample data has resource_id 1 and 2 (Conference Room 1 & 2)
-- We add resources starting from id 3
-- ============================================================

INSERT INTO resources (resource_id, name, location, contact_info, description, notes, autoassign, requires_approval, allow_multiday_reservations, max_participants, schedule_id) VALUES
(3, 'Executive Board Room', 'Building A, Floor 3', 'facilities@acmecorp.com', 'Large board room with 65-inch display, video conferencing, and whiteboard wall. Seats 20.', 'Requires approval for non-executive bookings. AV tech on call ext 4501.', 1, 1, 1, 20, 1),
(4, 'Innovation Lab', 'Building B, Floor 1', 'labs@acmecorp.com', 'Open workspace with standing desks, prototyping equipment, and 3D printer access.', 'Clean up after use. 3D printer filament requests via ServiceNow ticket.', 1, 0, 1, 12, 1),
(5, 'Training Room Alpha', 'Building A, Floor 2', 'training@acmecorp.com', '30-seat classroom with projector, podium, and recording equipment for webinars.', 'Catering orders must be placed 48 hours in advance via cafeteria portal.', 1, 0, 1, 30, 1),
(6, 'Quiet Focus Room 201', 'Building A, Floor 2', NULL, 'Single-occupant soundproof room for focused work or private calls.', 'Max booking 4 hours per day per person.', 1, 0, 0, 1, 1),
(7, 'Quiet Focus Room 202', 'Building A, Floor 2', NULL, 'Single-occupant soundproof room for focused work or private calls.', 'Max booking 4 hours per day per person.', 1, 0, 0, 1, 1),
(8, 'Video Conference Suite', 'Building A, Floor 3', 'av-support@acmecorp.com', 'Dedicated video conferencing room with Poly Studio X70 and dual 55-inch displays.', 'Polycom bridge auto-connects. Dial 8800 for AV help.', 1, 0, 0, 8, 1),
(9, 'Outdoor Patio Meeting Area', 'Campus Garden, West Side', 'facilities@acmecorp.com', 'Weather-permitting outdoor meeting space with shade structure and power outlets.', 'Check weather forecast. Rain backup: Conference Room 1.', 1, 0, 0, 15, 1),
(10, 'Company Van - Ford Transit', 'Parking Garage B, Spot V1', 'fleet@acmecorp.com', '2023 Ford Transit 12-passenger van for team outings and client site visits.', 'Return with full tank. Log mileage in glove box binder. Keys at reception.', 1, 1, 1, 12, 1),
(11, 'Portable Projector (Epson EB-U42)', 'IT Storage Room 105', 'it-helpdesk@acmecorp.com', 'Epson EB-U42 portable projector with HDMI cable and carry case.', 'Return to IT Storage Room 105 by 6 PM on last day of booking.', 1, 0, 1, NULL, 1),
(12, 'Photography Studio', 'Building C, Basement', 'marketing@acmecorp.com', 'Professional photography studio with lighting rigs, backdrops, and tethered capture setup.', 'Studio orientation required for first-time users. Contact marketing@acmecorp.com.', 1, 1, 0, 5, 1);

-- ============================================================
-- ADDITIONAL USERS (realistic names from various departments)
-- Default sample data has user_id 1 (User) and 2 (Admin)
-- Password hash for all: "password" with salt "3b3dbb9b"
-- (same hash as default sample user)
-- ============================================================

INSERT INTO users (fname, lname, email, username, password, salt, timezone, lastlogin, status_id, date_created, language, organization, phone, position) VALUES
('Maria', 'Gonzalez', 'maria.gonzalez@acmecorp.com', 'mgonzalez', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0103', 'VP of Engineering'),
('James', 'O''Brien', 'james.obrien@acmecorp.com', 'jobrien', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0104', 'Senior Software Engineer'),
('Priya', 'Patel', 'priya.patel@acmecorp.com', 'ppatel', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0105', 'Product Manager'),
('Wei', 'Chen', 'wei.chen@acmecorp.com', 'wchen', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0106', 'UX Designer'),
('Fatima', 'Al-Hassan', 'fatima.alhassan@acmecorp.com', 'falhassan', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0107', 'HR Business Partner'),
('Marcus', 'Williams', 'marcus.williams@acmecorp.com', 'mwilliams', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0108', 'Finance Analyst'),
('Elena', 'Petrov', 'elena.petrov@acmecorp.com', 'epetrov', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0109', 'Marketing Director'),
('Kenji', 'Tanaka', 'kenji.tanaka@acmecorp.com', 'ktanaka', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0110', 'DevOps Engineer'),
('Aisha', 'Mohammed', 'aisha.mohammed@acmecorp.com', 'amohammed', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0111', 'Legal Counsel'),
('Carlos', 'Rivera', 'carlos.rivera@acmecorp.com', 'crivera', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0112', 'Facilities Manager'),
('Sarah', 'Kim', 'sarah.kim@acmecorp.com', 'skim', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0113', 'Data Scientist'),
('Thomas', 'Andersen', 'thomas.andersen@acmecorp.com', 'tandersen', '7b6aec38ff9b7650d64d0374194307bdde711425', '3b3dbb9b', 'America/New_York', NULL, 1, NOW(), 'en_us', 'ACME Corp', '555-0114', 'IT Support Specialist');

-- Grant all new users permission to all resources
INSERT IGNORE INTO user_resource_permissions (user_id, resource_id, permission_id)
SELECT u.user_id, r.resource_id, 1
FROM users u, resources r
WHERE u.user_id > 2;

-- ============================================================
-- ACCESSORIES (realistic meeting supplies and equipment)
-- Default sample has accessory_id 1,2,3
-- ============================================================

INSERT INTO accessories (accessory_id, accessory_name, accessory_quantity) VALUES
(4, 'Wireless Presentation Clicker', 5),
(5, 'Whiteboard Marker Set (8 colors)', 10),
(6, 'USB-C to HDMI Adapter', 8),
(7, 'Webcam (Logitech C920)', 4),
(8, 'Conference Phone (Poly Trio)', 3),
(9, 'Catering - Coffee Service (12 cups)', NULL),
(10, 'Catering - Lunch Box Set (per person)', NULL);

-- ============================================================
-- RESERVATION SERIES & INSTANCES (realistic bookings)
-- Schema: reservation_series(series_id, date_created, last_modified, title, description,
--   allow_participation, allow_anon_participation, type_id, status_id, repeat_type,
--   repeat_options, owner_id, terms_date_accepted)
-- reservation_resources(series_id, resource_id, resource_level_id)
-- reservation_users(reservation_instance_id, user_id, reservation_user_level)
-- ============================================================

-- Series 1: Engineering Daily Standup
INSERT INTO reservation_series (series_id, date_created, last_modified, title, description, allow_participation, allow_anon_participation, type_id, status_id, repeat_type, repeat_options, owner_id, terms_date_accepted) VALUES
(1, NOW(), NOW(), 'Engineering Daily Standup', 'Daily standup for the platform engineering team. Discuss blockers, progress, and sprint goals.', 1, 0, 1, 1, 'none', NULL, 4, NOW());

INSERT INTO reservation_instances (series_id, reference_number, start_date, end_date) VALUES
(1, 'ref-eng-standup-001', DATE_ADD(CURDATE(), INTERVAL 1 DAY) + INTERVAL 9 HOUR, DATE_ADD(CURDATE(), INTERVAL 1 DAY) + INTERVAL 9 HOUR + INTERVAL 30 MINUTE),
(1, 'ref-eng-standup-002', DATE_ADD(CURDATE(), INTERVAL 2 DAY) + INTERVAL 9 HOUR, DATE_ADD(CURDATE(), INTERVAL 2 DAY) + INTERVAL 9 HOUR + INTERVAL 30 MINUTE);

INSERT INTO reservation_resources (series_id, resource_id, resource_level_id) VALUES (1, 1, 1);

SET @ri1a = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-eng-standup-001');
SET @ri1b = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-eng-standup-002');
INSERT INTO reservation_users (reservation_instance_id, user_id, reservation_user_level) VALUES (@ri1a, 4, 1), (@ri1b, 4, 1);

-- Series 2: Board Strategy Meeting
INSERT INTO reservation_series (series_id, date_created, last_modified, title, description, allow_participation, allow_anon_participation, type_id, status_id, repeat_type, repeat_options, owner_id, terms_date_accepted) VALUES
(2, NOW(), NOW(), 'Q2 Strategic Planning Session', 'Executive leadership quarterly strategy review. Agenda: market analysis, product roadmap, and budget review.', 0, 0, 1, 1, 'none', NULL, 3, NOW());

INSERT INTO reservation_instances (series_id, reference_number, start_date, end_date) VALUES
(2, 'ref-q2-strategy-001', DATE_ADD(CURDATE(), INTERVAL 3 DAY) + INTERVAL 10 HOUR, DATE_ADD(CURDATE(), INTERVAL 3 DAY) + INTERVAL 12 HOUR);

INSERT INTO reservation_resources (series_id, resource_id, resource_level_id) VALUES (2, 3, 1);

SET @ri2 = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-q2-strategy-001');
INSERT INTO reservation_users (reservation_instance_id, user_id, reservation_user_level) VALUES (@ri2, 3, 1);

-- Series 3: UX Design Review
INSERT INTO reservation_series (series_id, date_created, last_modified, title, description, allow_participation, allow_anon_participation, type_id, status_id, repeat_type, repeat_options, owner_id, terms_date_accepted) VALUES
(3, NOW(), NOW(), 'Mobile App UX Design Review', 'Review mockups and user testing results for the mobile app redesign project.', 1, 0, 1, 1, 'none', NULL, 6, NOW());

INSERT INTO reservation_instances (series_id, reference_number, start_date, end_date) VALUES
(3, 'ref-ux-review-001', DATE_ADD(CURDATE(), INTERVAL 1 DAY) + INTERVAL 14 HOUR, DATE_ADD(CURDATE(), INTERVAL 1 DAY) + INTERVAL 15 HOUR + INTERVAL 30 MINUTE);

INSERT INTO reservation_resources (series_id, resource_id, resource_level_id) VALUES (3, 4, 1);

SET @ri3 = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-ux-review-001');
INSERT INTO reservation_users (reservation_instance_id, user_id, reservation_user_level) VALUES (@ri3, 6, 1);

-- Series 4: HR Onboarding Training
INSERT INTO reservation_series (series_id, date_created, last_modified, title, description, allow_participation, allow_anon_participation, type_id, status_id, repeat_type, repeat_options, owner_id, terms_date_accepted) VALUES
(4, NOW(), NOW(), 'New Employee Orientation - April Cohort', 'Full-day orientation for new hires. Covers company policies, benefits enrollment, and IT setup.', 0, 0, 1, 1, 'none', NULL, 7, NOW());

INSERT INTO reservation_instances (series_id, reference_number, start_date, end_date) VALUES
(4, 'ref-hr-onboard-001', DATE_ADD(CURDATE(), INTERVAL 5 DAY) + INTERVAL 9 HOUR, DATE_ADD(CURDATE(), INTERVAL 5 DAY) + INTERVAL 17 HOUR);

INSERT INTO reservation_resources (series_id, resource_id, resource_level_id) VALUES (4, 5, 1);

SET @ri4 = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-hr-onboard-001');
INSERT INTO reservation_users (reservation_instance_id, user_id, reservation_user_level) VALUES (@ri4, 7, 1);

-- Series 5: Client Demo
INSERT INTO reservation_series (series_id, date_created, last_modified, title, description, allow_participation, allow_anon_participation, type_id, status_id, repeat_type, repeat_options, owner_id, terms_date_accepted) VALUES
(5, NOW(), NOW(), 'Client Demo - Nexus Financial Group', 'Product demonstration for prospective enterprise client. Attendees: 3 internal + 4 from client side.', 0, 0, 1, 1, 'none', NULL, 5, NOW());

INSERT INTO reservation_instances (series_id, reference_number, start_date, end_date) VALUES
(5, 'ref-client-demo-001', DATE_ADD(CURDATE(), INTERVAL 2 DAY) + INTERVAL 13 HOUR, DATE_ADD(CURDATE(), INTERVAL 2 DAY) + INTERVAL 14 HOUR + INTERVAL 30 MINUTE);

INSERT INTO reservation_resources (series_id, resource_id, resource_level_id) VALUES (5, 8, 1);

SET @ri5 = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-client-demo-001');
INSERT INTO reservation_users (reservation_instance_id, user_id, reservation_user_level) VALUES (@ri5, 5, 1);

-- Series 6: Team Building Van Trip
INSERT INTO reservation_series (series_id, date_created, last_modified, title, description, allow_participation, allow_anon_participation, type_id, status_id, repeat_type, repeat_options, owner_id, terms_date_accepted) VALUES
(6, NOW(), NOW(), 'DevOps Team Offsite - Escape Room', 'Team building activity at Downtown Escape Rooms. Depart campus 1:30 PM, return by 5:30 PM.', 1, 0, 1, 1, 'none', NULL, 10, NOW());

INSERT INTO reservation_instances (series_id, reference_number, start_date, end_date) VALUES
(6, 'ref-teambuilding-001', DATE_ADD(CURDATE(), INTERVAL 4 DAY) + INTERVAL 13 HOUR + INTERVAL 30 MINUTE, DATE_ADD(CURDATE(), INTERVAL 4 DAY) + INTERVAL 17 HOUR + INTERVAL 30 MINUTE);

INSERT INTO reservation_resources (series_id, resource_id, resource_level_id) VALUES (6, 10, 1);

SET @ri6 = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-teambuilding-001');
INSERT INTO reservation_users (reservation_instance_id, user_id, reservation_user_level) VALUES (@ri6, 10, 1);

-- Series 7: Marketing Photo Shoot
INSERT INTO reservation_series (series_id, date_created, last_modified, title, description, allow_participation, allow_anon_participation, type_id, status_id, repeat_type, repeat_options, owner_id, terms_date_accepted) VALUES
(7, NOW(), NOW(), 'Website Refresh - Team Photos', 'Professional headshots and team photos for website redesign. Photographer: Studio 54 Photography.', 0, 0, 1, 1, 'none', NULL, 9, NOW());

INSERT INTO reservation_instances (series_id, reference_number, start_date, end_date) VALUES
(7, 'ref-photoshoot-001', DATE_ADD(CURDATE(), INTERVAL 6 DAY) + INTERVAL 10 HOUR, DATE_ADD(CURDATE(), INTERVAL 6 DAY) + INTERVAL 16 HOUR);

INSERT INTO reservation_resources (series_id, resource_id, resource_level_id) VALUES (7, 12, 1);

SET @ri7 = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-photoshoot-001');
INSERT INTO reservation_users (reservation_instance_id, user_id, reservation_user_level) VALUES (@ri7, 9, 1);

-- Series 8: Data Science Workshop
INSERT INTO reservation_series (series_id, date_created, last_modified, title, description, allow_participation, allow_anon_participation, type_id, status_id, repeat_type, repeat_options, owner_id, terms_date_accepted) VALUES
(8, NOW(), NOW(), 'ML Model Evaluation Workshop', 'Hands-on workshop reviewing model performance metrics and A/B test results for recommendation engine.', 1, 0, 1, 1, 'none', NULL, 13, NOW());

INSERT INTO reservation_instances (series_id, reference_number, start_date, end_date) VALUES
(8, 'ref-ml-workshop-001', DATE_ADD(CURDATE(), INTERVAL 3 DAY) + INTERVAL 14 HOUR, DATE_ADD(CURDATE(), INTERVAL 3 DAY) + INTERVAL 16 HOUR);

INSERT INTO reservation_resources (series_id, resource_id, resource_level_id) VALUES (8, 4, 1);

SET @ri8 = (SELECT reservation_instance_id FROM reservation_instances WHERE reference_number='ref-ml-workshop-001');
INSERT INTO reservation_users (reservation_instance_id, user_id, reservation_user_level) VALUES (@ri8, 13, 1);

-- ============================================================
-- RESOURCE GROUPS (organize resources by type)
-- ============================================================

INSERT IGNORE INTO resource_groups (resource_group_id, resource_group_name, parent_id) VALUES
(1, 'Meeting Rooms', NULL),
(2, 'Equipment', NULL),
(3, 'Vehicles', NULL),
(4, 'Specialty Spaces', NULL);

INSERT IGNORE INTO resource_group_assignment (resource_group_id, resource_id) VALUES
(1, 1), (1, 2), (1, 3), (1, 6), (1, 7), (1, 8),
(2, 11),
(3, 10),
(4, 4), (4, 5), (4, 9), (4, 12);

-- ============================================================
-- ANNOUNCEMENTS
-- ============================================================

INSERT INTO announcements (announcement_id, announcement_text, priority, start_date, end_date) VALUES
(1, 'Building A elevator maintenance scheduled for April 10-11. Please use stairs or Building B elevator.', 1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY)),
(2, 'New video conferencing equipment installed in the Video Conference Suite (Room 301). Training sessions available - contact AV support.', 3, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 30 DAY));

SET foreign_key_checks = 1;
