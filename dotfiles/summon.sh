#!/usr/bin/env bash
set -euo pipefail

#====================#
# Config             #
#====================#
DEFAULT_MODULES=(zsh tmux nvim git)
DEFAULT_FONT="FiraCode Nerd Font"
DEFAULT_FONT_MAC_CASK="font-fira-code-nerd-font"
LOGFILE="$HOME/.dotfiles-install.log"

#====================#
# Logging / helpers  #
#====================#
need() { command -v "$1" >/dev/null 2>&1; }
now()  { date +"%Y-%m-%d %H:%M:%S"; }
log()  { printf "\033[1;32m==>\033[0m %s\n" "$*"; printf "[%s] [INFO ] %s\n" "$(now)" "$*" >>"$LOGFILE"; }
warn() { printf "\033[1;33m!! \033[0m %s\n" "$*"; printf "[%s] [WARN ] %s\n" "$(now)" "$*" >>"$LOGFILE"; }
err()  { printf "\033[1;31mEE \033[0m %s\n" "$*" >&2; printf "[%s] [ERROR] %s\n" "$(now)" "$*" >>"$LOGFILE"; }
die()  { err "$*"; exit 1; }

# return 0 (true) if array contains needle
_arr_has() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# decide final module list given MINIMAL, ONLY, SKIP
compute_modules() {
  local base=("${DEFAULT_MODULES[@]}")
  (( MINIMAL )) && base=(zsh tmux nvim)

  local filtered=()

  if ((${#ONLY_MODULES[@]})); then
    # keep only those in ONLY
    local m
    for m in "${base[@]}"; do
      _arr_has "$m" "${ONLY_MODULES[@]}" && filtered+=("$m")
    done
  else
    filtered=("${base[@]}")
  fi

  if ((${#SKIP_MODULES[@]})); then
    local keep=()
    local m
    for m in "${filtered[@]}"; do
      _arr_has "$m" "${SKIP_MODULES[@]}" || keep+=("$m")
    done
    filtered=("${keep[@]}")
  fi

  printf '%s\n' "${filtered[@]}"
}


# flags
DRY_RUN=0
DO_FONTS=1
MINIMAL=0
DEBUG=0
SKIP_MODULES=()   # e.g., ("zsh" "tmux")
ONLY_MODULES=()   # e.g., ("nvim" "git")

# small util: split comma-separated lists into array
split_csv() {
  local IFS=','; read -ra __out <<<"$1"; printf '%s\n' "${__out[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --no-fonts)  DO_FONTS=0 ;;
    --minimal)   MINIMAL=1 ;;
    --debug)     DEBUG=1 ;;
    --skip)
      shift
      [[ $# -eq 0 ]] && { echo "ERROR: --skip needs a value"; exit 1; }
      while IFS= read -r item; do SKIP_MODULES+=("$item"); done < <(split_csv "$1")
      ;;
    --only)
      shift
      [[ $# -eq 0 ]] && { echo "ERROR: --only needs a value"; exit 1; }
      while IFS= read -r item; do ONLY_MODULES+=("$item"); done < <(split_csv "$1")
      ;;
    *)
      warn "Unknown flag: $1"
      ;;
  esac
  shift
done

# enable command tracing if --debug
(( DEBUG )) && set -x

# tee all stdout/stderr to logfile as well (append)
# (avoid double tee when headless nvim runs; it’s fine)
exec > >(tee -a "$LOGFILE") 2>&1

run() {
  if (( DRY_RUN )); then
    printf "[dry-run] %q " "$@"; echo
  else
    "$@"
  fi
}

# trap errors to show where it failed
trap 'err "Failed at line $LINENO: ${BASH_COMMAND}"' ERR

SUDO="$(need sudo && echo sudo || true)"

#====================#
# OS / PM detection  #
#====================#
OS="unknown"; PM="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  grep -qi microsoft /proc/version 2>/dev/null && OS="linux-wsl" || OS="linux"
  need apt-get && PM="apt"   || true
  need dnf     && PM="dnf"   || true
  need pacman  && PM="pacman"|| true
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OS="macos"; PM="brew"
else
  die "Unsupported OS: $OSTYPE"
fi

log "Flags: DRY_RUN=$DRY_RUN DO_FONTS=$DO_FONTS MINIMAL=$MINIMAL DEBUG=$DEBUG"
log "Detected: OSTYPE=$OSTYPE OS=$OS PM=$PM SUDO=${SUDO:-<none>}"
log "Repo cwd: $(pwd -P)"
log "ONLY_MODULES: ${ONLY_MODULES[*]:-(none)}"
log "SKIP_MODULES: ${SKIP_MODULES[*]:-(none)}"

#====================#
# Network check      #
#====================#
if ! ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
  warn "No network; installs may fail. Continuing anyway."
fi

#====================#
# Package installs   #
#====================#
apt_retry() {
  for i in 1 2 3; do
    run $SUDO apt-get "$@" && return 0 || { warn "apt-get $* failed ($i/3)"; sleep 2; }
  done
  return 1
}

install_linux_apt() {
  log "apt update"
  apt_retry update -y || die "apt update failed"

  local pkgs=(build-essential curl git unzip pkg-config ca-certificates
              zsh tmux stow ripgrep fd-find fzf
              neovim
              gcc g++ clang llvm clangd gdb cmake ninja-build
              python3 python3-pip)
  log "apt install base pkgs: ${pkgs[*]}"
  apt_retry install -y "${pkgs[@]}" || die "apt install failed"

  if need fdfind && ! need fd; then
    log "Creating fd shim -> fdfind"
    run $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
}

install_linux_dnf() {
  log "dnf groupinstall Development Tools"
  run $SUDO dnf -y groupinstall "Development Tools"
  log "dnf install packages"
  run $SUDO dnf -y install curl git unzip pkg-config neovim zsh tmux stow ripgrep fd-find fzf \
    gcc gcc-c++ clang llvm clang-tools-extra gdb cmake ninja-build python3 python3-pip
}

install_linux_pacman() {
  log "pacman install packages"
  run $SUDO pacman -Sy --noconfirm \
    base-devel curl git unzip pkgconf neovim zsh tmux stow ripgrep fd fzf \
    gcc clang lldb gdb cmake ninja python python-pip
}

install_macos_brew() {
  if ! need brew; then
    log "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)" || true
    eval "$(/usr/local/bin/brew shellenv)" || true
  fi
  log "brew update"
  run brew update
  log "brew install packages"
  run brew install coreutils curl git unzip stow zsh tmux ripgrep fd fzf neovim gcc llvm clang-format gdb cmake ninja python
}

install_packages() {
  case "$PM" in
    apt)    install_linux_apt ;;
    dnf)    install_linux_dnf ;;
    pacman) install_linux_pacman ;;
    brew)   install_macos_brew ;;
    *)      die "Unknown PM: $PM" ;;
  esac
}

#====================#
# Nerd Fonts         #
#====================#
have_nerd_font() { fc-list 2>/dev/null | grep -qi "nerd" || false; }

install_fonts_linux() {
  local zip="/tmp/FiraCode.zip"
  local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip"
  local fontdir="$HOME/.local/share/fonts"
  log "Fonts: downloading $url"
  run mkdir -p "$fontdir"
  run curl -fsSL "$url" -o "$zip" || { warn "Font download failed"; return; }
  log "Fonts: installing into $fontdir"
  run unzip -o "$zip" -d "$fontdir" && run fc-cache -fv || warn "Font cache update failed"
}

install_fonts_macos() {
  log "Fonts: installing $DEFAULT_FONT_MAC_CASK"
  run brew tap homebrew/cask-fonts
  run brew install --cask "$DEFAULT_FONT_MAC_CASK" || warn "Font cask failed"
}

ensure_fonts() {
  log "Fonts: DO_FONTS=$DO_FONTS"
  ((DO_FONTS)) || { warn "Skipping font install (--no-fonts)"; return; }
  if have_nerd_font; then
    log "Nerd Font already present"
    return
  fi
  case "$OS" in
    linux|linux-wsl) install_fonts_linux ;;
    macos)           install_fonts_macos ;;
  esac
  if ! have_nerd_font; then
    warn "Nerd Font still missing; Powerlevel10k icons may look wrong. On WSL, also set the Windows Terminal font."
  fi
}

