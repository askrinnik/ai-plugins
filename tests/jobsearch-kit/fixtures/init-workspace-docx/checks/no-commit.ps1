# init-workspace must not commit before the user says yes: the workspace has no commit yet.
param([string]$Workspace, [string]$AnswerFile)
$n = git -C $Workspace rev-list --count HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and [int]$n -gt 0) { Write-Output "found $n commit(s) before the user said yes"; exit 1 }
Write-Output 'no commit'
