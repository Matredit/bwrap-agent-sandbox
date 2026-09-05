#!/usr/bin/env bash
# agent-sandbox - A Bubblewrap wrapper for CLI coding agents
set -euo pipefail

WORKSPACES=()
OVERLAYS=()
READONLY_PATHS=()
CLI_MASKS=()
STEALTH_MASK=false
COMMAND=()

# Temporary files for masking
EMPTY_FILE=$(mktemp)
NOTICE_FILE=$(mktemp)
trap 'rm -f "$EMPTY_FILE" "$NOTICE_FILE"' EXIT  # Clean up automatically when script exits

cat <<'EOF' > "$NOTICE_FILE"
[SANDBOX NOTICE]
This file or directory is masked by the Bubblewrap sandbox (agent-sandbox).
Access to this content has been restricted to protect sensitive personal data or system integrity.

If you are an AI coding agent and require access to this path to complete your task:
- DO NOT assume this file or directory is missing, empty, or corrupted.
- DO NOT attempt to recreate, overwrite, or bypass this restriction.
- Please inform the user and ask them to grant access by updating their sandbox configuration or command-line flags.
EOF

# 1. Parse arguments: Extract workspaces, overlays, readonly paths, masks, and the final command
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--workspace)
      if [[ -z "${2:-}" ]]; then
        echo "Error: -w requires a directory argument."
        exit 1
      fi
      # Resolve to absolute path to prevent bwrap symlink/relative path errors
      WORKSPACES+=("$(realpath "$2")")
      shift 2
      ;;
    -o|--overlay)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a directory argument."
        exit 1
      fi
      OVERLAYS+=("$(realpath "$2")")
      shift 2
      ;;
    -r|-ro|--ro|--readonly|--read-only)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a path argument."
        exit 1
      fi
      READONLY_PATHS+=("$(realpath "$2")")
      shift 2
      ;;
    -m|--mask)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a path argument."
        exit 1
      fi
      CLI_MASKS+=("$(realpath "$2")")
      shift 2
      ;;
    --stealth|--stealth-mask|--empty-mask|--ambiguous)
      STEALTH_MASK=true
      shift
      ;;
    --)
      shift
      COMMAND=("$@")
      break
      ;;
    *)
      echo "Error: Invalid argument '$1'"
      echo "Usage: $0 [-w /path/to/workspace]... [-o /path/to/overlay]... [-r /path/to/readonly]... [-m /path/to/mask]... [--stealth] -- <command> [args...]"
      exit 1
      ;;
  esac
done