#====================#
# Oh My Zsh          #
#====================#
ensure_ohmyzsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log "Oh My Zsh already installed"
    return
  fi
  log "Installing Oh My Zsh (non-interactive, KEEP_ZSHRC)"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
  || warn "OMZ installer returned non-zero"
}

ensure_p10k_theme() {
  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local THEME_DIR="$ZSH_CUSTOM/themes/powerlevel10k"
  log "Checking Powerlevel10k at $THEME_DIR"
  if [[ -d "$THEME_DIR" ]]; then
    log "Powerlevel10k present"
  else
    log "Cloning Powerlevel10k theme"
    run git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$THEME_DIR" || warn "p10k clone failed"
  fi
}

#====================#
# Stow dotfiles      #
#====================#
stow_dotfiles() {
  log "Stowing dotfiles into \$HOME"
  local repo_root; repo_root="$(cd "$(dirname "$0")" && pwd -P)"
  log "stow repo_root=$repo_root"

  # build final module list
  mapfile -t modules < <(compute_modules)
  log "stow modules (final): ${modules[*]}"
  [[ ${#modules[@]} -eq 0 ]] && { warn "No modules selected (after --only/--skip). Skipping stow."; return; }

  for m in "${modules[@]}"; do
    local src="$repo_root/$m"
    if [[ ! -d "$src" ]]; then
      warn "module '$m' not found at $src; skipping"
      continue
    fi

    log "stow module: $m (preview)"
    run stow -nv --target="$HOME" "$m" || warn "stow preview reported issues for '$m'"

    # conflict scan
    local conflicts=0
    while IFS= read -r -d '' file; do
      local rel="${file#"$src"/}"
      local target="$HOME/$rel"
      if [[ -e "$target" && ! -L "$target" ]]; then
        ((conflicts++))
        printf "  conflict: %s exists and is not a symlink\n" "$target"
      fi
    done < <(find "$src" -type f -print0)

    if (( conflicts > 0 )); then
      warn "$conflicts conflict(s) in '$m'. Skipping apply. (You can adopt with: stow --adopt --target=\"\$HOME\" $m )"
      continue
    fi

    log "stow module: $m (apply)"
    run stow --restow --target="$HOME" "$m"
    log "stowed: $m"
  done
}

#====================#
# zsh shell default  #
#====================#
maybe_set_default_shell() {
  log "Current shell: $SHELL"
  [[ "$SHELL" == *zsh ]] && { log "Default shell already zsh"; return 0; }
  if need chsh; then
    log "Setting default shell to zsh"
    run ${SUDO:-} chsh -s "$(command -v zsh)" "$USER" || warn "chsh failed; set default shell manually later"
  else
    warn "chsh not available; skipping default shell change"
  fi
}

#====================#
# tmux (TPM)         #
#====================#
setup_tmux() {
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    log "Installing TPM"
    run git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" || warn "TPM clone failed"
  fi
  log "Installing tmux plugins"
  run "$HOME/.tmux/plugins/tpm/bin/install_plugins" || true
}

#====================#
# Neovim bootstrap   #
#====================#
bootstrap_nvim() {
  local lazypath="$HOME/.local/share/nvim/lazy/lazy.nvim"
  log "lazy.nvim path: $lazypath"
  if [[ ! -d "$lazypath" ]]; then
    log "Installing lazy.nvim"
    run git clone --filter=blob:none https://github.com/folke/lazy.nvim.git --branch=stable "$lazypath"
  fi

  if ! need nvim; then
    warn "Neovim not found; skipping headless bootstrap"
    return
  fi

  log "Neovim headless: Lazy sync"
  run nvim --headless "+Lazy! sync" +qa || warn "Lazy sync failed (check Neovim config)"

  log "Neovim headless: MasonUpdate"
  run nvim --headless "+MasonUpdate" +qa || warn "MasonUpdate failed or Mason not configured yet (ok)"
}

#====================#
# Embedded (Linux)   #
#====================#
install_embedded_linux() {
  [[ "$PM" == "apt" ]] || { warn "Embedded toolchain step is apt-specific; skipping"; return; }
  log "Installing embedded toolchain (Linux/apt)"
  run $SUDO apt-get install -y gdb-multiarch openocd minicom gcc-arm-none-eabi binutils-arm-none-eabi || warn "Embedded tools skipped/failed"
}

#====================#
# Sanity report      #
#====================#
sanity_report() {
  log "Sanity report:"
  for c in git zsh tmux nvim stow rg fd fzf cmake g++ clangd gdb; do
    if need "$c"; then printf "  - %-7s: ok (%s)\n" "$c" "$(command -v "$c")"; else printf "  - %-7s: MISSING\n" "$c"; fi
  done
  if [[ "$OS" == "linux-wsl" ]]; then
    warn "WSL: set Windows Terminal font to a Nerd Font (e.g., '$DEFAULT_FONT') for icons."
  fi
}

#====================#
# Main               #
#====================#
main() {
  log "Starting bootstrap at $(now)"
  install_packages
  ensure_fonts
  ensure_ohmyzsh
  ensure_p10k_theme
  stow_dotfiles
  maybe_set_default_shell
  setup_tmux
  (( MINIMAL )) || bootstrap_nvim
  if [[ "$OS" == "linux" || "$OS" == "linux-wsl" ]]; then install_embedded_linux || true; fi
  sanity_report
  log "Done. Open a new terminal or: exec zsh"
}

main "$@"

