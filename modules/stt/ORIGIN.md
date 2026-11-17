# Speech-to-text module

Two containers on the internal network: NVIDIA's NeMo-Speech.cpp server running Nemotron 3.5 Transcribe on the GPU,
and a small shim (`shim/server.py`) that gives it an OpenAI-compatible `/v1/audio/transcriptions`, converts any audio
format (browser recordings included) and passes the vocabulary of `terms.txt` as context terms.

| Part | Source | License |
|---|---|---|
| Server | [NVIDIA/NeMo-Speech.cpp](https://github.com/NVIDIA/NeMo-Speech.cpp), commit in `versions.lock` | Apache-2.0 |
| Model | [Nemotron 3.5 Transcribe 30B-A4B](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B), GGUF from [AtomicChat](https://huggingface.co/AtomicChat/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B-GGUF), hashes in `versions.lock` | OpenMDW-1.1 |
| Shim | this repository | MIT |
| Audio conversion | FFmpeg (Debian package) | LGPL/GPL |

The vocabulary file (`$ALICE_DATA_DIR/stt/terms/terms.txt`) is personal: names of people, places and projects. It is
read on every request, so editing it needs no restart. NVIDIA reports a named-entity error rate falling from 12.2 %
to 2.2 % with fine-grained context terms. Measured on the reference machine: about 0.7 s per sentence.
