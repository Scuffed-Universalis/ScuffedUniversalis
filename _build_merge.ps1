# Rebuilds "JG Expanded" from the Steam Workshop copies of its source mods.
# Re-run after any source mod updates:  powershell -ExecutionPolicy Bypass -File _build_merge.ps1
# Load order matches the playset/collection: later mods overwrite same-path files from earlier ones.

$ErrorActionPreference = 'Stop'
$ws  = "C:\Program Files (x86)\Steam\steamapps\workshop\content\236850"
$dst = $PSScriptRoot
$cp1252 = [System.Text.Encoding]::GetEncoding(1252)

$mods = [ordered]@{
  'Europa Expanded'               = '2164202838'
  'Holy Roman Empire Expanded'    = '1352521684'
  'Governments Expanded'          = '1596815683'
  'Ages and Splendor Expanded'    = '2172666098'
  'Great Monuments Expanded'      = '2469419235'
  'Advisor Types Expanded'        = '2737385499'
  'Doge Ideas Fixed'              = '3799936009'
  'No MP Slowdown'                = '2551069952'
  'Kingdom of Yugoslavia'         = '2014721248'
}

# 1. Clear previous build output (keeps this script, descriptor, thumbnail and _custom)
Get-ChildItem $dst -Directory | Where-Object { $_.Name -ne '_custom' } | Remove-Item -Recurse -Force

# 2. Copy each mod's content folders in load order
foreach ($name in $mods.Keys) {
  $src = Join-Path $ws $mods[$name]
  if (-not (Test-Path $src)) { throw "Missing workshop folder for $name ($src) - subscribe in Steam first." }
  Write-Host "Copying $name"
  foreach ($dir in Get-ChildItem $src -Directory) {
    Copy-Item $dir.FullName -Destination $dst -Recurse -Force
  }
}

function Read-1252($path)          { $cp1252.GetString([System.IO.File]::ReadAllBytes($path)) }
function Write-1252($path, $text)  { [System.IO.File]::WriteAllBytes($path, $cp1252.GetBytes($text)) }

# 3. Patches

# 3a. Doge Ideas Fixed ships old-vanilla country files only to empty historical_idea_groups;
#     they would also revert EE's map colours and use a non-existent unit (qizilbash_cavalry).
#     Use EE's files and apply just the idea-group change.
foreach ($tag in 'fars','franconia','portugal','swabia') {
  $text = Read-1252 (Join-Path $ws "2164202838\common\countries\$tag.txt")
  $text = [regex]::Replace($text, 'historical_idea_groups\s*=\s*\{[^}]*\}', 'historical_idea_groups = {}')
  Write-1252 (Join-Path $dst "common\countries\$tag.txt") $text
}

# 3b. Pragmatic Sanction: keep HRE Expanded's Golden Bull check plus EE's mission reward (me_free_pragmatic_sanction).
Write-1252 (Join-Path $dst "decisions\pragmaticsanction.txt") @'
country_decisions = {

	pragmatic_sanction_decision = {
		potential = {
			allows_female_emperor = no
			NOT = { has_country_flag = pragmatic_sanction }
			is_part_of_hre = yes
		}
		allow = {
			OR = {
				imperial_influence = 25
				has_country_flag = me_free_pragmatic_sanction
			}
			prestige = 1
			legitimacy = 90
			allows_female_emperor = no
			OR = {
				has_female_heir = yes
				custom_trigger_tooltip = {
					tooltip = me_has_completed_certain_mission
					has_country_flag = me_free_pragmatic_sanction
				}
			}
			is_emperor = yes
			if = {
				limit = {
					NOT = { hre_reform_passed = erbkaisertum }
					NOT = { hre_reform_passed = emperor_erbkaisertum }
				}
				custom_trigger_tooltip = {
					tooltip = LAWS_OF_THE_GOLDEN_BULL_ARE_NOT_ACTIVE
					OR = {
						NOT = { has_global_flag = hre_golden_bull_enacted }
						has_global_flag = hre_golden_bull_removed
					}
				}
			}
		}
		effect = {
			if = {
				limit = {
					NOT = { has_country_flag = me_free_pragmatic_sanction }
				}
				add_imperial_influence = -25
			}
			add_legitimacy = -25
			country_event = { id = pragmatic_sanction.2 }
		}
		ai_will_do = {
			factor = 1
		}
	}

}
'@

