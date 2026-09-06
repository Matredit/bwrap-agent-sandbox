# agent-sandbox

A simple Bubblewrap sandbox for CLI coding agents.

Designed for Omarchy Linux, where by default agents run without any sandboxing in _bypassing all permissions_ mode. This wrapper leaves the environment permissive enough for tools like `mise` to function, while strictly locking down system integrity and masking sensitive personal data. The host filesystem is read-only by default.

**Installation**  
(requires bubblewrap)

```bash
chmod +x agent-sandbox.sh
mv agent-sandbox.sh ~/.local/bin/agent-sandbox
```

**Usage**  

### 1. Preset Shortcuts (Quick Launch)
When launching an agent from your project folder, you can use built-in presets. By default, the current directory (`.`) is mounted as your writable workspace and `.git` is protected as read-only.

```bash
# Antigravity CLI (agy --dangerously-skip-permissions)
agent-sandbox g              # Standard: project writable, .git read-only
agent-sandbox g -o           # Ephemeral OverlayFS: changes stay in RAM, discarded on exit
agent-sandbox g -r           # Read-Only: project is strictly read-only

# OpenCode (opencode --auto)
agent-sandbox oc             # Standard: project writable, .git read-only
agent-sandbox oc -o          # Ephemeral OverlayFS

# Claude (claude --dangerously-skip-permissions)
agent-sandbox c

# Pass extra flags or prompts to the agent cleanly using '--'
agent-sandbox g -- "explain this codebase"
agent-sandbox g -o -- -c     # Continue recent conversation in overlay mode
agent-sandbox g -m .env      # Mask .env with read-only notice
```

### 2. Classic Full Syntax
If you need custom commands or specific workspace configurations:

```bash
# Explicit workspaces and read-only overrides
agent-sandbox -w ./ -r .git -- agy --dangerously-skip-permissions

# Ephemeral overlay with masked files
agent-sandbox -o ./ -r .git -m .env -- opencode --auto

# Use old ambiguous masking (empty directory and 0-byte file without notice)
agent-sandbox -w ./ -m .env --stealth -- agy
```

**Configuration & Tweaking**  
Open the script in any editor to customize your permissions. The security boundaries are defined by simple arrays:

- `WRITABLE_DIRS`: Add paths here to allow all agents do anything (e.g., `"$HOME/.config/some-agent"`).
- `MASKED_DIRS`: Add private folders here (e.g., `"$HOME/Personal"`). They are replaced by empty RAM disks, hiding your files completely from the agent.
- `MASKED_FILES`: Add specific files here (e.g., `"$HOME/slavik_passwords.txt"`) to prevent the agent from reading their contents without masking the parent directory.

Paths passed via the `-w`/`--workspace` flag take highest priority and grant full read-write access to those directories. It is recommended to `cd` into your project directory first (e.g., `~/.config/omarchy/plugins/user.someplugin`) and pass `./`:

```bash
agent-sandbox -w ./ -- opencode --auto
```
