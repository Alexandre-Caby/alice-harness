# Text-to-speech module

Speech synthesis behind an OpenAI-compatible `/v1/audio/speech`, by a C engine for Qwen3-TTS running on the CPU.
An optional cloned voice (`.qvoice`, `ALICE_TTS_VOICE_FILE`) stays outside the repository.

| Part | Source | License |
|---|---|---|
| Engine | [gabriele-mastrapasqua/qwen3-tts](https://github.com/gabriele-mastrapasqua/qwen3-tts), commit in `versions.lock` | MIT |
| Model | [Qwen/Qwen3-TTS-12Hz-0.6B-Base](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base), revision and hash in `versions.lock` | Apache-2.0 |

Engine versions before September 2026 read JSON escapes literally: Open WebUI sends `\u00e9` for `é`, and those
versions spoke it as "u zero zero e nine". `QWEN_SERVER_STRICT=0` lets Open WebUI's voice name fall back to the
loaded voice. Measured on the reference machine: a 4.7 s sentence in 3.2 s.
