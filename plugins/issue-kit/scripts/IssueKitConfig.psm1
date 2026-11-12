<#
.SYNOPSIS
	Reads the issue-kit configuration: three JSON layers merged key by key, validated against the defaults file.

.DESCRIPTION
	Layer 1 is issue-kit.config.default.json in the plugin folder. Layer 2 is issue-kit.config.json in the Claude
	config folder (CLAUDE_CONFIG_DIR, else ~/.claude). Layer 3 is issue-kit.config.json in the repository root.
	A later layer overrides an earlier one. Objects merge key by key; a list or a text replaces the earlier value as
	a whole. The defaults file is the schema: a key that is not in it, or a value of another type, stops the read with
	a message that names the file and the key.
#>

Set-StrictMode -Version Latest

$script:configFileName = 'issue-kit.config.json'
$script:defaultsFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'issue-kit.config.default.json'
$script:regexKeys = @('prd.idPattern', 'plans.typeLabelPattern', 'ordering.titleCodePattern')
$script:requiredTextKeys = @('baseBranch', 'branchPattern', 'batchBranchPattern', 'shipLanguage', 'plans.dir', 'plans.nameTemplate',
	'plans.language', 'issueSections.requirements', 'issueSections.acceptance', 'issueSections.dependencies',
	'roles.planner', 'roles.developer', 'roles.buildRunner', 'roles.skillRunner')
$script:placeholders = @{
	'branchPattern'        = @('{n}', '{slug}')
	'batchBranchPattern'   = @('{first}', '{last}', '{slug}')
	'plans.nameTemplate'   = @('{n}')
	'commands.testProject' = @('{project}')
}

function Get-ValueKind([AllowNull()]$Value) {
	if ($null -eq $Value) { return 'null' }
	if ($Value -is [string]) { return 'text' }
	if ($Value -is [bool]) { return 'true or false' }
	if ($Value -is [System.Management.Automation.PSCustomObject]) { return 'object' }
	if ($Value -is [System.Collections.IList]) { return 'list' }
	if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return 'number' }
	return $Value.GetType().Name
}

function Add-Article([string]$Kind) {
	if ($Kind -eq 'true or false') { return 'true or false' }
	if ($Kind -match '^[aeiou]') { return "an $Kind" }
	return "a $Kind"
}

function ConvertTo-OrderedTree([AllowNull()]$Value) {
	if ($Value -is [System.Management.Automation.PSCustomObject]) {
		$tree = [ordered]@{}
		foreach ($p in $Value.PSObject.Properties) { $tree[$p.Name] = ConvertTo-OrderedTree $p.Value }
		return $tree
	}
	if ($Value -is [System.Collections.IList]) { return , @($Value | ForEach-Object { ConvertTo-OrderedTree $_ }) }
	return $Value
}

function Read-JsonFile([string]$File) {
	try { $data = [IO.File]::ReadAllText($File) | ConvertFrom-Json }
	catch { throw "${File}: not valid JSON: $($_.Exception.Message)" }
	if ($data -isnot [System.Management.Automation.PSCustomObject]) { throw "${File}: must hold a JSON object." }
	return $data
}

function Assert-Layer {
	<# Checks one layer against the schema (the defaults) and throws on the first unknown key or wrong type. #>
	param($Layer, $Schema, [string]$File, [string]$Prefix)

	foreach ($p in $Layer.PSObject.Properties) {
		$key = if ($Prefix) { "$Prefix.$($p.Name)" } else { $p.Name }
		$known = @($Schema.PSObject.Properties.Name)
		if ($p.Name -notin $known) {
			throw "${File}: unknown key '$key'. Known keys here: $($known -join ', '). See CONFIGURATION.md of issue-kit."
		}
		$expected = Get-ValueKind $Schema.($p.Name)
		$actual = Get-ValueKind $p.Value
		if ($expected -ne $actual) { throw "${File}: key '$key' must be $(Add-Article $expected); found $(Add-Article $actual)." }
		if ($expected -eq 'object') { Assert-Layer -Layer $p.Value -Schema $Schema.($p.Name) -File $File -Prefix $key; continue }
		if ($expected -eq 'list') {
			foreach ($item in @($p.Value)) {
				if ($item -isnot [string] -or -not $item) { throw "${File}: key '$key' must be a list of non-empty texts." }
			}
		}
		if ($expected -eq 'text') { Assert-TextValue -Key $key -Value $p.Value -File $File }
	}
}

