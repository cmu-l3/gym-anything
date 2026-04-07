-- Casebox Seed Data: Real Human Rights Cases
-- Sources: European Court of Human Rights (ECHR) judgments, UN Treaty Body decisions,
-- Inter-American Court of Human Rights (IACtHR) cases
-- All case names and details are from publicly available court records

-- First, identify the template IDs from the default installation
-- Casebox uses a tree structure where every item (folder, file, task) is a node

-- Get the folder template ID (typically id=5 in default install)
SET @folder_tpl = (SELECT id FROM templates WHERE `type` = 'object' AND name LIKE '%older%' LIMIT 1);
SET @folder_tpl = COALESCE(@folder_tpl, 5);

-- Get the task template ID (typically id=7 in default install)
SET @task_tpl = (SELECT id FROM templates WHERE `type` = 'object' AND name LIKE '%ask%' LIMIT 1);
SET @task_tpl = COALESCE(@task_tpl, 7);

-- Get the root tree node (pid=null or the main container)
SET @root_id = (SELECT id FROM tree WHERE pid IS NULL ORDER BY id LIMIT 1);
SET @root_id = COALESCE(@root_id, 1);

-- ============================================================
-- Create main organizational folders
-- ============================================================

-- ECHR Cases folder
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@root_id, @folder_tpl, 'ECHR Case Documentation', 1, 1, '2024-01-15 09:00:00', '2024-01-15 09:00:00', 0, 0);
SET @echr_folder = LAST_INSERT_ID();

-- UN Treaty Body Cases folder
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@root_id, @folder_tpl, 'UN Treaty Body Decisions', 1, 1, '2024-01-15 09:05:00', '2024-01-15 09:05:00', 0, 0);
SET @un_folder = LAST_INSERT_ID();

-- Inter-American Court Cases folder
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@root_id, @folder_tpl, 'Inter-American Court Cases', 1, 1, '2024-01-15 09:10:00', '2024-01-15 09:10:00', 0, 0);
SET @iachr_folder = LAST_INSERT_ID();

-- Active Investigations folder
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@root_id, @folder_tpl, 'Active Investigations', 1, 1, '2024-02-01 10:00:00', '2024-02-01 10:00:00', 0, 0);
SET @active_folder = LAST_INSERT_ID();

-- ============================================================
-- ECHR Cases - Real case names from European Court of Human Rights
-- ============================================================

-- Case subfolder: Hanan v. Germany [GC] (Application no. 4871/16) - 2021 judgment on extraterritorial jurisdiction
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@echr_folder, @folder_tpl, 'Hanan v. Germany [GC] - App. 4871/16', 1, 1, '2024-02-10 11:00:00', '2024-02-10 11:00:00', 0, 0);
SET @case_hanan = LAST_INSERT_ID();

-- Case subfolder: Georgia v. Russia (II) [GC] (Application no. 38263/08) - 2021 inter-state case
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@echr_folder, @folder_tpl, 'Georgia v. Russia (II) [GC] - App. 38263/08', 1, 1, '2024-02-12 09:30:00', '2024-02-12 09:30:00', 0, 0);
SET @case_georgia = LAST_INSERT_ID();

-- Case subfolder: Big Brother Watch v. United Kingdom [GC] (Applications 58170/13, 62322/14, 24960/15)
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@echr_folder, @folder_tpl, 'Big Brother Watch v. UK [GC] - App. 58170/13', 1, 1, '2024-02-15 14:00:00', '2024-02-15 14:00:00', 0, 0);
SET @case_bbw = LAST_INSERT_ID();

-- Case subfolder: Centrum for Rattvisa v. Sweden [GC] (Application no. 35252/08) - surveillance
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@echr_folder, @folder_tpl, 'Centrum for Rattvisa v. Sweden [GC] - App. 35252/08', 1, 1, '2024-02-18 10:15:00', '2024-02-18 10:15:00', 0, 0);
SET @case_centrum = LAST_INSERT_ID();

-- Case subfolder: Sedletska v. Ukraine (Application no. 42634/18) - freedom of press
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@echr_folder, @folder_tpl, 'Sedletska v. Ukraine - App. 42634/18', 1, 1, '2024-03-01 08:45:00', '2024-03-01 08:45:00', 0, 0);
SET @case_sedletska = LAST_INSERT_ID();

-- Case subfolder: Fedotova and Others v. Russia [GC] (Applications 40792/10, 30## etc.)
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@echr_folder, @folder_tpl, 'Fedotova and Others v. Russia [GC] - App. 40792/10', 1, 1, '2024-03-05 13:20:00', '2024-03-05 13:20:00', 0, 0);
SET @case_fedotova = LAST_INSERT_ID();

-- Case subfolder: Yildirim v. Turkey (Application no. 3111/10) - internet censorship
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@echr_folder, @folder_tpl, 'Yildirim v. Turkey - App. 3111/10', 1, 1, '2024-03-10 15:00:00', '2024-03-10 15:00:00', 0, 0);

-- ============================================================
-- UN Treaty Body Decisions - Real decisions from UN committees
-- ============================================================

-- HRC Decision: Toonen v. Australia (Communication No. 488/1992) - landmark LGBTQ rights
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@un_folder, @folder_tpl, 'Toonen v. Australia - HRC Comm. 488/1992', 1, 1, '2024-03-15 09:00:00', '2024-03-15 09:00:00', 0, 0);

