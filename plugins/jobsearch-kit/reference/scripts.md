# Scripts

The scripts live in the plugin's `scripts/` folder. In a skill, call them as `${CLAUDE_SKILL_DIR}/../../scripts/<name>`
and run them from the workspace root.

| Script | Run with | What it does |
|---|---|---|
| `cv.js <profile.yaml> [--no-docx]` | `node` | Builds a CV from the master and a profile: checks the wording rules, writes `<output>.md` and `<output>.docx` next to the profile. The profile and master formats are documented at the top of the script |
| `cv.js --lint <file.md> ...` | `node` | Checks Markdown text against `cv_rules.yaml`; builds nothing |
| `build-cv.js <content.json> <out.docx>` | `node` | Renders a CV from an older `cv_content.json` |
| `build-letter.js <letter.md>` | `node` | Builds a letter `.docx` from Markdown with front matter (`output`, `date`) |
| `export-pdf.ps1 -Docx <file.docx>` | `pwsh -File` | Exports a PDF next to the `.docx` with Word and keeps the hyperlinks; prints the page count and the links |
| `render-preview.ps1 -Docx <file.docx> [-OutDir <dir>]` | `pwsh -File` | Renders the `.docx` to PDF and one PNG per page; default output `%TEMP%\jobsearch\preview\page*.png` |
| `pdf-to-png.ps1 -Pdf <file.pdf> -OutDir <dir>` | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` | Renders a PDF to `page*.png` |
| `transcribe.py <audio> <out_prefix> [options]` | the whisper venv Python | Transcribes a recording locally with faster-whisper; options are documented at the top of the script |
| `install-deps.ps1` | `pwsh -File` | Installs the npm packages outside the plugin |
| `install-whisper.ps1` | `pwsh -File` | Creates the whisper venv outside the plugin |

## Shells

- Write paths in commands with forward slashes (`<folder>/<file>.docx`). The scripts accept them, and the Bash tool
  treats a backslash as an escape character.
- Run the `.ps1` scripts with `pwsh -File` (or `powershell.exe -File` where the table says so). This works from the
  PowerShell tool and from the Bash tool.

## Workspace root

The scripts find the workspace root in this order: `--root <dir>`, the `JOBSEARCH_ROOT` environment variable, the
nearest folder upwards (from the current directory or the input file) that contains `MyProfile/cv/cv_master.yaml`,
the current directory. If `cv.js` prints "no wording rules", it did not find the workspace: pass `--root`.

## Dependencies

| What | Folder | Override |
|---|---|---|
| npm packages (`docx`, `yaml`) | `%LOCALAPPDATA%\ai-plugins\jobsearch-kit\node_modules` | `JOBSEARCH_DEPS` |
| whisper venv and models | `%LOCALAPPDATA%\ai-plugins\jobsearch-kit\whisper` | `JOBSEARCH_WHISPER` |

- If a script reports a missing npm package, run `pwsh -File "${CLAUDE_SKILL_DIR}/../../scripts/install-deps.ps1"`.
- If the whisper venv does not exist, run `pwsh -File "${CLAUDE_SKILL_DIR}/../../scripts/install-whisper.ps1"`.
- The whisper Python is `<whisper folder>\.venv\Scripts\python.exe`.
- If an install script gets a folder other than the default (`-DepsDir`, `-WhisperDir`), it sets the matching user
  environment variable itself and prints it. Tell the user that only new terminals and sessions see the variable.

## Environment

- Windows with Microsoft Word (used through COM), Node, PowerShell 7 (`pwsh`) and Windows PowerShell 5.1.
- Run the Word step in pwsh: from Windows PowerShell 5.1, Word's `SaveAs2` hangs in a hidden instance. The
  PDF-to-PNG step needs WinRT and therefore Windows PowerShell 5.1; `render-preview.ps1` handles the split.
- Transcription needs `uv` and an NVIDIA GPU with CUDA 12 (or `--device cpu`, much slower).
- To read a `.docx` without Word, unzip `word/document.xml` and strip the tags.
