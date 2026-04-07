<?php
error_reporting(0);
ini_set('display_errors', '0');
http_response_code(200);
$root_path = '../';
require_once($root_path . 'include/core/Database.php');
try {
    Database::init('localhost', 'care2x', 'care2x', 'care2x_pass');
    $pdo = Database::pdo();
} catch (Throwable $e) {}
?>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>Menu - Care2x</title>
<link rel="stylesheet" href="menu/dtree/dtree.css" type="text/css" />
<script language="javascript" src="menu/dtree/dtree.js" type="text/javascript"></script>
<style>body { font-family: Arial, sans-serif; font-size: 11px; margin: 5px; }</style>
</head>
<body>
<center><a href="../index.php" target="_top"><img src="../gui/img/logos/care_logo.png" border=0 width="135" height="39"></a></center>
<br>
<script language="javascript">
function runModul(ziel) {
    window.parent.CONTENTS.location.href=ziel;
}
m = new dTree('m');
m.config.useIcons=true;
m.config.useLines=true;
m.config.closeSameLevel=true;
m.config.useSelection=false;
m.config.useCookies=false;
m.add(0,-1,'<b>Menu</b>','','','','img/trash.gif','../gui/img/common/default/address_book2.gif');
<?php
if (isset($pdo)) {
    try {
        $stmt = $pdo->query('SELECT nr, sort_nr, name, LD_var, url, is_visible FROM care_menu_main WHERE is_visible=1 ORDER BY sort_nr');
        $idx = 1;
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $name = htmlspecialchars($row['name']);
            $url = htmlspecialchars($row['url']);
            echo "m.add($idx,0,'$name','javascript:runModul(\"../$url?lang=en\")','','','','');\n";
            // Add sub-menu items
            $sub_stmt = $pdo->query("SELECT s_nr, s_sort_nr, s_name, s_url, s_url_ext FROM care_menu_sub WHERE s_main_nr={$row['nr']} AND s_ebene=1 ORDER BY s_sort_nr");
            $sub_idx = $idx * 100 + 1;
            while ($sub = $sub_stmt->fetch(PDO::FETCH_ASSOC)) {
                if (!empty($sub['s_name'])) {
                    $sname = htmlspecialchars($sub['s_name']);
                    $surl = htmlspecialchars($sub['s_url'] . $sub['s_url_ext']);
                    echo "m.add($sub_idx,$idx,'$sname','javascript:runModul(\"../$surl?lang=en\")','','','','');\n";
                    $sub_idx++;
                }
            }
            $idx++;
        }
    } catch (Throwable $e) {}
}
?>
document.write(m);
</script>
<br>
<hr>
<small><a href="login.php" target="CONTENTS">Login</a></small>
</body>
</html>