function Assert-TextValue([string]$Key, [string]$Value, [string]$File) {
	if ($Key -in $script:requiredTextKeys -and -not $Value) { throw "${File}: key '$Key' must not be empty." }
	if ($Key -in $script:regexKeys -and $Value) {
		try { $null = [regex]::new($Value) }
		catch { throw "${File}: key '$Key' is not a valid regular expression ('$Value'): $($_.Exception.Message)" }
	}
	if ($script:placeholders.ContainsKey($Key) -and $Value) {
		foreach ($token in $script:placeholders[$Key]) {
			if (-not $Value.Contains($token)) { throw "${File}: key '$Key' must contain $token; found '$Value'." }
		}
	}
}

function Merge-Layer($Target, $Layer) {
	foreach ($p in $Layer.PSObject.Properties) {
		if ($p.Value -is [System.Management.Automation.PSCustomObject]) { Merge-Layer -Target $Target[$p.Name] -Layer $p.Value }
		else { $Target[$p.Name] = ConvertTo-OrderedTree $p.Value }
	}
}

function Get-IssueKitRepoRoot {
	<# Returns the root of the git repository of the given folder, or the folder itself outside a repository. #>
	param([string]$Path = (Get-Location).Path)
	$root = & git -C $Path rev-parse --show-toplevel 2>$null
	if ($LASTEXITCODE -eq 0 -and $root) { return [IO.Path]::GetFullPath(([string]($root | Select-Object -First 1)).Trim()) }
	return [IO.Path]::GetFullPath($Path)
}

function Get-IssueKitUserConfigFile {
	$dir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
	return Join-Path $dir $script:configFileName
}

function Get-IssueKitConfig {
	<#
	.SYNOPSIS
		Returns the merged configuration and the files it came from.
	.OUTPUTS
		An object with Config (ordered dictionary), Sources (files read, in order), RepoFile (path of layer 3) and
		HasRepoFile (whether layer 3 exists).
	#>
	[CmdletBinding()]
	param(
		[string]$RepoRoot = (Get-IssueKitRepoRoot),
		[string]$DefaultsFile = $script:defaultsFile,
		[string]$UserFile = (Get-IssueKitUserConfigFile),
		[string]$RepoFile
	)

	if (-not $RepoFile) { $RepoFile = Join-Path $RepoRoot $script:configFileName }
	if (-not (Test-Path -LiteralPath $DefaultsFile)) { throw "Defaults file not found: $DefaultsFile" }
	$schema = Read-JsonFile $DefaultsFile
	$config = ConvertTo-OrderedTree $schema
	$sources = [System.Collections.Generic.List[string]]::new()
	$sources.Add($DefaultsFile)

	foreach ($file in @($UserFile, $RepoFile)) {
		if (-not $file -or -not (Test-Path -LiteralPath $file)) { continue }
		$layer = Read-JsonFile $file
		Assert-Layer -Layer $layer -Schema $schema -File $file -Prefix ''
		Merge-Layer -Target $config -Layer $layer
		$sources.Add($file)
	}

	return [pscustomobject]@{
		Config      = $config
		Sources     = [string[]]$sources
		RepoFile    = $RepoFile
		HasRepoFile = (Test-Path -LiteralPath $RepoFile)
	}
}

function Get-IssueKitValue {
	<# Returns the value of a dotted key ("commands.build") from a merged configuration. #>
	param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Key)
	$node = $Config
	foreach ($part in $Key.Split('.')) {
		if ($node -isnot [System.Collections.IDictionary] -or -not $node.Contains($part)) { throw "Unknown configuration key '$Key'." }
		$node = $node[$part]
	}
	return , $node
}

function ConvertTo-BranchRegex {
	<#
	.SYNOPSIS
		Turns a branch pattern ("{n}-{slug}", "{first}-{last}-{slug}") into an anchored regular expression.
	.DESCRIPTION
		{n}, {first} and {last} become named groups of digits; {slug} becomes one or more characters.
	#>
	param([Parameter(Mandatory)][string]$Pattern)
	$regex = [regex]::Escape($Pattern)
	$regex = $regex.Replace('\{n}', '(?<n>\d+)').Replace('\{first}', '(?<first>\d+)').Replace('\{last}', '(?<last>\d+)').Replace('\{slug}', '.+')
	return "^$regex$"
}

Export-ModuleMember -Function Get-IssueKitConfig, Get-IssueKitValue, Get-IssueKitRepoRoot, Get-IssueKitUserConfigFile, ConvertTo-BranchRegex
