# bwrap box

A simple Bubblewrap sandbox for CLI coding agents.

Designed for Omarchy Linux, where by default agents run without any sandboxing in bypassing all permissions mode. This wrapper leaves the environment permissive enough for tools like mise to function, while strictly locking down system integrity and masking sensitive personal data. The host filesystem is read-only by default.

### Installation

(requires bubblewrap)

chmod +x bbox.sh
mv bbox.sh ~/.local/bin/bbox

### Basic Syntax

- it mounts / readonly, then overwrites it with other defaults
- defaults (read the script for full info):
  writable by default:
  - agent dirs like .gemini
  - .cache
  - some .config, .local folders of some tools like mise, opencode, nvim.
    masked (hidden) by default:
  - bash and a few other histories
  - .ssh, .gnupg
  - most user folders like Desktop, Documents, Downloads, Photos, Videos, etc.
  - cache and configs of some apps like browsers, messengers
  - trash
- mount a directory as writable via -w path/to/dir. can be only dir (because some editors don't write to a file, they replace old with new one in atomic operation)
- make something readonly inside your writable dir via -r (nice if you don't want your .git folder to be changed). can be dir or file
- if you want to allow fake changes that won't be saved in your actual folder use overlay: -o dirname (can be used for .git as well to not confuse agent but still maintain conrtoll over git history)
- to hide secrets from agent use -m file or dir. useful for .env or just personal files.
- By default for dirs -m creates fake folder in ram, and binds readonly README.md file in there. for files it just readonly binds contents of README.md file instead of target one. that README says that it's a sandbox and it should ask you to drop masking and not think it's gone or try to go around this. If you want to disable README use --stealth/--empty-mask flag, it won't add readmes.
- after you specify all the settings with -w -o -r -m you specify the command you sandbox via --.
  e.g. to run antigravity you do `-- agy --dangerously-skip-permissions`, for opencode it's `-- opencode --auto`. We use yolo mode because we already sandboxed everything and clicking "approve" every time is nuts.

### Short syntax

since writing `-- agy --dangerously-skip-permissions` is nuts, you can use shortcuts.
By default using shortcut means your current working directory will be writable and .git inside of it (if exists) - readonly.
for exmaple, this: `bbox g` is same as `bbox -w . -r .git -- agy --dangerously-skip-permissions`. same with opencode.
you can change current working directory preset with -w -r -o flag withot path, e.g.
`bbox g -w` will make .git writable again, or `bbox g -o` will make cwd and .git overlay.
you can add whatever options you want next like `bbox -g -r -w src/ -o .git -m .env`
You also can use -- in preset mode to add an option to preset command, e.g.
`bbox g -- -i "hello"` will result in `bbox -w . -r .git -- agy --dangerously-skip-permissions -i "hello"`.
So unlike traditional syntax where -- means next goes path, -- here means next goes command

Edit presets (agent commands), default writable, masked inside the script, it's easy.
If you care only about your files add only them and make .config and other folders fully writable to unlock the most out of your Omarchy [malleable](https://world.hey.com/dhh/the-malleable-computer-7c187a9b) computer.

### quirks

I don't know what to mount and what to not, tried to not make sandboxing useless by allowing everything in XDG_RUNTIME_DIR, so some things may work badly, as well as some editors may not work beacuse they want e.g. their own local state dir.

- copying in nvim doesn't work:

```
clipboard: error invoking wl-copy: Failed to connect to a Wayland server: No such file or directory Note: WAYLAND_DISPLAY is set to wayland-1 Note: XDG_RUNTIME_DIR is set to /run/user/1000 Please check whether /run/user/1000/wayland-1 socket exists and is accessible.
```

to adress it you can either use something called 'OSC 52' in your nvim config (ask your AgEnT), or you can just hold shift and select with your mouse and copy using SUPER+C/CTRL+SHIFT+C instead. most terminals allow that.
