<?php
$version = getenv('APP_VERSION') ?: 'v1.0-BLUE (Production)';
$bg = strpos($version, 'v2.0') !== false ? '#0f5132' : '#084298';
echo "<body style='background:$bg; color:white; font-family:sans-serif; text-align:center; padding-top:50px;'>";
echo "<h1>Azure Cloud-Native Container Architecture</h1>";
echo "<h2>Active Release: $version</h2>";
echo "<p>Authenticated to Private ACR via Entra Managed Identity (Zero Secrets)</p>";
echo "</body>";
?>
