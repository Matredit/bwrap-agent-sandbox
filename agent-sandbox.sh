#!/usr/bin/env bash
# agent-sandbox - A Bubblewrap wrapper for CLI coding agents
set -euo pipefail

WORKSPACES=()
COMMAND=()

# empty file instead of /dev/null for masking files
EMPTY_FILE=$(mktemp)
trap 'rm -f "$EMPTY_FILE"' EXIT  # Clean up automatically when script exits

# 1. Parse arguments: Extract workspaces and the final command
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
    --)
      shift
      COMMAND=("$@")
      break
      ;;
    *)
      echo "Error: Invalid argument '$1'"
      echo "Usage: $0 [-w /path/to/workspace]... -- <command> [args...]"
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
)

# Helper functions to prevent bwrap crashes if a directory doesn't exist on the host
bind_if_exists() {
  if [[ -d "$1" ]]; then
    BWRAP_ARGS+=(--bind "$1" "$1")
  fi
}

mask_if_exists() {
  if [[ -d "$1" ]]; then
    BWRAP_ARGS+=(--tmpfs "$1")
  fi
}

mask_file_if_exists() {
  if [[ -f "$1" ]]; then
    BWRAP_ARGS+=(--ro-bind "$EMPTY_FILE" "$1") # ro is crucial, prevents cross-contamination
  fi
}

# 3. Writable System/Config directories (as requested for 'yolo' compatibility)
bind_if_exists "$HOME/.claude"
bind_if_exists "$HOME/.codex"
bind_if_exists "$HOME/.copilot"
bind_if_exists "$HOME/.gemini"
bind_if_exists "$HOME/.pi"

bind_if_exists "$HOME/.cache"

# ~/.config
# bind_if_exists "$HOME/.config"
bind_if_exists "$HOME/.config/mise"
bind_if_exists "$HOME/.config/opencode"

mask_if_exists "$HOME/.config/1Password"
mask_if_exists "$HOME/.config/Bitwarden"
mask_if_exists "$HOME/.config/keepassxc"
mask_if_exists "$HOME/.config/BraveSoftware"
mask_if_exists "$HOME/.config/chromium"
mask_if_exists "$HOME/.config/google-chrome"
mask_if_exists "$HOME/.config/google-chrome-beta"
mask_if_exists "$HOME/.config/google-chrome-unstable"
mask_if_exists "$HOME/.config/microsoft-edge"
mask_if_exists "$HOME/.config/microsoft-edge-dev"
mask_if_exists "$HOME/.config/mozilla"
mask_if_exists "$HOME/.config/torbrowser"
mask_if_exists "$HOME/.config/vivaldi"
mask_if_exists "$HOME/.config/vivaldi-snapshot"
mask_if_exists "$HOME/.config/discord"
mask_if_exists "$HOME/.config/Signal"
mask_if_exists "$HOME/.config/TeamSpeak"
mask_if_exists "$HOME/.config/obsidian"

# ~/.local
# bind_if_exists "$HOME/.local"
bind_if_exists "$HOME/.local/share/mise"
bind_if_exists "$HOME/.local/share/opencode"
bind_if_exists "$HOME/.local/share/opentui"
bind_if_exists "$HOME/.local/state/mise"
bind_if_exists "$HOME/.local/state/opencode"

mask_if_exists "$HOME/.local/share/keyrings"
mask_if_exists "$HOME/.local/share/TelegramDesktop"
mask_if_exists "$HOME/.local/share/torbrowser"
mask_if_exists "$HOME/.local/share/Trash"



# 4. Masked/Hidden Directories
# These become completely empty read-write RAM disks. The agent cannot see your files.
mask_if_exists "$HOME/.ssh"
mask_if_exists "$HOME/.gnupg"
mask_if_exists "$HOME/.keepass"
mask_if_exists "$HOME/.mozilla"
mask_if_exists "$HOME/.pki"
mask_if_exists "$HOME/Desktop"
mask_if_exists "$HOME/Documents"
mask_if_exists "$HOME/Downloads"
mask_if_exists "$HOME/Games"
mask_if_exists "$HOME/Music"
mask_if_exists "$HOME/Photos"
mask_if_exists "$HOME/Pictures"
# mask_if_exists "$HOME/Projects" # symlinks are evil
mask_if_exists "$HOME/Videos"
mask_if_exists "$HOME/Work"

# 4.2 Masked/Hidden Files
mask_file_if_exists "$HOME/.bash_history"
mask_file_if_exists "$HOME/.mariadb_history"
mask_file_if_exists "$HOME/.node_repl_history"
mask_file_if_exists "$HOME/.psql_history"
mask_file_if_exists "$HOME/.python_history"
mask_file_if_exists "$HOME/.pulse-cookie"
mask_file_if_exists "$HOME/default_pwtimer.json"
mask_file_if_exists "$HOME/.my_file2"

# 5. Whitelisted Workspace Directories
for ws in "${WORKSPACES[@]}"; do
  if [[ ! -d "$ws" ]]; then
    echo "Warning: Workspace directory does not exist: $ws"
    continue
  fi
  # Overrides the read-only root specifically for this folder
  BWRAP_ARGS+=(--bind "$ws" "$ws")
done

# 6. Execute the target agent inside the sandbox
# 'exec' replaces the current bash process with bwrap, passing signals cleanly.
exec bwrap "${BWRAP_ARGS[@]}" "${COMMAND[@]}"