-- CAT Decision: Agiza v. Sweden (Communication No. 233/2003) - non-refoulement
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@un_folder, @folder_tpl, 'Agiza v. Sweden - CAT Comm. 233/2003', 1, 1, '2024-03-18 10:30:00', '2024-03-18 10:30:00', 0, 0);

-- CEDAW Decision: A.T. v. Hungary (Communication No. 2/2003) - domestic violence
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@un_folder, @folder_tpl, 'A.T. v. Hungary - CEDAW Comm. 2/2003', 1, 1, '2024-03-20 11:00:00', '2024-03-20 11:00:00', 0, 0);

-- CERD Decision: L.R. et al. v. Slovak Republic (Communication No. 31/2003)
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@un_folder, @folder_tpl, 'L.R. et al. v. Slovak Republic - CERD Comm. 31/2003', 1, 1, '2024-03-22 14:00:00', '2024-03-22 14:00:00', 0, 0);

-- CRC Decision: Y.B. and N.S. v. Belgium (Communication No. 12/2017) - child detention
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@un_folder, @folder_tpl, 'Y.B. and N.S. v. Belgium - CRC Comm. 12/2017', 1, 1, '2024-03-25 09:30:00', '2024-03-25 09:30:00', 0, 0);

-- ============================================================
-- Inter-American Court Cases - Real IACtHR judgments
-- ============================================================

-- Velasquez Rodriguez v. Honduras (1988) - landmark enforced disappearance case
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@iachr_folder, @folder_tpl, 'Velasquez Rodriguez v. Honduras (1988)', 1, 1, '2024-04-01 09:00:00', '2024-04-01 09:00:00', 0, 0);

-- Barrios Altos v. Peru (2001) - amnesty laws and impunity
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@iachr_folder, @folder_tpl, 'Barrios Altos v. Peru (2001)', 1, 1, '2024-04-05 10:00:00', '2024-04-05 10:00:00', 0, 0);

-- Atala Riffo and Daughters v. Chile (2012) - LGBTQ rights and child custody
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@iachr_folder, @folder_tpl, 'Atala Riffo and Daughters v. Chile (2012)', 1, 1, '2024-04-08 11:30:00', '2024-04-08 11:30:00', 0, 0);

-- Kichwa Indigenous People of Sarayaku v. Ecuador (2012) - indigenous rights
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@iachr_folder, @folder_tpl, 'Sarayaku v. Ecuador (2012)', 1, 1, '2024-04-10 14:00:00', '2024-04-10 14:00:00', 0, 0);

-- ============================================================
-- Active Investigations - current work items with tasks
-- ============================================================

-- Active investigation folder: Migrant Detention Documentation Project
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@active_folder, @folder_tpl, 'Migrant Detention Documentation Project', 1, 1, '2024-05-01 09:00:00', '2024-05-01 09:00:00', 0, 0);
SET @detention_folder = LAST_INSERT_ID();

-- Active investigation folder: Digital Surveillance Monitoring Initiative
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@active_folder, @folder_tpl, 'Digital Surveillance Monitoring Initiative', 1, 1, '2024-05-05 10:00:00', '2024-05-05 10:00:00', 0, 0);
SET @surveillance_folder = LAST_INSERT_ID();

-- Active investigation folder: Environmental Rights and Indigenous Communities
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@active_folder, @folder_tpl, 'Environmental Rights and Indigenous Communities', 1, 1, '2024-05-10 11:00:00', '2024-05-10 11:00:00', 0, 0);
SET @enviro_folder = LAST_INSERT_ID();

-- Tasks within active investigations
INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@detention_folder, @task_tpl, 'Review detention facility reports from UNHCR field offices', 1, 1, '2024-05-02 09:00:00', '2024-05-02 09:00:00', 0, 0);

INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@detention_folder, @task_tpl, 'Contact local NGO partners for witness statements', 1, 1, '2024-05-03 10:00:00', '2024-05-03 10:00:00', 0, 0);

INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@detention_folder, @task_tpl, 'Compile medical evidence from MSF clinic reports', 1, 1, '2024-05-04 11:00:00', '2024-05-04 11:00:00', 0, 0);

INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@surveillance_folder, @task_tpl, 'Analyze Citizen Lab technical reports on Pegasus deployment', 1, 1, '2024-05-06 09:00:00', '2024-05-06 09:00:00', 0, 0);

INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@surveillance_folder, @task_tpl, 'Map affected journalists and activists by region', 1, 1, '2024-05-07 10:00:00', '2024-05-07 10:00:00', 0, 0);

INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@enviro_folder, @task_tpl, 'Document land rights violations in Amazon basin communities', 1, 1, '2024-05-11 09:00:00', '2024-05-11 09:00:00', 0, 0);

INSERT INTO tree (pid, template_id, `name`, cid, uid, cdate, udate, dstatus, `system`)
VALUES (@enviro_folder, @task_tpl, 'Review IACHR precautionary measures for affected communities', 1, 1, '2024-05-12 10:00:00', '2024-05-12 10:00:00', 0, 0);

-- ============================================================
-- Verify seed data
-- ============================================================
SELECT 'Seed data imported successfully' AS status,
       (SELECT COUNT(*) FROM tree WHERE dstatus = 0 AND `system` = 0) AS total_user_nodes,
       (SELECT COUNT(*) FROM tree WHERE template_id = @folder_tpl AND dstatus = 0 AND `system` = 0) AS folder_count,
       (SELECT COUNT(*) FROM tree WHERE template_id = @task_tpl AND dstatus = 0 AND `system` = 0) AS task_count;
