$filePath = "websters_1828_definitions.dart"
$content = Get-Content -Raw -Path $filePath

# Replace 'YOUR_DEFINITION_HERE' with your actual definition text
$saintEntry = @"
  'Saint': {
    'id': 46296,
    'definition': 'YOUR_DEFINITION_HERE',
  },`n
"@

# 1. Increment every ID greater than or equal to 46296 by 1
$updatedContent = [regex]::Replace($content, "('id':\s*)(\d+)", {
    param($m)
    $id = [int]$m.Groups[2].Value
    if ($id -ge 46296) {
        return $m.Groups[1].Value + ($id + 1)
    }
    return $m.Value
})

# 2. Insert the 'Saint' entry directly before the key that now holds ID 46297
$finalContent = [regex]::Replace($updatedContent, "(  '[^']+'\s*:\s*\{\s*'id':\s*46297)", "$saintEntry`$1")

# 3. Overwrite the file with updated contents
Set-Content -Path $filePath -Value $finalContent -Encoding UTF8