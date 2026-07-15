#!/usr/bin/env bash
##############################################################################
# voice2text – přepis audia na text pomocí Whisper (faster-whisper, CPU).
#
# Použití:
#   voice2text <audio_soubor> [model] [jazyk]
#     model:  tiny | base | small | medium | large-v3   (výchozí: small)
#     jazyk:  cs | en | ... | auto                      (výchozí: cs)
#
# Příklad:
#   voice2text ~/workspace/nahravka.m4a small cs
#
# Poznámka k "hlasovému ovládání":
#   Server / kontejner nemá mikrofon. Postup je: nahrané audio nakopírujte
#   do ~/workspace, přepište přes voice2text a text předejte agentovi.
#   Modely se stahují jednou do ~/.cache/whisper (trvalý volume).
##############################################################################
set -euo pipefail

AUDIO="${1:?Použití: voice2text <audio_soubor> [model] [jazyk]}"
MODEL="${2:-small}"
LANG="${3:-cs}"

if [ ! -f "$AUDIO" ]; then
  echo "Soubor neexistuje: $AUDIO" >&2
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
