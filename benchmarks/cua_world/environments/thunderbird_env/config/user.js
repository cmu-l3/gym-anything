// Thunderbird preferences for gym-anything environment
// Optimized for container usage and agent interaction

// === Disable First-Run and Updates ===
user_pref("mail.provider.enabled", false);
user_pref("mail.startup.enabledMailCheckOnce", false);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.update.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false);

// === Disable Telemetry and Reporting ===
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.crashreporter.enabled", false);

// === Mail Settings ===
user_pref("mail.shell.checkDefaultClient", false);
user_pref("mail.root.none-rel", "[ProfD]Mail");
user_pref("mail.root.none", "Mail");
user_pref("mail.server.default.check_new_mail", false);
user_pref("mail.biff.show_alert", false);

// === Compose Settings ===
user_pref("mail.compose.default_to_paragraph", false);
user_pref("mail.compose.attachment_reminder", false);
user_pref("mail.SpellCheckBeforeSend", false);
user_pref("mail.warn_on_send_accel_key", false);
user_pref("mail.compose.autosave", false);
user_pref("mailnews.sendformat.auto_downgrade", true);

// === Performance ===
user_pref("mail.db.global.indexer.enabled", true);
user_pref("mailnews.database.global.indexer.enabled", true);
user_pref("mail.strictly_mime", false);
user_pref("mailnews.headers.showSender", 1);

// === UI Settings ===
user_pref("mail.tabs.autoHide", false);
user_pref("mail.tabs.drawInTitlebar", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("mail.ui.show.statusbar", true);

// === Offline/Network ===
user_pref("offline.autoDetect", false);
user_pref("offline.startup_state", 0);

// === Calendar ===
user_pref("calendar.timezone.local", "America/New_York");
user_pref("calendar.alarms.show", false);
user_pref("calendar.alarms.playsound", false);

// === Privacy ===
user_pref("mail.collect_email_address_outgoing", false);
user_pref("mailnews.message_display.disable_remote_image", false);
user_pref("mail.phishing.detection.enabled", false);

// === Downloads ===
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.download.folderList", 1);
user_pref("browser.download.manager.showWhenStarting", false);

// === Search ===
user_pref("mailnews.database.global.indexer.enabled", true);

// === Debugging ===
user_pref("devtools.debugger.remote-enabled", true);
user_pref("devtools.chrome.enabled", true);
user_pref("devtools.debugger.prompt-connection", false);

// === Performance Tuning ===
user_pref("mail.db.max_gloda_results_per_page", 1000);
user_pref("mailnews.tcptimeout", 100);
