# After the user's yes, the workspace is a git repository with a commit that holds the facts and the master CV.
param([string]$Workspace, [string]$AnswerFile)
$n = git -C $Workspace rev-list --count HEAD 2>$null
if ($LASTEXITCODE -ne 0 -or [int]$n -lt 1) { Write-Output 'no commit'; exit 1 }
$files = git -C $Workspace ls-files
foreach ($f in 'MyProfile/candidate_facts.md', 'MyProfile/cv/cv_master.yaml') {
  if ($files -notcontains $f) { Write-Output "$f is not committed"; exit 1 }
}
Write-Output "$n commit(s)"
