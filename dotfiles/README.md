# 🧰 Portable Dev Environment (dotfiles)

A reproducible, cross-platform setup for **Zsh (Oh My Zsh + Powerlevel10k)**, **tmux**, and **Neovim**, with one-shot bootstrap for **Ubuntu/WSL**, **Linux**, and **macOS**.
Everything is symlinked with **GNU Stow**.

---

## ✨ What included

* **Zsh** with **Oh My Zsh** (auto-installed if missing)
* **Powerlevel10k** theme (auto-installed if missing)
* **Nerd Fonts** installer (Linux/macOS) with safe fallbacks
* **tmux** with **TPM** (plugin manager)
* **Neovim** with **lazy.nvim** bootstrap (headless)
* Base dev toolchain: `git, ripgrep, fd, fzf, cmake, gcc/clang, gdb`, etc.
* Optional **embedded** tools on Linux (`gdb-multiarch`, `openocd`, ARM GCC)
* Idempotent, debuggable **bootstrap** (`dotfiles/summon.sh`) with:

  * `--dry-run`, `--debug`, `--no-fonts`, `--minimal`
  * conflict detection for Stow 
  * comprehensive logging to `~/.dotfiles-install.log`

---

## 📁 Repo layout

```
.
├── dotfiles
│   ├── git/                # e.g. git/.gitconfig (optional)
│   ├── nvim/.config/nvim/  # full Neovim config
│   ├── scripts/            # optional extra scripts
│   ├── summon.sh           # the bootstrap script (run this)
│   ├── tmux/.tmux.conf
│   └── zsh/.zshrc
└── README.md
```

**Stow modules:** `zsh`, `tmux`, `nvim`, `git`
Each module mirrors the target path under `$HOME`.
Example: `dotfiles/zsh/.zshrc` → symlinked to `~/.zshrc` by Stow.

---

## 🚀 Quick start

```bash
# 1) Clone to your home
git clone https://github.com/<you>/dotfiles.git ~/.dotfiles
cd ~/.dotfiles/dotfiles

# 2) Run the bootstrap
bash ./summon.sh
# or, with options:
bash ./summon.sh --debug         # verbose logs + bash tracing
bash ./summon.sh --dry-run       # show actions, make no changes
bash ./summon.sh --no-fonts      # skip Nerd Fonts install
bash ./summon.sh --minimal       # skip Neovim/Mason headless bootstrap
```

* On **WSL**, set your Windows Terminal font to a Nerd Font (e.g., *FiraCode Nerd Font*) for proper icons.
* All output is also logged to `~/.dotfiles-install.log`.

---

## 🧵 How symlinking works (GNU Stow)

The script calls Stow to symlink modules into `$HOME`.
For example:

```
stow --restow --target="$HOME" zsh
# creates: ~/.zshrc -> <repo>/dotfiles/zsh/.zshrc
```

* **Preview** first: the script runs `stow -nv` (no-op, verbose).
* **Conflicts**: if a real file exists (not a symlink), the script **skips** that module and prints instructions to resolve or to adopt:

  ```bash
  stow --adopt --target="$HOME" <module>   # moves real files into the repo
  git status                               # review before committing
  ```

---

## 🧠 What the bootstrap does

1. **Detects** OS & package manager (apt/dnf/pacman/brew).
2. **Installs** base packages (zsh, tmux, stow, neovim, compilers, tools).
3. **Fonts**: installs Nerd Font (Linux/macOS) unless `--no-fonts`.
4. **Oh My Zsh**: installs if `~/.oh-my-zsh` is missing (keeps your `.zshrc`).
5. **Powerlevel10k**: installs to `~/.oh-my-zsh/custom/themes/powerlevel10k`.
6. **Stows** modules safely (`zsh`, `tmux`, `nvim`, `git`).
7. **Default shell**: switches to zsh (if `chsh` available).
8. **tmux plugins**: installs via TPM.
9. **Neovim headless**: `+Lazy! sync` and `+MasonUpdate` (skip with `--minimal`).
10. **Embedded tools (Linux)**: installs via apt (optional step in script).
11. **Sanity report**: prints presence/paths of key tools.

---

## ⚙️ Your Zsh config (excerpt)

 **Oh My Zsh** with **Powerlevel10k**, and plugins:

```zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git z tmux sudo history-substring-search)
source $ZSH/oh-my-zsh.sh
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
```

The bootstrap ensures `~/.oh-my-zsh` and the `powerlevel10k` theme exist before your `.zshrc` loads them.

---

## 🖨️ Useful flags

* `--debug`
  Extra prints + `set -x` tracing. All output is tee’d to `~/.dotfiles-install.log`.

* `--dry-run`
  Echo commands instead of running them. Great for auditing actions.

* `--no-fonts`
  Skip Nerd Font install (useful on CI/servers).

* `--minimal`
  Skip headless Neovim/Lazy/Mason steps (fast base setup).

---

## 🧪 Sanity check

After running:

```bash
# see what got installed and where
tail -n +1 ~/.dotfiles-install.log | less

# quick health:
which zsh tmux nvim stow rg fd fzf cmake g++ clangd gdb
```

In Neovim:

```
:Lazy
:Mason
```

---

## 🐛 Troubleshooting

* **Fonts look wrong / icons missing**

  * Re-run with fonts: `bash ./summon.sh` (without `--no-fonts`)
  * On **WSL**, set Windows Terminal font to a Nerd Font (e.g., FiraCode Nerd Font).
  * On macOS, ensure Homebrew cask fonts are installed:

    ```bash
    brew tap homebrew/cask-fonts
    brew install --cask font-fira-code-nerd-font
    ```

* **Stow says “conflict”**

  * The script will show conflicting paths. Either remove/backup those files or adopt them:

    ```bash
    stow --adopt --target="$HOME" <module>
    git status  # review moved files before commit
    ```

* **Neovim headless bootstrap fails**

  * Run without headless steps:

    ```bash
    bash ./summon.sh --minimal
    ```
  * Open Neovim and check:

    ```
    :Lazy sync
    :MasonUpdate
    ```

* **`chsh` failed**

  * Some environments disallow changing shells non-interactively.

    ```bash
    chsh -s "$(command -v zsh)"
    ```

---

## 🛠️ Customize

* Add modules: create a folder under `dotfiles/<module>` mirroring the target path, e.g.:

  ```
  dotfiles/vscode/.config/Code/User/settings.json
  ```

  Then run `bash ./summon.sh` again to stow it.

* Add machine-specific settings: create `~/.dotfiles/local/*.zsh` and source it from your `.zshrc` (keep secrets out of Git).

* Skip embedded tools: comment out the `install_embedded_linux` call in `summon.sh`.

---

## 🧹 Uninstall (unlink) symlinks

From `dotfiles/`:

```bash
stow -D --target="$HOME" zsh tmux nvim git
```

---

## 📝 License

MIT © <nelmensh>
```

---


## 📎 Quick commands reference

```bash
# Clone + bootstrap
git clone https://github.com/<you>/dotfiles.git ~/.dotfiles
cd ~/.dotfiles/dotfiles
bash ./summon.sh --debug

# Dry run
bash ./summon.sh --dry-run

# Stow only (from dotfiles/)
stow --restow --target="$HOME" zsh tmux nvim git

# Adopt existing files into repo (DANGEROUS; review git status!)
stow --adopt --target="$HOME" zsh
git status
```

---


