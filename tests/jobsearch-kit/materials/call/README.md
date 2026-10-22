# Test call: Nordwind Pay recruiter screening (fictional)

A recruiter call of about 2.5 minutes: English first, then Russian from about 01:29. Speakers: Anna (recruiter,
female voice) and Jordan (candidate, male voice).

| File | What it is |
|---|---|
| `dialogue.tsv` | The script: one utterance per line, `speaker<TAB>language<TAB>text`. Source of the synthetic audio |
| `call-synthetic-en-ru.mp3` | Generated from `dialogue.tsv` by `../../tools/New-CallAudio.ps1` with Windows voices: Anna = Zira (en) and Irina (ru), Jordan = David (en) and Pavel (ru). Mono MP3, 48 kbps, 152 s, about 0.9 MB |
| `call-live-voice-en-ru.mp3` | The same script read aloud by one person who changed the voice for each speaker. Recorded for the live check of 2026-10-22 |

Regenerate the synthetic audio (Windows PowerShell 5.1):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\jobsearch-kit\tools\New-CallAudio.ps1 -Dialogue tests\jobsearch-kit\materials\call\dialogue.tsv -Out tests\jobsearch-kit\materials\call\call-synthetic-en-ru.mp3
```

The script needs no other tool: it encodes the MP3 with the encoder built into Windows. With `-Out <file>.wav` it
writes uncompressed audio instead (about 5 MB).

## What the process-call skill must notice (ground truth)

| In the call | Why it matters | Expected result |
|---|---|---|
| Jordan: "I set up our clusters myself" (Kubernetes) | Contradicts the facts: working knowledge only, never set up a cluster | Listed as the main risk in "nuances and risks" of the summary; facts not changed |
| Jordan: "around 5,500 euros" | The facts and `application_defaults.yaml` say 5000 | Named as a discrepancy and asked about; facts not changed without confirmation |
| Team lead Marek; invitation "by Friday" | New person and a deadline | Marek added to the company notes; the deadline in "next steps" with a date |
| Language switch to Russian | Two-language mode | `--languages en,ru`; the Russian part of the transcript stays in Russian; the switch time checked against the text |
| Team of six developers and one tester; office Tuesday to Thursday; on-call one week in six, paid | Company facts | In the side notes or the company notes |

The user's answers in the live check: the Kubernetes claim was an exaggeration, the salary stays 5000, the start is
one month after an offer. The skill must leave `candidate_facts.md` unchanged.

## Known transcription effects

- Synthetic audio: automatic language detection put the switch at 01:30 (real: about 01:29), and the English pass
  translated the first Russian utterance into English. A correct run notices this and reruns with `--switch`.
- Live voice: detection put the switch at 01:00 (real: 01:25); the skill reran with `--switch 00:01:25`. Whisper
  lost the start of the start-date answer and garbled "one week in six"; the skill marked both as unclear.
