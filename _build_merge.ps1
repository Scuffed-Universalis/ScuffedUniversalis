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
}

# 1. Clear previous build output (keeps this script, descriptor and thumbnail)
Get-ChildItem $dst -Directory | Remove-Item -Recurse -Force

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

Write-Host "Done."
