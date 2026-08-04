# Reading probe output

`lmstack-probe` emits one JSON object. Every field is best-effort: a
missing tool yields `null`, never an error, because the script is designed to
run against a host that has not been bootstrapped yet.

## Fields

| Path | Meaning |
|---|---|
| `os.id` / `os.version` | From `/etc/os-release`. Bootstrap adds the Docker apt repo for `os.version`, so a non-Debian family host will fail there. |
| `os.kernel` | The amdgpu and NVIDIA driver both live in the kernel; a mismatch between kernel and driver shows up here first. |
| `gpu.vendor` | `nvidia`, `amd`, or `none`. Decides the host role and nothing else. |
| `gpu.vram_gib` | NVIDIA discrete: total board memory from `nvidia-smi`. NVIDIA unified (Grace Blackwell, Grace Hopper, Jetson): the unified pool via `libcuda.cuMemGetInfo`, because `nvidia-smi` returns `N/A` for `memory.total` on those parts. AMD: `mem_info_vram_total`, which on an APU is a small carve-out. |
| `gpu.gtt_gib` | AMD only. The share of system RAM the GPU may map, from `mem_info_gtt_total`. **On an APU this is the number that matters.** When the sysfs nodes are unreadable — a restricted container, an amdgpu that has not initialised its info files yet — the probe falls back to the largest `MEMORY_HEAP_DEVICE_LOCAL_BIT` heap `vulkaninfo` reports, and writes that number here. It is the deterministic ceiling for GPU-visible memory. |
| `gpu.driver` | NVIDIA driver version, or the literal `amdgpu`. Empty on NVIDIA means no usable driver. |
| `dri_nodes` | The render nodes containers can be given. Empty on an AMD host is fatal. |
| `vulkan.present` | Whether `vulkaninfo` exists. Bootstrap installs it; absence before bootstrap is expected. |
| `vulkan.device` | The device Vulkan actually found. Absence *after* bootstrap means CPU fallback. |
| `docker.usable` | `docker info` succeeded as this user. False with `present: true` is almost always missing docker group membership. |
| `sudo` | `root`, `passwordless`, `password`, or `unknown`. Decides whether bootstrap needs `-K`. |

## Things the numbers do not mean

**`vram_gib: 2` on a laptop is not a 2 GiB GPU.** AMD APUs carve out a token
dedicated pool — 512 MiB or 2 GiB, set in the BIOS — and allocate everything else
through GTT from system RAM. A machine reporting `vram_gib: 2, gtt_gib: 29` can
comfortably serve a 7B model. `lmstack-classify` takes the larger of the two for this
reason. Reading the VRAM figure alone declares most AMD laptops unsupported.

**`vram_gib: null` on a detected NVIDIA GPU is a probe bug, not a zero.** It
means `nvidia-smi --query-gpu=memory.total` returned `N/A` (Grace Blackwell,
Grace Hopper, Jetson) and the `libcuda.so` fallback also could not answer —
usually because CUDA is not installed. Install CUDA (or the NVIDIA container
runtime, which drops it in) and re-probe. Do not read `null` as 0 GiB and
declare the host unsupported; that once called a DGX Spark a zero-VRAM box.

**`gtt_gib` on a discrete card is not additional capacity.** A dGPU also reports
a GTT budget, but spilling into it means transferring weights over PCIe per
token. `lmstack-classify` takes the max, which on a dGPU is the real VRAM. Do not add
the two together.

**`docker.runtimes` without `nvidia` is not a failure.** Bootstrap registers the
NVIDIA runtime. It matters only if the user says bootstrap already ran.

## Probing a remote host

The script is self-contained on purpose:

```bash
ssh user@box 'bash -s' < "$(command -v lmstack-probe)"
```

Nothing is copied to the target and nothing is left behind. It needs bash and
coreutils, and degrades gracefully without `lspci`, `nvidia-smi`, `vulkaninfo`
or `docker`.

## When the probe finds nothing

`gpu.vendor: none` with a populated `dri_nodes` list usually means an Intel iGPU.
There is no host role for it. llama.cpp's Vulkan backend does run on Intel Arc,
so a `h3-intel` role is a reasonable contribution, but do not point the user at
`h2-amd` — its bootstrap installs the Mesa AMD stack and asserts on an amdgpu
render node.

`gpu.vendor: nvidia` with `driver: null` means `nvidia-smi` is installed but not
answering. Nine times out of ten the driver was updated without a reboot and the
kernel module no longer matches the userspace library.
