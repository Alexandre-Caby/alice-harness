# Decision module

Judges, for Open WebUI's approval gate, whether a tool call needs your approval. Two containers on the internal core
network: the decision model in the official llama.cpp server, and a small adapter (`adapter.py`) that translates Open
WebUI's Decisions API into llama.cpp's System One API and enforces the fixed floor (`allowlist.txt`). Tools marked
`pass` there skip the model: the workspace (walled, backed up every night) and reads of the person's own data.

## Sources

| Part | Source | License |
|---|---|---|
| Server | [llama.cpp](https://github.com/ggml-org/llama.cpp), official image `server-vulkan`, pinned by digest in `versions.lock` | MIT |
| Default model | [OpenJev](https://huggingface.co/openjev/openjev), GGUF by [ggml-org](https://huggingface.co/ggml-org/OpenJev-GGUF), `OpenJev-Q4_K_M.gguf` at a pinned revision and SHA-256 | CC BY-NC 4.0 (non-commercial) |
| Adapter | this repository | MIT |

## Measured on the reference machine (AMD Ryzen AI Max+ 395, Vulkan)

`cases.json` holds 82 labeled calls, mostly English (42 must pass, 40 must ask): the last four send a file to the
machine's own speech-to-text (must pass) or off the machine (must ask). The first row is measured on them; the
others come from an earlier set of 67 calls (35 and 32), with the same calls translated into French (not included) as
a control set.

| Model and method | GPU memory | Risky calls let through | Harmless calls asked | Median time |
|---|---|---|---|---|
| OpenJev Q4_K_M, six criteria, threshold 0.5 (default) | 23 GB | 0 / 40 (earlier set: 0 / 32, English and French) | 1 / 42 | 2.7 s |
| OpenJev Q4_K_M, eight criteria, threshold 0.8 | 23 GB | 3 / 32 in English, 0 in French | 1 / 35 | 3.2 s |
| OpenJev Q4_K_M, one policy question | 23 GB | the safe threshold moves between data sets | | 1.0 s |
| LiquidAI d1-2B Q8_0, eight criteria | 3.9 GB | 1 to 3 at 0.5, overlapping scores | | 0.33 s |
| LiquidAI d1-2B Q8_0, one policy question | 3.9 GB | 7 to 11 at 0.5 | | 0.06 s |
| LiquidAI d1-3B, vllm-sr d3 (one question) | 5.1 GB, 24.6 GB | 10, 2 at 0.5 | | 0.10 s, 1.1 s |
| magnitudedev d3-ultra | | does not load in the pinned llama.cpp server | | |

The data question names what counts as leaving: "to another computer, address or person" made the judge ask for
every upload to the machine's own services (0.89 and 0.92 on the two speech-to-text calls; now 0.13 and 0.16), while
the calls that send off the machine stay high (0.98, 0.71).

With six criteria at 0.5, the lowest risky score is 0.510 on the current set (0.652 in English and 0.809 in French on
the earlier one): the margin above the threshold is thin. Re-run `test.py` after any change of model, quantization or
criteria. `test.py` plays only the cases of judged tools (26 of the 82); the whole set still compares judges.

## Notes

- Only GGUF files that carry the decision metadata (`<arch>.decision.*`, the `systemone` chat template) work with
  llama.cpp's System One API. The publisher's own GGUF (`openjev/openjev-GGUF`) has none, and the server answers
  "This model is not a decision model".

- The model is kept loaded. A model that sleeps when idle answers its first request after a pause too late for Open
  WebUI's limit, which turns every first tool call into an approval request.
- Open WebUI waits 5 s for a decision; the approval patch raises it to 15 s. Measured on the reference machine: a call
  that carries code takes about 4.5 s while the chat model shares the GPU, and one call in ten went past 5 s, so the
  person was asked for no reason (safe, but it blocked the work).
- The model weights are not redistributed; `build.sh` downloads them from the publisher and checks the hash.
