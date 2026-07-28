$file = "lib\main.dart"
$content = Get-Content $file -Raw
$startStr = " void _showGainDetailsDialog(BuildContext context) async {"

$start = $content.IndexOf($startStr)
$count = 0
$end = -1
for ($i = $start; $i -lt $content.Length; $i++) {
    if ($content[$i] -eq "{") { $count++ }
    elseif ($content[$i] -eq "}") {
        $count--
        if ($count -eq 0) {
            $end = $i
            break
        }
    }
}
Write-Output "$start to $end"
