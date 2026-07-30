#!/usr/bin/env bash
# Report what a candidate GPU host actually has, as JSON on stdout.
#
#   bash probe-host.sh                       # the machine you are on
#   ssh user@box 'bash -s' < probe-host.sh   # a remote candidate
#
# Read-only. Installs nothing, writes nothing, needs no privileges. It is meant
# to run against a host that has not been bootstrapped yet, so it assumes only
# coreutils and a POSIX shell — no jq, no python, no ansible. Every probe is
# guarded; a missing tool produces a null field, never an error.
#
# The output feeds classify.py on the control host. Nothing here is written to
# .stacklog directly; the skill logs a summary, and the raw probe can contain a
# serial number or a hostname that has no business in a change log.

set -uo pipefail

# ---------------------------------------------------------------------------
# JSON emission without jq. Only strings need escaping, and only for the
# characters JSON forbids raw: backslash, quote, and control bytes.
jstr() {
  if [[ -z "${1:-}" ]]; then
    printf 'null'
    return
  fi
  printf '"%s"' "$(printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

jnum() {
  if [[ "${1:-}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then printf '%s' "$1"; else printf 'null'; fi
}

jbool() { if [[ "${1:-}" == "true" ]]; then printf 'true'; else printf 'false'; fi; }

# A JSON array of strings from newline-separated stdin.
jarray() {
  local first=1 line
  printf '['
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ $first -eq 1 ]] || printf ', '
    jstr "$line"
    first=0
  done
  printf ']'
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# OS and kernel
os_id=""; os_version=""; os_pretty=""
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  os_id="${ID:-}"
  os_version="${VERSION_ID:-}"
  os_pretty="${PRETTY_NAME:-}"
fi
kernel="$(uname -r 2>/dev/null || true)"
arch="$(uname -m 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# GPU. NVIDIA first: nvidia-smi is authoritative when it answers, and its
# presence is exactly the condition h1-nvidia's bootstrap checks for.
gpu_vendor="none"; gpu_model=""; gpu_vram_gib=""; gpu_gtt_gib=""; gpu_driver=""

if have nvidia-smi && nvidia_out="$(nvidia-smi --query-gpu=name,memory.total,driver_version \
      --format=csv,noheader,nounits 2>/dev/null)" && [[ -n "$nvidia_out" ]]; then
  gpu_vendor="nvidia"
  IFS=',' read -r gpu_model vram_mib gpu_driver <<<"$(head -n1 <<<"$nvidia_out")"
  gpu_model="${gpu_model# }"; vram_mib="${vram_mib# }"; gpu_driver="${gpu_driver# }"
  [[ "$vram_mib" =~ ^[0-9]+$ ]] && gpu_vram_gib=$(( vram_mib / 1024 ))
fi

# AMD. mem_info_vram_total is a dedicated pool on a discrete card and a small
# carve-out on an APU, where the number that matters is mem_info_gtt_total —
# the share of system RAM the GPU may map. Report both; the classifier decides.
dri_nodes="$(ls -1 /dev/dri/renderD* 2>/dev/null || true)"

if [[ "$gpu_vendor" == "none" && -n "$dri_nodes" ]]; then
  for card in /sys/class/drm/card[0-9]*; do
    [[ -r "$card/device/uevent" ]] || continue
    grep -q '^DRIVER=amdgpu$' "$card/device/uevent" 2>/dev/null || continue
    gpu_vendor="amd"
    if [[ -r "$card/device/mem_info_vram_total" ]]; then
      gpu_vram_gib=$(( $(cat "$card/device/mem_info_vram_total") / 1073741824 ))
    fi
    if [[ -r "$card/device/mem_info_gtt_total" ]]; then
      gpu_gtt_gib=$(( $(cat "$card/device/mem_info_gtt_total") / 1073741824 ))
    fi
    break
  done
fi

# A readable model name. lspci knows the marketing name; the amdgpu sysfs tree
# only knows PCI IDs.
if [[ -z "$gpu_model" && "$gpu_vendor" == "amd" ]] && have lspci; then
  gpu_model="$(lspci -mm 2>/dev/null \
    | grep -iE '"(VGA compatible controller|Display controller)"' \
    | grep -i 'AMD\|ATI' | head -n1 | cut -d'"' -f6)"
fi

if [[ "$gpu_vendor" == "amd" && -r /proc/modules ]]; then
  gpu_driver="$(awk '$1 == "amdgpu" {print "amdgpu"}' /proc/modules | head -n1)"
fi

# ---------------------------------------------------------------------------
# Vulkan. The AMD path serves through it, so "is it installed and does it see a
# device" is the difference between GPU inference and a silent CPU fallback.
vulkan_present="false"; vulkan_device=""
if have vulkaninfo; then
  vulkan_present="true"
  vulkan_device="$(vulkaninfo --summary 2>/dev/null \
    | awk -F'=' '/deviceName/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
fi

# ---------------------------------------------------------------------------
# Docker. `docker info` failing while the binary exists usually means the user
# is not in the docker group — a bootstrap-fixable state, not a missing engine.
docker_present="false"; docker_version=""; docker_usable="false"; docker_runtimes=""
if have docker; then
  docker_present="true"
  docker_version="$(docker --version 2>/dev/null | sed 's/^Docker version //; s/,.*//')"
  if docker info >/dev/null 2>&1; then
    docker_usable="true"
    docker_runtimes="$(docker info --format '{{range $k, $v := .Runtimes}}{{$k}}{{"\n"}}{{end}}' 2>/dev/null)"
  fi
fi

# ---------------------------------------------------------------------------
# Whether bootstrap will need a password. Cheap to check and it changes the
# instruction the skill gives the user.
sudo_mode="unknown"
if [[ "$(id -u)" == "0" ]]; then
  sudo_mode="root"
elif have sudo; then
  if sudo -n true 2>/dev/null; then sudo_mode="passwordless"; else sudo_mode="password"; fi
fi

mem_total_gib=""
if [[ -r /proc/meminfo ]]; then
  mem_total_gib=$(( $(awk '/^MemTotal:/ {print $2}' /proc/meminfo) / 1048576 ))
fi

# ---------------------------------------------------------------------------
printf '{\n'
printf '  "schema": 1,\n'
printf '  "os": {"id": %s, "version": %s, "pretty": %s, "kernel": %s, "arch": %s},\n' \
  "$(jstr "$os_id")" "$(jstr "$os_version")" "$(jstr "$os_pretty")" \
  "$(jstr "$kernel")" "$(jstr "$arch")"
printf '  "mem_total_gib": %s,\n' "$(jnum "$mem_total_gib")"
printf '  "gpu": {"vendor": %s, "model": %s, "vram_gib": %s, "gtt_gib": %s, "driver": %s},\n' \
  "$(jstr "$gpu_vendor")" "$(jstr "$gpu_model")" "$(jnum "$gpu_vram_gib")" \
  "$(jnum "$gpu_gtt_gib")" "$(jstr "$gpu_driver")"
printf '  "dri_nodes": %s,\n' "$(jarray <<<"$dri_nodes")"
printf '  "vulkan": {"present": %s, "device": %s},\n' \
  "$(jbool "$vulkan_present")" "$(jstr "$vulkan_device")"
printf '  "docker": {"present": %s, "usable": %s, "version": %s, "runtimes": %s},\n' \
  "$(jbool "$docker_present")" "$(jbool "$docker_usable")" \
  "$(jstr "$docker_version")" "$(jarray <<<"$docker_runtimes")"
printf '  "sudo": %s\n' "$(jstr "$sudo_mode")"
printf '}\n'
