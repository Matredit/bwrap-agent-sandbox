#!/usr/bin/env bash
# agent-sandbox - A Bubblewrap wrapper for CLI coding agents
set -euo pipefail

# Preset Aliases: map shortcut name to default agent command
# Easily edit or add custom agent presets here
declare -A PRESETS=(
  [g]="agy --dangerously-skip-permissions"
  [agy]="agy --dangerously-skip-permissions"
  [oc]="opencode --auto"
  [opencode]="opencode --auto"
)

WORKSPACES=()
OVERLAYS=()
READONLY_PATHS=()
CLI_MASKS=()
STEALTH_MASK=false
COMMAND=()

CWD_MODE=""
PROTECT_GIT=true
PRESET_SELECTED=""

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

# 1. Parse arguments: Handle presets, mode flags, paths, masks, and commands
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--workspace)
      # If followed by an existing directory, mount that directory as workspace
      if [[ -n "${2:-}" && "$2" != -* && "$2" != "--" && -d "$2" ]]; then
        WORKSPACES+=("$(realpath "$2")")
        shift 2
      else
        # Bare -w: set CWD mode to write
        CWD_MODE="write"
        shift
      fi
      ;;
    -o|--overlay)
      # If followed by an existing directory, mount that directory as overlay
      if [[ -n "${2:-}" && "$2" != -* && "$2" != "--" && -d "$2" ]]; then
        OVERLAYS+=("$(realpath "$2")")
        shift 2
      else
        # Bare -o: set CWD mode to overlay
        CWD_MODE="overlay"
        shift
      fi
      ;;
    -r|-ro|--ro|--readonly|--read-only)
      # If followed by an existing file/directory, mount that path as read-only
      if [[ -n "${2:-}" && "$2" != -* && "$2" != "--" && -e "$2" ]]; then
        READONLY_PATHS+=("$(realpath "$2")")
        shift 2
      else
        # Bare -r: set CWD mode to readonly
        CWD_MODE="readonly"
        shift
      fi
      ;;
    -m|--mask)
      if [[ -z "${2:-}" || "$2" == -* || "$2" == "--" ]]; then
        echo "Error: $1 requires a path argument."
        exit 1
      fi
      CLI_MASKS+=("$(realpath "$2")")
      shift 2
      ;;
    --allow-git|--git-write|--no-protect-git)
      PROTECT_GIT=false
      shift
      ;;
    --stealth|--stealth-mask|--empty-mask|--ambiguous)
      STEALTH_MASK=true
      shift
      ;;
    --)
      shift
      if [[ -n "$PRESET_SELECTED" ]]; then
        # Append extra arguments to the preset command
        COMMAND+=("$@")
      else
        # Classic syntax: user supplies the entire command
        COMMAND=("$@")
      fi
      break
      ;;
    *)
      # Check if argument matches a registered preset alias
      if [[ -n "${PRESETS[$1]:-}" ]]; then
        PRESET_SELECTED="$1"
        read -ra CMD_ARRAY <<< "${PRESETS[$1]}"
        COMMAND=("${CMD_ARRAY[@]}")
        # Presets default to CWD writable, unless modified by -o or -r
        if [[ -z "$CWD_MODE" ]]; then
          CWD_MODE="write"
        fi
        shift
      else
        echo "Error: Invalid argument '$1'"
        echo ""
        echo "Usage:"
        echo "  $0 <preset> [-o|-r|-w] [-m path]... [-- [agent-args...]]"
        echo "  $0 [-w dir]... [-o dir]... [-r path]... [-m path]... -- <command> [args...]"
        echo ""
        echo "Available presets: ${!PRESETS[*]}"
        exit 1
      fi
      ;;
  esac
done

# Apply CWD mode if set (presets default to write, modified by -o or -r)
CWD="$(realpath ".")"
if [[ "$CWD_MODE" == "write" ]]; then
  if [[ ! " ${WORKSPACES[*]} " =~ " ${CWD} " ]]; then
    WORKSPACES+=("$CWD")
  fi
elif [[ "$CWD_MODE" == "overlay" ]]; then
  if [[ ! " ${OVERLAYS[*]} " =~ " ${CWD} " ]]; then
    OVERLAYS+=("$CWD")
  fi
elif [[ "$CWD_MODE" == "readonly" ]]; then
  if [[ ! " ${READONLY_PATHS[*]} " =~ " ${CWD} " ]]; then
    READONLY_PATHS+=("$CWD")
  fi
fi

# Protect .git by default if CWD is the active workspace and .git exists
if [[ -n "$CWD_MODE" && "$PROTECT_GIT" == true ]]; then
  if [[ -e "$CWD/.git" ]]; then
    GIT_PATH="$(realpath "$CWD/.git")"
    if [[ ! " ${READONLY_PATHS[*]} " =~ " ${GIT_PATH} " ]]; then
      READONLY_PATHS+=("$GIT_PATH")
    fi
  fi
fi

if [[ ${#COMMAND[@]} -eq 0 ]]; then
  echo "Error: No agent preset or command provided."
  echo ""
  echo "Usage:"
  echo "  $0 <preset> [-o|-r|-w] [-m path]... [-- [agent-args...]]"
  echo "  $0 [-w dir]... [-o dir]... [-r path]... [-m path]... -- <command> [args...]"
  echo ""
  echo "Available presets: ${!PRESETS[*]}"
  echo ""
  echo "Modes for current directory:"
  echo "  (default)  Read-write workspace with .git protected as read-only"
  echo "  -o         Ephemeral OverlayFS (all changes in RAM, discarded on exit)"
  echo "  -r         Read-only workspace (no writes allowed anywhere in project)"
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

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "COMMAND: ${COMMAND[*]}"
  printf 'BWRAP_ARGS:\n'
  printf '  %s\n' "${BWRAP_ARGS[@]}"
  exit 0
fi

# Execute the target agent inside the sandbox
# 'exec' replaces the current bash process with bwrap, passing signals cleanly.
exec bwrap "${BWRAP_ARGS[@]}" "${COMMAND[@]}"
