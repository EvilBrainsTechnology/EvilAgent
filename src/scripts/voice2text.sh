#!/usr/bin/env bash
##############################################################################
# voice2text – transcribe audio to text using Whisper (faster-whisper, CPU).
#
# Usage:
#   voice2text <audio_file> [model] [language]
#     model:     tiny | base | small | medium | large-v3   (default: small)
#     language:  cs | en | ... | auto                      (default: cs)
#
# Example:
#   voice2text ~/workspace/recording.m4a small cs
#
# Note on "voice control":
#   The server / container has no microphone. The workflow is: copy the
#   recorded audio into ~/workspace, transcribe it with voice2text, and
#   pass the resulting text to an agent.
#   Models are downloaded once to ~/.cache/whisper (persistent volume).
##############################################################################
set -euo pipefail

if [ ! -x /opt/whisper-venv/bin/python ]; then
  echo "Whisper is not installed in this image." >&2
  echo "Rebuild with Whisper enabled: make update" >&2
  exit 1
fi

AUDIO="${1:?Usage: voice2text <audio_file> [model] [language]}"
MODEL="${2:-small}"
LANG="${3:-cs}"

if [ ! -f "$AUDIO" ]; then
  echo "File not found: $AUDIO" >&2
  exit 1
fi

exec /opt/whisper-venv/bin/python - "$AUDIO" "$MODEL" "$LANG" <<'PY'
import sys
from faster_whisper import WhisperModel

audio, model_name, lang = sys.argv[1], sys.argv[2], sys.argv[3]
model = WhisperModel(
    model_name, device="cpu", compute_type="int8",
    download_root="/home/agent/.cache/whisper",
)
segments, _info = model.transcribe(
    audio, language=None if lang == "auto" else lang, vad_filter=True,
)
for seg in segments:
    print(seg.text.strip())
PY