if [[ ${#COMMAND[@]} -eq 0 ]]; then
  echo "Error: No command provided after '--'."
  echo "Usage: $0 -w ./my-project -- antigravity-cli"
  exit 1
fi

# 2. Base Kernel Namespaces & Global Read-Only Root
BWRAP_ARGS=(
  --ro-bind / /  # The core rule: Entire host is read-only
  --dev /dev     # Required for pseudoterminals (PTYs) and basic IO
  --proc /proc   # Required for process management
  --tmpfs /tmp   # Isolated scratchpad; prevents reading host /tmp sockets
  --tmpfs "${XDG_RUNTIME_DIR:-/run/user/$UID}" # Fixes Neovim crashes
  --tmpfs /var/tmp                             # maybe Needed for large compiler temps
  --tmpfs /dev/shm                             # maybe Needed for Node/Python shared memory
)

# 3. Configuration Arrays (Declarative Setup)
WRITABLE_DIRS=(
  # Top-level agent folders
  "$HOME/.claude"
  "$HOME/.codex"
  "$HOME/.copilot"
  "$HOME/.gemini"
  "$HOME/.pi"
  
  # Base Cache
  "$HOME/.cache"
  
  # Specific Configs
  "$HOME/.config/mise"
  "$HOME/.config/opencode"
  
  # Specific Local States
  "$HOME/.local/share/mise"
  "$HOME/.local/share/opencode"
  "$HOME/.local/share/opentui"
  "$HOME/.local/state/mise"
  "$HOME/.local/state/nvim"  # Fixes Neovim crashes
  "$HOME/.local/state/opencode"
)

MASKED_DIRS=(
  # Home Directory Secrets & Personal Folders
  "$HOME/.ssh"
  "$HOME/.gnupg"
  "$HOME/.keepass"
  "$HOME/.ViberPC"
  "$HOME/.mozilla"
  "$HOME/.pki"
  "$HOME/Desktop"
  "$HOME/Documents"
  "$HOME/Downloads"
  "$HOME/Games"
  "$HOME/Music"
  "$HOME/Photos"
  "$HOME/Pictures"
  "$HOME/Videos"
  "$HOME/Work"
  # "$HOME/Projects" # symlinks are evil, never again

  # Caches to hide inside the writable ~/.cache
  "$HOME/.cache/thumbnails"
  "$HOME/.cache/BraveSoftware"
  "$HOME/.cache/chromium"
  "$HOME/.cache/mozilla"
  "$HOME/.cache/torbrowser"
  "$HOME/.cache/com.bitwarden.desktop"
  "$HOME/.cache/keepassxc"
  "$HOME/.cache/TelegramDesktop"
  "$HOME/.cache/TeamSpeak"

  # Configs to hide
  "$HOME/.config/1Password"
  "$HOME/.config/Bitwarden"
  "$HOME/.config/keepassxc"
  "$HOME/.config/BraveSoftware"
  "$HOME/.config/chromium"
  "$HOME/.config/google-chrome"
  "$HOME/.config/google-chrome-beta"
  "$HOME/.config/google-chrome-unstable"
  "$HOME/.config/microsoft-edge"
  "$HOME/.config/microsoft-edge-dev"
  "$HOME/.config/mozilla"
  "$HOME/.config/torbrowser"
  "$HOME/.config/vivaldi"
  "$HOME/.config/vivaldi-snapshot"
  "$HOME/.config/discord"
  "$HOME/.config/Signal"
  "$HOME/.config/TeamSpeak"
  "$HOME/.config/obsidian"

  # Local states to hide
  "$HOME/.local/share/keyrings"
  "$HOME/.local/share/TelegramDesktop"
  "$HOME/.local/share/torbrowser"
  "$HOME/.local/share/Trash"
)

MASKED_FILES=(
  # Histories
  "$HOME/.bash_history"
  "$HOME/.mariadb_history"
  "$HOME/.node_repl_history"
  "$HOME/.psql_history"
  "$HOME/.python_history"
  
  # some shit
  "$HOME/.pulse-cookie"
  "$HOME/default_pwtimer.json"
  "$HOME/.my_file2"
)

# Apply Mounts in Strict Order

# Apply Writable Directories
for dir in "${WRITABLE_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then BWRAP_ARGS+=(--bind "$dir" "$dir"); fi
done

# Apply Directory Masks (Tmpfs)
for dir in "${MASKED_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    BWRAP_ARGS+=(--tmpfs "$dir")
    if [[ "$STEALTH_MASK" == false ]]; then
      BWRAP_ARGS+=(--ro-bind "$NOTICE_FILE" "$dir/README.txt")
    fi
  fi
done

# Apply File Masks
for file in "${MASKED_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    if [[ "$STEALTH_MASK" == false ]]; then
      BWRAP_ARGS+=(--ro-bind "$NOTICE_FILE" "$file")
    else
      BWRAP_ARGS+=(--ro-bind "$EMPTY_FILE" "$file")
    fi
  fi
done

# Whitelisted Workspace Directories
for ws in "${WORKSPACES[@]}"; do
  if [[ -d "$ws" ]]; then
    # Overrides the read-only root specifically for this folder
    BWRAP_ARGS+=(--bind "$ws" "$ws")
  else
    echo "Warning: Workspace directory does not exist: $ws"
  fi
done

# Ephemeral OverlayFS Directories (Copy-on-write via tmpfs, discarded on exit)
for ovl in "${OVERLAYS[@]}"; do
  if [[ -d "$ovl" ]]; then
    BWRAP_ARGS+=(--overlay-src "$ovl" --tmp-overlay "$ovl")
  else
    echo "Warning: Overlay directory does not exist: $ovl"
  fi
done

# Read-Only Overrides (Must be applied after workspaces/overlays to override writable mounts)
for ro in "${READONLY_PATHS[@]}"; do
  if [[ -e "$ro" ]]; then
    BWRAP_ARGS+=(--ro-bind "$ro" "$ro")
  else
    echo "Warning: Read-only path does not exist: $ro"
  fi
done

# CLI Mask Overrides (Must be applied after workspaces/overlays to mask paths inside them)
for target in "${CLI_MASKS[@]}"; do
  if [[ -d "$target" ]]; then
    BWRAP_ARGS+=(--tmpfs "$target")
    if [[ "$STEALTH_MASK" == false ]]; then
      BWRAP_ARGS+=(--ro-bind "$NOTICE_FILE" "$target/README.txt")
    fi
  elif [[ -f "$target" ]]; then
    if [[ "$STEALTH_MASK" == false ]]; then
      BWRAP_ARGS+=(--ro-bind "$NOTICE_FILE" "$target")
    else
      BWRAP_ARGS+=(--ro-bind "$EMPTY_FILE" "$target")
    fi
  else
    echo "Warning: Mask path does not exist: $target"
  fi
done

# Execute the target agent inside the sandbox
# 'exec' replaces the current bash process with bwrap, passing signals cleanly.
exec bwrap "${BWRAP_ARGS[@]}" "${COMMAND[@]}"
