<#
.SYNOPSIS
  Shared by install-deps.ps1 and install-whisper.ps1: keeps a folder environment variable in step with the folder
  that the install script used.

.DESCRIPTION
  Dot-source it, then call Sync-FolderVariable. The other jobsearch-kit scripts read the folder from the
  environment variable, else from the default folder. So:
  - If the install folder is not the default one, the function sets the variable for the current user (and for
    the current process) and says so in the output. No administrator rights are needed.
  - If the install folder is the default one and the variable points elsewhere, the function only warns: the
    scripts would still use the other folder.
#>

function Sync-FolderVariable {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Folder,
    [Parameter(Mandatory = $true)][string]$Default
  )
  $full = [IO.Path]::GetFullPath($Folder).TrimEnd('\')
  $defaultFull = [IO.Path]::GetFullPath($Default).TrimEnd('\')
  $current = [Environment]::GetEnvironmentVariable($Name, 'User')

  if ($full -ieq $defaultFull) {
    if ($current -and ($current.TrimEnd('\') -ine $full)) {
      Write-Warning ("$Name (user environment) points to $current, so the scripts use that folder, not $full. " +
        "To use the default folder, remove the variable: [Environment]::SetEnvironmentVariable('$Name', [NullString]::Value, 'User')")
    }
    return
  }

  if ($current -and ($current.TrimEnd('\') -ieq $full)) {
    Write-Output "$Name already points to $full (user environment)."
    return
  }

  [Environment]::SetEnvironmentVariable($Name, $full, 'User')
  Set-Item -Path "Env:$Name" -Value $full
  $was = if ($current) { " (was $current)" } else { '' }
  Write-Output "$Name set to $full (user environment)$was. New terminals and Claude Code sessions see it."
}