# 3c. events/ideagroups.txt comes from Doge Ideas Fixed; re-add EE's France mission bonus to "Women needed" (ideagroups.1206).
$path = Join-Path $dst "events\ideagroups.txt"
$text = Read-1252 $path
if ($text -notmatch 'fra_double_the_women_flag') {
  $re = [regex]'(?s)(id = ideagroups\.1206\b.*?mean_time_to_happen = \{\s*days = 1)'
  if (-not $re.IsMatch($text)) { throw "ideagroups.1206 patch target not found" }
  $text = $re.Replace($text, "`$1`r`n`t`tmodifier = {`r`n`t`t`tfactor = 2`r`n`t`t`thas_country_flag = fra_double_the_women_flag`r`n`t`t}", 1)
  Write-1252 $path $text
}

# 3d. Kingdom of Yugoslavia: its build_treasury/build_manufactories missions share names with vanilla generic
#     missions (completion is tracked by name), so rename them; fix its loc gaps; add the missing country history.
#     Mission reward modifiers last until the end of the game, except the ones listed in $keepTimed
#     (yug_recent_culture_progress is the cooldown that gates the slot 1 missions, so it must expire).
$keepTimed = 'yug_crusade_against_ottomans','growing_economy','national_bank_inflation','yug_recent_culture_progress'
foreach ($file in Get-ChildItem (Join-Path $dst "missions") -Filter "yug_Yugoslavia_*_Missions.txt") {
  $text = Read-1252 $file.FullName
  $text = [regex]::Replace($text, '\b(build_treasury|build_manufactories)\b', 'yug_$1')
  $text = [regex]::Replace($text, 'name\s*=\s*"?army_enthusiasm"?', 'name = yug_army_enthusiasm')
  $text = [regex]::Replace($text, '(add_country_modifier\s*=\s*\{\s*name\s*=\s*"?(\w+)"?\s*duration\s*=\s*)\d+', {
    param($m)
    if ($keepTimed -contains $m.Groups[2].Value) { $m.Value } else { $m.Groups[1].Value + '-1' }
  })
  $text = [regex]::Replace($text, '(duration\s*=\s*-1)[ \t]*#[^\r\n]*', '$1')
  Write-1252 $file.FullName $text
}

# Westernize: require 50 prestige instead of ducats/military power/splendor, and don't take them away.
$path = Join-Path $dst "missions\yug_Yugoslavia_3_Missions.txt"
$text = Read-1252 $path
$re = [regex]'(\s*)treasury\s*=\s*2000\s*mil_power\s*=\s*400\s*if\s*=\s*\{\s*limit\s*=\s*\{\s*has_dlc\s*=\s*"Mandate of Heaven"\s*\}\s*splendor\s*=\s*600\s*\}'
if (-not $re.IsMatch($text)) { throw "yug_westernize trigger patch target not found" }
$text = $re.Replace($text, '$1prestige = 50', 1)
$re = [regex]'\s*add_splendor\s*=\s*-600\s*add_treasury\s*=\s*-2000\s*add_mil_power\s*=\s*-400'
if (-not $re.IsMatch($text)) { throw "yug_westernize effect patch target not found" }
$text = $re.Replace($text, '', 1)
# Coal Mining repeated Build Manufactories' proto_industrialization; give it its own modifier.
$re = [regex]'(?s)(yug_furnace\s*=\s*\{.*?name\s*=\s*)"?proto_industrialization"?'
if (-not $re.IsMatch($text)) { throw "yug_furnace modifier patch target not found" }
$text = $re.Replace($text, '$1yug_coal_mining', 1)
Write-1252 $path $text

