# bwrap box

A simple Bubblewrap sandbox for CLI coding agents.

Designed for Omarchy Linux, where agents run by default without sandboxing in bypass-all-permissions mode. This wrapper leaves the environment permissive enough for tools like `mise` to work, while locking down system integrity and masking sensitive personal data. The host filesystem is read-only by default.

### Installation

Requires `bubblewrap`.

```bash
chmod +x bbox.sh
mv bbox.sh ~/.local/bin/bbox
```

### Usage

- Mounts `/` read-only, then overrides it with defaults.
- Defaults (check the script for the full list):
  - **Writable by default:**
    - Agent directories like `.gemini`
    - `~/.cache`
    - Config and local state folders for tools like `mise`, `opencode`, `nvim`
  - **Masked (hidden) by default:**
    - Shell histories (`.bash_history`, etc.)
    - `~/.ssh`, `~/.gnupg`
    - Common user folders (`Desktop`, `Documents`, `Downloads`, `Photos`, `Videos`, etc.)
    - Caches and configs for apps like browsers and messengers
    - Trash
- Mount a directory as writable with `-w path/to/dir`. Directories only (some editors don't write directly to files, they replace them atomically).
- Make something read-only inside your writable directory with `-r path` (useful if you don't want your `.git` folder touched). Can be a file or directory.
- Allow disposable changes that won't be saved to disk with an overlay: `-o dir` (useful for `.git` so the agent can make commits without messing up your actual git history).
- Hide secrets from the agent with `-m file_or_dir`. Useful for `.env` or personal files.
- By default, `-m` creates an in-RAM fake directory with a read-only `README.txt` notice inside (or binds the notice over a file). The notice explains that the path is sandboxed so the agent won't think it's missing or try to bypass it. If you don't want the notice, use `--stealth` (or `--empty-mask`) to mount an empty file/folder instead.
- Pass the command to run after `--`.  
  For example, to run Antigravity: `-- agy --dangerously-skip-permissions`, or OpenCode: `-- opencode --auto`. We run in auto/yolo mode because everything is already sandboxed, so clicking "approve" every time is unnecessary.

### Shortcuts

Since writing `-- agy --dangerously-skip-permissions` every time is tedious, you can use presets.
By default, a preset makes your current working directory writable and protects `.git` (if it exists) as read-only.

For example, `bbox g` is the same as:

```bash
bbox -w . -r .git -- agy --dangerously-skip-permissions
```

(Same for OpenCode with `bbox oc`).

You can change how the current working directory is mounted using bare `-w`, `-r`, or `-o` flags (without a path):

- `bbox g -r` makes the current directory strictly read-only.
- `bbox g -o` mounts the current directory as an ephemeral overlay.

You can combine any options:

```bash
bbox g -r -w src/ -o .git -m .env
```

You can also use `--` to pass extra arguments to the preset command:

```bash
bbox g -- -i "hello"
```

results in:

```bash
bbox -w . -r .git -- agy --dangerously-skip-permissions -i "hello"
```

Presets, default writable paths, and masked paths are easy to edit directly in the script.
If you only care about protecting your personal files, mask just those and leave `.config` and other folders writable to get the most out of your Omarchy [malleable](https://world.hey.com/dhh/the-malleable-computer-7c187a9b) computer.

### Quirks

I don't know everything that needs to be mounted and what doesn't. I tried not to make sandboxing useless by exposing all of `XDG_RUNTIME_DIR`, so some things might not work smoothly, and some editors might fail if they need their own local state directory.

- **Copying in Neovim doesn't work:**

  ```
  clipboard: error invoking wl-copy: Failed to connect to a Wayland server: No such file or directory Note: WAYLAND_DISPLAY is set to wayland-1 Note: XDG_RUNTIME_DIR is set to /run/user/1000 Please check whether /run/user/1000/wayland-1 socket exists and is accessible.
  ```

  To fix this, you can either use OSC 52 in your Neovim config (ask your agent), or just hold Shift, select with your mouse, and copy using Super+C or Ctrl+Shift+C (most terminals support this).
