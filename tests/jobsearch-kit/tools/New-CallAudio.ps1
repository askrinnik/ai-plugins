<#
.SYNOPSIS
  Synthesizes a two-speaker call recording (MP3 or WAV) from a dialogue file, with Windows speech voices.

.DESCRIPTION
  Requires Windows PowerShell 5.1 (powershell.exe): it uses the WinRT Windows.Media.SpeechSynthesis and
  Windows.Media.Transcoding APIs, which PowerShell 7 cannot load. The OneCore voices of that API include a male and
  a female voice for English and Russian. No other tool (ffmpeg and the like) is needed.

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\jobsearch-kit\tools\New-CallAudio.ps1 `
      -Dialogue tests\jobsearch-kit\materials\call\dialogue.tsv -Out <file.mp3>

  Dialogue format: one line per utterance, tab-separated: speaker, language (en or ru), text.
  -Voices maps "<speaker>:<language>" to a voice name; the default fits the fixture call (Anna female, Jordan male).
  Output: the utterances with a pause between them. The extension of -Out picks the format: .mp3 (mono, encoded by
  the Windows MP3 encoder at -Mp3BitrateKbps, default 48) or .wav (mono 16-bit PCM). Every utterance must come out in
  the same audio format; the script stops if it does not.
#>
param(
  [Parameter(Mandatory = $true)][string]$Dialogue,
  [Parameter(Mandatory = $true)][string]$Out,
  [hashtable]$Voices = @{
    'Anna:en'   = 'Microsoft Zira'
    'Anna:ru'   = 'Microsoft Irina'
    'Jordan:en' = 'Microsoft David'
    'Jordan:ru' = 'Microsoft Pavel'
  },
  [int]$PauseMs = 450,
  [int]$Mp3BitrateKbps = 48
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]

$asTaskOp = [System.WindowsRuntimeSystemExtensions].GetMethods() |
  Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } |
  Select-Object -First 1
function Await($operation, [Type]$resultType) {
  $task = $asTaskOp.MakeGenericMethod($resultType).Invoke($null, @($operation))
  $task.Wait()
  $task.Result
}

$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$all = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices

# Returns the WAV bytes of one utterance.
function Speak([string]$voiceName, [string]$text) {
  $voice = $all | Where-Object { $_.DisplayName -eq $voiceName } | Select-Object -First 1
  if (-not $voice) { throw "Voice not installed: $voiceName" }
  $synth.Voice = $voice
  $stream = Await ($synth.SynthesizeTextToStreamAsync($text)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
  $size = [uint32]$stream.Size
  $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
  $null = Await ($reader.LoadAsync($size)) ([uint32])
  $bytes = New-Object byte[] $size
  $reader.ReadBytes($bytes)
  $reader.Dispose(); $stream.Dispose()
  , $bytes
}

# Splits a RIFF/WAVE file into its "fmt " chunk and its PCM data.
function Split-Wav([byte[]]$b) {
  $pos = 12; $fmt = $null; $data = $null
  while ($pos + 8 -le $b.Length) {
    $id = [Text.Encoding]::ASCII.GetString($b, $pos, 4)
    $len = [BitConverter]::ToInt32($b, $pos + 4)
    if ($id -eq 'fmt ') { $fmt = $b[($pos + 8)..($pos + 7 + $len)] }
    if ($id -eq 'data') { $data = New-Object byte[] $len; [Array]::Copy($b, $pos + 8, $data, 0, $len) }
    $pos += 8 + $len + ($len % 2)
  }
  if (-not $fmt -or -not $data) { throw 'Unexpected WAV layout from the synthesizer' }
  @{ Fmt = [byte[]]$fmt; Data = $data }
}

$lines = Get-Content -LiteralPath $Dialogue -Encoding UTF8 | Where-Object { $_.Trim() }
$fmt = $null
$pcm = New-Object System.IO.MemoryStream
foreach ($line in $lines) {
  $speaker, $lang, $text = $line -split "`t", 3
  $key = "${speaker}:${lang}"
  if (-not $Voices.ContainsKey($key)) { throw "No voice for $key" }
  $wav = Split-Wav (Speak $Voices[$key] $text)
  if ($null -eq $fmt) { $fmt = $wav.Fmt }
  elseif ([Convert]::ToBase64String($fmt) -ne [Convert]::ToBase64String($wav.Fmt)) { throw "Audio format differs for: $key" }
  $pcm.Write($wav.Data, 0, $wav.Data.Length)
  $byteRate = [BitConverter]::ToInt32($fmt, 8)
  $blockAlign = [BitConverter]::ToInt16($fmt, 12)
  $silence = [int]($byteRate * $PauseMs / 1000)
  $silence -= $silence % $blockAlign
  $pcm.Write((New-Object byte[] $silence), 0, $silence)
}

$data = $pcm.ToArray()
$outFull = [IO.Path]::GetFullPath($Out)
$ext = [IO.Path]::GetExtension($outFull).ToLowerInvariant()
if ($ext -notin '.mp3', '.wav') { throw "-Out must end in .mp3 or .wav: $Out" }
# For MP3 the WAV is written to a temporary file first and then encoded.
$wavPath = if ($ext -eq '.wav') { $outFull } else { Join-Path ([IO.Path]::GetTempPath()) ("call-audio-{0}.wav" -f [guid]::NewGuid()) }

$fs = [IO.File]::Create($wavPath)
$w = New-Object IO.BinaryWriter($fs)
$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](4 + 8 + $fmt.Length + 8 + $data.Length))
$w.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
$w.Write([Text.Encoding]::ASCII.GetBytes('fmt ')); $w.Write([int]$fmt.Length); $w.Write($fmt)
$w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$data.Length); $w.Write($data)
$w.Close()

if ($ext -eq '.mp3') {
  $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
  $null = [Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType = WindowsRuntime]
  $null = [Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType = WindowsRuntime]
  $asTaskProgress = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncActionWithProgress`1' } |
    Select-Object -First 1
  try {
    $outDir = Split-Path $outFull -Parent
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $src = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($wavPath)) ([Windows.Storage.StorageFile])
    $folder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($outDir)) ([Windows.Storage.StorageFolder])
    $dst = Await ($folder.CreateFileAsync([IO.Path]::GetFileName($outFull), [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
    # Speech needs no stereo and no high bitrate. The Windows MP3 encoder takes 32, 44.1 or 48 kHz input.
    $profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp3([Windows.Media.MediaProperties.AudioEncodingQuality]::Low)
    $profile.Audio.ChannelCount = 1
    $profile.Audio.SampleRate = 32000
    $profile.Audio.Bitrate = [uint32]($Mp3BitrateKbps * 1000)
    $transcoder = New-Object Windows.Media.Transcoding.MediaTranscoder
    $prepared = Await ($transcoder.PrepareFileTranscodeAsync($src, $dst, $profile)) ([Windows.Media.Transcoding.PrepareTranscodeResult])
    if (-not $prepared.CanTranscode) { throw "MP3 encoding is not available: $($prepared.FailureReason)" }
    $asTaskProgress.MakeGenericMethod([double]).Invoke($null, @($prepared.TranscodeAsync())).Wait()
  }
  finally {
    Remove-Item -LiteralPath $wavPath -ErrorAction SilentlyContinue
  }
}

$seconds = [math]::Round($data.Length / [BitConverter]::ToInt32($fmt, 8), 1)
$size = [math]::Round((Get-Item -LiteralPath $outFull).Length / 1KB)
Write-Output "Wrote $outFull ($($lines.Count) utterances, $seconds s, $size KB)"