# Defense against the Ottomans is permanent now, so tone it down.
$path = Join-Path $dst "common\event_modifiers\yug_crusade.txt"
$text = Read-1252 $path
$re = [regex]'yug_defends_against_ottomans\s*=\s*\{[^}]*\}'
if (-not $re.IsMatch($text)) { throw "yug_defends_against_ottomans patch target not found" }
$text = $re.Replace($text, "yug_defends_against_ottomans = {`r`n`tdefensiveness = 0.15`r`n`tglobal_manpower_modifier = 0.05`r`n`tmanpower_recovery_speed = 0.05`r`n}", 1)
Write-1252 $path $text

# Yugoslavia's own copy of vanilla army_enthusiasm with extra morale (vanilla's is shared by other nations' missions).
Write-1252 (Join-Path $dst "common\event_modifiers\yug_mission_modifiers.txt") @'
yug_army_enthusiasm = {
	yearly_army_professionalism = 0.001
	army_tradition = 0.5
	land_morale = 0.05
}

yug_coal_mining = {
	trade_goods_size_modifier = 0.05
}
'@
# (accented letters as [char] codes: Windows PowerShell reads this BOM-less script as ANSI)
$e_ = [char]0xE8; $o_ = [char]0xF6; $a_ = [char]0xE4; $oa = [char]0xF3
$extraLoc = @{
  english = ' yug_coal_mining:0 "Coal Mining Industry"', ' desc_yug_coal_mining:0 "The coal pits of Hum fuel our furnaces and workshops."'
  french  = " yug_coal_mining:0 `"Industrie houill${e_}re`"",  ' desc_yug_coal_mining:0 "Les mines de charbon de Hum alimentent nos fourneaux et nos ateliers."'
  german  = ' yug_coal_mining:0 "Kohlebergbau"',              " desc_yug_coal_mining:0 `"Die Kohlegruben von Hum befeuern unsere Hoch${o_}fen und Werkst${a_}tten.`""
  spanish = " yug_coal_mining:0 `"Industria del carb${oa}n`"", " desc_yug_coal_mining:0 `"Las minas de carb${oa}n de Hum alimentan nuestros hornos y talleres.`""
}

$game  ="C:\Program Files (x86)\Steam\steamapps\common\Europa Universalis IV"
$utf8  = New-Object System.Text.UTF8Encoding $true
$keyRe = '^\s*([\w\.]+):'
$en = [System.IO.File]::ReadAllLines((Join-Path $dst "localisation\yug_locals_l_english.yml"), $utf8) | Select-Object -Skip 1
foreach ($lang in 'english','french','german','spanish') {
  $path  = Join-Path $dst "localisation\yug_locals_l_$lang.yml"
  $lines = [System.Collections.Generic.List[string]][System.IO.File]::ReadAllLines($path, $utf8)
  # a few keys sit at column 0, which the loc parser can drop
  for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\w') { $lines[$i] = ' ' + $lines[$i] } }
  $have = @{}
  foreach ($l in $lines) { if ($l -match $keyRe) { $have[$matches[1]] = $true } }
  # keys missing from the translations fall back to English
  foreach ($l in $en) { if ($l -match $keyRe -and -not $have[$matches[1]]) { $lines.Add(' ' + $l.TrimStart()); $have[$matches[1]] = $true } }
  # renamed missions reuse the vanilla generic mission text
  foreach ($l in [System.IO.File]::ReadAllLines("$game\localisation\new_missions_l_$lang.yml", $utf8)) {
    if ($l -match '^\s*(build_treasury|build_manufactories)_(title|desc):' -and -not $have["yug_$($matches[1])_$($matches[2])"]) {
      $lines.Add(' yug_' + $l.TrimStart())
    }
  }
  foreach ($l in [System.IO.File]::ReadAllLines("$game\localisation\modifers_l_$lang.yml", $utf8)) {
    if ($l -match '^\s*(desc_)?army_enthusiasm(:.*)$' -and -not $have["$($matches[1])yug_army_enthusiasm"]) {
      $lines.Add(" $($matches[1])yug_army_enthusiasm$($matches[2])")
    }
  }
  foreach ($l in $extraLoc[$lang]) { if ($l -match $keyRe -and -not $have[$matches[1]]) { $lines.Add($l) } }
  [System.IO.File]::WriteAllLines($path, $lines, $utf8)
}

