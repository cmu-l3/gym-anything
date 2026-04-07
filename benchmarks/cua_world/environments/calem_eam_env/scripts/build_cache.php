<?php
if (!defined("_CALEM_DIR_")) {
    chdir("../..");
    define("_CALEM_DIR_", getcwd() . "/");
    define("LOG4PHP_CONFIGURATION", _CALEM_DIR_ . "etc/log4php.properties");
}
error_reporting(E_ALL & ~E_DEPRECATED & ~E_NOTICE & ~E_STRICT);

require_once _CALEM_DIR_ . "server/conf/calem.php";

$conf = $GLOBALS["_CALEM_conf"];
$dsn = "mysql:host=" . $conf["calem_db_host"] . ";dbname=" . $conf["calem_db_name"];
$pdo = new PDO($dsn, $conf["calem_db_user"], $conf["calem_db_password"]);
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

// Fetch all ACL groups
$stmt = $pdo->query("SELECT * FROM acl_group");
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo "ACL groups: " . count($rows) . "\n";

// Build parent map
$parentMap = array();
foreach ($rows as $row) {
    $gid = $row["id"];
    $parentMap[$gid] = array();
    $pid = isset($row["parent_group_id"]) ? $row["parent_group_id"] : null;
    $visited = array();
    while ($pid && !in_array($pid, $visited)) {
        $parentMap[$gid][] = $pid;
        $visited[] = $pid;
        $nextPid = null;
        foreach ($rows as $prow) {
            if ($prow["id"] == $pid) {
                $nextPid = isset($prow["parent_group_id"]) ? $prow["parent_group_id"] : null;
                break;
            }
        }
        $pid = $nextPid;
    }
}

// Build data array
$data = array();
foreach ($rows as $row) {
    $data[] = array($row["id"], false);
}

// Write cache
$cacheData = array("data" => $data, "parentMap" => $parentMap);

require_once _CALEM_DIR_ . "server/include/core/cache/CalemFileCacheManager.php";
$cache = CalemFileCacheManager::getInstance();
$cache->save($cacheData, "acl_group");
echo "ACL group cache saved\n";

// Verify
$verify = $cache->load("acl_group");
echo "Verify: " . ($verify !== false ? "OK" : "FAILED") . "\n";
if ($verify) {
    echo "parentMap keys: " . implode(", ", array_keys($verify["parentMap"])) . "\n";
}
?>
