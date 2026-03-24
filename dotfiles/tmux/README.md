# 🧠 Tmux Setup & Usage Guide (Colemak + Arrow-Friendly)

This guide explains how to use your tmux setup, keybindings, and how to install plugins using TPM.

---

## 🚀 What is tmux?

**tmux** is a terminal multiplexer that lets you:

* Split your terminal into multiple panes
* Manage multiple sessions and windows
* Detach and reattach sessions (great for remote work)
* Keep long-running processes alive

---

## ⚡ Prefix Key

Your prefix key is:

```
Ctrl + Space
```

All tmux commands start with this key unless specified otherwise.

---

## 🪟 Windows (Tabs)

| Action                    | Key            |
| ------------------------- | -------------- |
| New window                | `Prefix + c`   |
| Rename window             | `Prefix + w`   |
| Next window               | `Prefix + n`   |
| Previous window           | `Prefix + p`   |
| Last window               | `Prefix + Tab` |
| Switch window (no prefix) | `Alt + ← / →`  |

---

## 🧩 Panes (Splits)

### Split panes

| Action           | Key          |   |
| ---------------- | ------------ | - |
| Vertical split   | `Prefix +    | ` |
| Horizontal split | `Prefix + -` |   |

> Splits open in the **same directory** as current pane.

---

### Navigate panes

| Action             | Key                   |
| ------------------ | --------------------- |
| Move between panes | `Prefix + Arrow Keys` |
| Move (no prefix)   | `Ctrl + Arrow Keys`   |

---

### Resize panes

| Action      | Key                      |
| ----------- | ------------------------ |
| Resize pane | `Prefix + Shift + Arrow` |

> If Shift+Arrow doesn't work in your terminal, use Alt or Ctrl+Shift instead.

---

### Pane management

| Action            | Key          |
| ----------------- | ------------ |
| Zoom pane         | `Prefix + m` |
| Kill pane         | `Prefix + x` |
| Show pane numbers | `Prefix + q` |

---

## 📦 Sessions

| Action           | Key                |
| ---------------- | ------------------ |
| New session      | `tmux new -s name` |
| List sessions    | `tmux ls`          |
| Attach session   | `tmux a -t name`   |
| Rename session   | `Prefix + R`       |
| Next session     | `Prefix + N`       |
| Previous session | `Prefix + P`       |

---

## 📋 Copy Mode (Vim-style)

| Action           | Key          |
| ---------------- | ------------ |
| Enter copy mode  | `Prefix + [` |
| Start selection  | `v`          |
| Copy selection   | `y`          |
| Rectangle select | `r`          |

---

## 🔄 Reload Config

```
Prefix + r
```

---

## 🎨 Status Bar

* Shows **session name**, **window names**, and **time/date**
* Highlights zoomed panes

---

## 🔤 Auto Naming

Windows automatically rename based on running process:

* `nvim`
* `ssh`
* `htop`

You can still rename manually.

---

## 🔌 Plugin Manager (TPM)

### What is TPM?

**TPM (Tmux Plugin Manager)** lets you easily install and manage tmux plugins.

---

## 📥 Install TPM

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

---

## 📦 Install Plugins

1. Start tmux:

   ```bash
   tmux
   ```

2. Press:

   ```
   Prefix + I
   ```

This installs all plugins listed in your `.tmux.conf`.

---

## 🔄 Update Plugins

```
Prefix + U
```

---

## ❌ Remove Plugins

```
Prefix + Alt + u
```

---

## 📁 Plugin Location

```
~/.tmux/plugins/
```

---

## 🧪 Recommended Plugins (optional)

Add these to your config:

```tmux
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
```

### Features:

* `tmux-sensible` → better defaults
* `tmux-resurrect` → restore sessions
* `tmux-continuum` → auto-save sessions

---

## 🧠 Workflow Tips (Colemak-Friendly)

* Use **Arrow keys everywhere** (tmux + nvim consistency)
* Use:

  * `Ctrl + Arrow` → panes
  * `Alt + Arrow` → windows
* Keep one session per project

---

## 🛠 Troubleshooting

### Plugins not installing?

```bash
ls ~/.tmux/plugins/tpm
```

If missing:

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

---

### Keybindings not working?

Reload config:

```
Prefix + r
```

---

### Shift+Arrow not working?

Your terminal might not support it.

Use alternative:

```tmux
bind -r M-Left resize-pane -L 5
```

---

## 🏁 Quick Start

```bash
tmux new -s dev
```

Then:

* Split → `Prefix + |`
* Navigate → `Ctrl + Arrows`
* Rename → `Prefix + w`
* Reload config → `Prefix + r`

---