Write-1252 (Join-Path $dst "history\countries\YUG - Yugoslavia.txt") @'
government = monarchy
add_government_reform = feudalism_reform
government_rank = 2
primary_culture = serbian
religion = orthodox
technology_group = eastern
capital = 4239	# Belgrade
'@

# 3e. Merina (MIR) gets the ported Malagasy Glory tree (_custom\missions\mir_glory_missions.txt) laid out around
#     vanilla's East Africa and African trees, as in the original mod: no Paradox/Expanded mission choice and
#     no EE generic Madagascar tree.
foreach ($rel in 'common\scripted_triggers\missions_expanded_scripted_triggers.txt','missions\ME_Generic_Madagascar_Missions.txt') {
  $path = Join-Path $dst $rel
  $text = Read-1252 $path
  $re = [regex]'(?m)^[ \t]*tag = MIR[ \t]*\r?\n'
  if (-not $re.IsMatch($text)) { throw "MIR patch target not found in $rel" }
  Write-1252 $path $re.Replace($text, '')
}
#     East Africa: MIR always qualifies, whether or not it has the use_paradox_missions flag.
$path = Join-Path $dst "missions\AFR_East_Africa_Missions.txt"
$text = Read-1252 $path
$re = [regex]'(?m)^[ \t]*NOT = \{ tag = MIR \}[ \t]*\r?\n'
if (-not $re.IsMatch($text)) { throw "East Africa MIR patch target not found" }
Write-1252 $path $re.Replace($text, '')
#     African (slot 5): EE comments out vanilla's tree for everyone; bring it back for MIR only.
if (@((Read-1252 (Join-Path $dst "missions\African_Missions.txt")) -split "`n" | Where-Object { $_.Trim() -and $_.Trim() -notmatch '^#' }).Count) {
  throw "African_Missions.txt is no longer fully commented out - mir_african_missions.txt would duplicate its missions"
}
$text = Read-1252 "$game\missions\African_Missions.txt"
$re = [regex]'(?s)^african_missions\s*=\s*\{(.*?)potential\s*=\s*\{.*?\r?\n\t\}'
if (-not $re.IsMatch($text)) { throw "vanilla African_Missions.txt layout changed - check the MIR patch" }
Write-1252 (Join-Path $dst "missions\mir_african_missions.txt") $re.Replace($text, "mir_african_missions = {`$1potential = {`r`n`t`ttag = MIR`r`n`t}", 1)
#     Vanilla's always-on generic trees (slots 2-4) otherwise stack onto MIR's columns where its own missions
#     start lower down, so take a copy of the installed vanilla file that excludes MIR.
$text = Read-1252 "$game\missions\00_Generic_missions.txt"
$re = [regex]'potential\s*=\s*\{\s*always\s*=\s*yes\s*\}'
if ($re.Matches($text).Count -ne 3) { throw "vanilla 00_Generic_missions.txt layout changed - check the MIR patch" }
Write-1252 (Join-Path $dst "missions\00_Generic_missions.txt") $re.Replace($text, "potential = {`r`n`t`tNOT = { tag = MIR }`r`n`t}")

# 4. Hand-maintained content (ports from mods too broken to patch, e.g. Merina's "Malagasy Glory" missions).
#    Lives in _custom\ with the normal mod folder layout and is copied over the build output last.
foreach ($dir in Get-ChildItem (Join-Path $dst '_custom') -Directory) {
  Copy-Item $dir.FullName -Destination $dst -Recurse -Force
}

Write-Host "Done."
