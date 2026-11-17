# Images module

Image generation and editing behind an OpenAI-compatible API (`/v1/images/generations`, `/v1/images/edits`), by the
stable-diffusion.cpp server compiled for the machine's backend.

| Part | Source | License |
|---|---|---|
| Server | [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp), commit in `versions.lock` | MIT |
| Model | FLUX 3 Image Klein, GGUF from [AtomicChat](https://huggingface.co/AtomicChat/FLUX-3-Image-Klein-GGUF) (diffusion model, Qwen3-VL-4B text encoder, VAE), hashes in `versions.lock` | FLUX Kommunity License |

Settings: 4 steps (the distilled model is made for it; 16 steps took three times longer for the same quality at
768×768) and a random seed on every request (the server's default seed is fixed, so "regenerate" returned the very
same image). Measured on the reference machine: 512×512 in 4 s, 768×768 in 13 s, 1920×1088 in 61 s.
The model understands English prompts much better than other languages: `soul.txt` adds that rule to the soul.
