<#
.SYNOPSIS
  Creates the Python environment for scripts\transcribe.py outside the plugin.

.DESCRIPTION
  The plugin folder is replaced on every plugin install, and a workspace may live in a synced folder such as
  OneDrive, so the virtual environment and the Whisper models are kept elsewhere:

    pwsh -File scripts\install-whisper.ps1 [-WhisperDir <folder>]

  The default WhisperDir is the JOBSEARCH_WHISPER environment variable, else
  %LOCALAPPDATA%\ai-plugins\jobsearch-kit\whisper. If WhisperDir is not the default folder, the script sets the
  user environment variable JOBSEARCH_WHISPER to it, so that transcribe.py finds the environment. To reuse an
  existing environment without reinstalling, run the script with -WhisperDir <that folder>: uv keeps what is there.

  Needs uv (Python 3.13 is installed by uv if missing). Installs faster-whisper with the CUDA 12 libraries for
  NVIDIA GPUs. av is pinned below 16 because faster-whisper 1.2.1 passes an argument that newer PyAV removed.
  The model (large-v3, about 3 GB) is downloaded into WhisperDir\models on the first transcribe.py run.
#>
param(
  [string]$WhisperDir = $(if ($env:JOBSEARCH_WHISPER) { $env:JOBSEARCH_WHISPER } else { Join-Path $env:LOCALAPPDATA 'ai-plugins\jobsearch-kit\whisper' })
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'folder-variable.ps1')

New-Item -ItemType Directory -Force (Join-Path $WhisperDir 'models') | Out-Null
$venv = Join-Path $WhisperDir '.venv'
& uv venv $venv --python 3.13 --allow-existing
if ($LASTEXITCODE -ne 0) { throw "uv venv failed with exit code $LASTEXITCODE" }
& uv pip install --python (Join-Path $venv 'Scripts\python.exe') faster-whisper 'av<16' nvidia-cublas-cu12 'nvidia-cudnn-cu12==9.*'
if ($LASTEXITCODE -ne 0) { throw "uv pip install failed with exit code $LASTEXITCODE" }
Write-Output "Whisper environment ready in $venv"
Sync-FolderVariable -Name 'JOBSEARCH_WHISPER' -Folder $WhisperDir -Default (Join-Path $env:LOCALAPPDATA 'ai-plugins\jobsearch-kit\whisper')
