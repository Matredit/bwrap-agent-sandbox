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
Pass one or more workspace directories using `-w`, followed by `--`, and then your agent command. The specified workspaces will be fully read-write.

```bash
agent-sandbox -w ./ -w ~/also-writable -- agy --dangerously-skip-permissions
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
