#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# Portable development-environment bootstrap
#
# Supported:
#   - Ubuntu / Debian / WSL             (apt)
#   - Fedora / RHEL-like systems        (dnf)
#   - Arch Linux                        (pacman)
#   - macOS                             (Homebrew)
#
# Repository layout expected beside this script:
#
#   zsh/.zshrc
#   zsh/ros2-tools.plugin.zsh           optional
#   tmux/.tmux.conf
#   nvim/.config/nvim/
#   git/.gitconfig                      optional
#
# GNU Stow links selected modules into $HOME.
# =============================================================================

# =============================================================================
# Defaults
# =============================================================================

DEFAULT_MODULES=(zsh tmux nvim git)

DEFAULT_FONT_NAME="FiraCode Nerd Font"
DEFAULT_FONT_ARCHIVE="FiraCode.zip"
DEFAULT_FONT_MAC_CASK="font-fira-code-nerd-font"

ROS2_PLUGIN_RELATIVE_PATH="zsh/ros2-tools.plugin.zsh"

# "stable" downloads the current upstream stable release at execution time.
# Set an exact version for fully reproducible editor binaries:
#
#   NEOVIM_VERSION=0.12.2 bash ./summon.sh
#
NEOVIM_VERSION="${NEOVIM_VERSION:-stable}"

NVIM_BOOTSTRAP_TIMEOUT="${NVIM_BOOTSTRAP_TIMEOUT:-1200}"
TREE_SITTER_CLI_MIN_VERSION="${TREE_SITTER_CLI_MIN_VERSION:-0.26.1}"
NVIM_PLUGIN_CONCURRENCY="${NVIM_PLUGIN_CONCURRENCY:-auto}"

LOGFILE="${DOTFILES_LOGFILE:-$HOME/.dotfiles-install.log}"

# =============================================================================
# Runtime flags
# =============================================================================

DRY_RUN=0
DEBUG=0
MINIMAL=0

DO_FONTS=1
DO_NVIM_PLUGINS=1
DO_TMUX_PLUGINS=1
DO_ZSH_PLUGINS=1
DO_EMBEDDED=1
DO_MASON_UPDATE=1
DO_SET_DEFAULT_SHELL=1

SKIP_MODULES=()
ONLY_MODULES=()

# =============================================================================
# Help
# =============================================================================

usage() {
  cat <<'EOF'
Portable development-environment bootstrap

Usage:
  bash ./summon.sh [OPTIONS]

Core options:
  -h, --help
      Show this help and exit.

  --dry-run
      Print commands without executing them.

  --debug
      Enable Bash execution tracing with set -x.

  --minimal
      Install core tools and stow selected dotfiles, but do not bootstrap:
        - external Oh My Zsh plugins
        - Neovim plugins
        - Mason registry/packages
        - tmux plugins
        - embedded-development tools

      Neovim itself and the Neovim configuration are still installed/stowed.

  --only MODULES
      Operate only on a comma-separated subset of Stow modules.

      Example:
        --only zsh,nvim

  --skip MODULES
      Skip a comma-separated subset of Stow modules.

      Example:
        --skip git,tmux

Fonts:
  --no-fonts
      Skip Nerd Font installation.

Neovim:
  --neovim-version VERSION
      Select the Neovim release.

      Values:
        stable       current upstream stable release
        0.12.2       exact upstream release

      The environment variable NEOVIM_VERSION provides the same setting.

  --nvim-plugins
      Restore Neovim plugins from lazy-lock.json.

  --no-nvim-plugins
      Do not clone lazy.nvim or restore Neovim plugins.

  --mason-update
      Refresh the Mason registry after restoring plugins.

  --no-mason-update
      Skip the Mason registry refresh.

Zsh:
  --zsh-plugins
      Install external Oh My Zsh plugins used by the managed .zshrc:
        - zsh-autosuggestions
        - zsh-syntax-highlighting

  --no-zsh-plugins
      Do not install external Oh My Zsh plugins.

tmux:
  --tmux-plugins
      Install TPM and restore tmux plugins.

  --no-tmux-plugins
      Do not clone TPM or install tmux plugins.

Other:
  --embedded
      Install optional embedded-development tools where supported.

  --no-embedded
      Skip optional embedded-development tools.

  --set-default-shell
      Attempt to set Zsh as the login shell.

  --no-set-default-shell
      Do not change the login shell.

Environment overrides:
  NEOVIM_VERSION
      "stable" or an exact version such as "0.12.2".

  NVIM_PLUGIN_CONCURRENCY
      Number of concurrent Lazy jobs, or "auto".
      Auto chooses a conservative value based on available RAM.

  NVIM_BOOTSTRAP_TIMEOUT
      Headless Neovim timeout in seconds. Default: 1200.

  DOTFILES_LOGFILE
      Override the log path. Default: ~/.dotfiles-install.log

Examples:
  bash ./summon.sh

  bash ./summon.sh --minimal --no-fonts

  bash ./summon.sh --only zsh,nvim --no-tmux-plugins

  bash ./summon.sh --neovim-version stable

  NEOVIM_VERSION=0.12.2 \
  NVIM_PLUGIN_CONCURRENCY=1 \
    bash ./summon.sh

Plugin-version policy:
  - Neovim is installed from an upstream stable release on Linux.
  - lazy.nvim is cloned from its stable branch.
  - Application plugins are restored from nvim/.config/nvim/lazy-lock.json.
  - The bootstrap uses "Lazy restore", not "Lazy sync", so plugin versions do
    not float during machine setup.
EOF
}

# =============================================================================
# Logging and helpers
# =============================================================================

need() {
  command -v "$1" >/dev/null 2>&1
}

now() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  printf '\033[1;32m==>\033[0m %s\n' "$*"
  printf '[%s] [INFO ] %s\n' "$(now)" "$*" >>"$LOGFILE"
}

warn() {
  printf '\033[1;33m!! \033[0m %s\n' "$*"
  printf '[%s] [WARN ] %s\n' "$(now)" "$*" >>"$LOGFILE"
}

err() {
  printf '\033[1;31mEE \033[0m %s\n' "$*" >&2
  printf '[%s] [ERROR] %s\n' "$(now)" "$*" >>"$LOGFILE"
}

die() {
  err "$*"
  exit 1
}

run() {
  if (( DRY_RUN )); then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

array_contains() {
  local needle="$1"
  shift

  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done

  return 1
}

split_csv() {
  local input="$1"
  local IFS=','

  read -ra values <<<"$input"
  printf '%s\n' "${values[@]}"
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P
}

module_selected() {
  local wanted="$1"
  local -a selected=()

  mapfile -t selected < <(compute_modules)
  array_contains "$wanted" "${selected[@]}"
}

# =============================================================================
# Argument parsing
# =============================================================================

while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;

    --dry-run)
      DRY_RUN=1
      ;;

    --debug)
      DEBUG=1
      ;;

    --minimal)
      MINIMAL=1
      DO_NVIM_PLUGINS=0
      DO_TMUX_PLUGINS=0
      DO_ZSH_PLUGINS=0
      DO_EMBEDDED=0
      DO_MASON_UPDATE=0
      ;;

    --no-fonts)
      DO_FONTS=0
      ;;

    --nvim-plugins)
      DO_NVIM_PLUGINS=1
      ;;

    --no-nvim-plugins)
      DO_NVIM_PLUGINS=0
      DO_MASON_UPDATE=0
      ;;

    --mason-update)
      DO_MASON_UPDATE=1
      ;;

    --no-mason-update)
      DO_MASON_UPDATE=0
      ;;

    --tmux-plugins)
      DO_TMUX_PLUGINS=1
      ;;

    --no-tmux-plugins)
      DO_TMUX_PLUGINS=0
      ;;

    --zsh-plugins)
      DO_ZSH_PLUGINS=1
      ;;

    --no-zsh-plugins)
      DO_ZSH_PLUGINS=0
      ;;

    --embedded)
      DO_EMBEDDED=1
      ;;

    --no-embedded)
      DO_EMBEDDED=0
      ;;

    --set-default-shell)
      DO_SET_DEFAULT_SHELL=1
      ;;

    --no-set-default-shell)
      DO_SET_DEFAULT_SHELL=0
      ;;

    --neovim-version)
      shift
      (( $# > 0 )) || die "--neovim-version requires a value"
      NEOVIM_VERSION="$1"
      ;;

    --only)
      shift
      (( $# > 0 )) || die "--only requires a comma-separated value"

      while IFS= read -r item; do
        [[ -n "$item" ]] && ONLY_MODULES+=("$item")
      done < <(split_csv "$1")
      ;;

    --skip)
      shift
      (( $# > 0 )) || die "--skip requires a comma-separated value"

      while IFS= read -r item; do
        [[ -n "$item" ]] && SKIP_MODULES+=("$item")
      done < <(split_csv "$1")
      ;;

    *)
      die "Unknown option: $1. Run '$0 --help'."
      ;;
  esac

  shift
done

(( DEBUG )) && set -x

mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"

exec > >(tee -a "$LOGFILE") 2>&1

trap 'err "Failed at line $LINENO: $BASH_COMMAND"' ERR

# =============================================================================
# Module selection
# =============================================================================

compute_modules() {
  local -a base=("${DEFAULT_MODULES[@]}")
  local -a filtered=()
  local module

  if (( ${#ONLY_MODULES[@]} > 0 )); then
    for module in "${base[@]}"; do
      array_contains "$module" "${ONLY_MODULES[@]}" &&
        filtered+=("$module")
    done
  else
    filtered=("${base[@]}")
  fi

  if (( ${#SKIP_MODULES[@]} > 0 )); then
    local -a kept=()

    for module in "${filtered[@]}"; do
      array_contains "$module" "${SKIP_MODULES[@]}" ||
        kept+=("$module")
    done

    filtered=("${kept[@]}")
  fi

  printf '%s\n' "${filtered[@]}"
}

# =============================================================================
# OS and package-manager detection
# =============================================================================

OS="unknown"
PM="unknown"

detect_platform() {
  case "$(uname -s)" in
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        OS="linux-wsl"
      else
        OS="linux"
      fi

      if need apt-get; then
        PM="apt"
      elif need dnf; then
        PM="dnf"
      elif need pacman; then
        PM="pacman"
      else
        die "No supported Linux package manager found"
      fi
      ;;

    Darwin)
      OS="macos"
      PM="brew"
      ;;

    *)
      die "Unsupported operating system: $(uname -s)"
      ;;
  esac
}

detect_platform

if need sudo; then
  SUDO="sudo"
else
  SUDO=""
fi

log "Detected OS=$OS package_manager=$PM"
log "Repository root: $(repo_root)"
log "Neovim release policy: $NEOVIM_VERSION"
log "Minimal mode: $MINIMAL"
log "Selected-only modules: ${ONLY_MODULES[*]:-(none)}"
log "Skipped modules: ${SKIP_MODULES[*]:-(none)}"

# =============================================================================
# Connectivity
# =============================================================================

check_network() {
  if need curl &&
     curl --head --silent --fail --max-time 5 https://github.com \
       >/dev/null 2>&1; then
    log "Network check passed"
  else
    warn "GitHub is not currently reachable; network operations may fail"
  fi
}

# =============================================================================
# Package installation
# =============================================================================

apt_retry() {
  local attempt

  for attempt in 1 2 3; do
    if run $SUDO apt-get "$@"; then
      return 0
    fi

    warn "apt-get $* failed ($attempt/3)"
    sleep 2
  done

  return 1
}

install_linux_apt() {
  log "Updating apt metadata"
  apt_retry update -y || die "apt update failed"

  local -a packages=(
    build-essential
    ca-certificates
    curl
    git
    unzip
    tar
    xz-utils
    pkg-config
    zsh
    tmux
    stow
    ripgrep
    fd-find
    fzf
    gcc
    g++
    clang
    llvm
    clangd
    gdb
    cmake
    ninja-build
    python3
    python3-pip
    fontconfig
  )

  log "Installing apt packages"
  apt_retry install -y "${packages[@]}" ||
    die "Base apt package installation failed"

  if need fdfind && ! need fd; then
    log "Creating fd compatibility link"
    run $SUDO ln -sfn "$(command -v fdfind)" /usr/local/bin/fd
  fi
}

install_linux_dnf() {
  log "Installing Fedora/RHEL development tools"

  run $SUDO dnf -y groupinstall "Development Tools" || true

  run $SUDO dnf -y install \
    ca-certificates curl git unzip tar xz pkgconf-pkg-config \
    zsh tmux stow ripgrep fd-find fzf \
    gcc gcc-c++ clang llvm clang-tools-extra gdb cmake ninja-build \
    python3 python3-pip fontconfig
}

install_linux_pacman() {
  log "Installing Arch Linux development tools"

  run $SUDO pacman -Sy --needed --noconfirm \
    base-devel ca-certificates curl git unzip tar xz pkgconf \
    zsh tmux stow ripgrep fd fzf \
    gcc clang lldb gdb cmake ninja python python-pip fontconfig
}

ensure_homebrew() {
  if need brew; then
    return 0
  fi

  log "Installing Homebrew"

  if (( DRY_RUN )); then
    printf '[dry-run] install Homebrew\n'
    return 0
  fi

  NONINTERACTIVE=1 \
    /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  [[ -x /opt/homebrew/bin/brew ]] &&
    eval "$(/opt/homebrew/bin/brew shellenv)"

  [[ -x /usr/local/bin/brew ]] &&
    eval "$(/usr/local/bin/brew shellenv)"
}

install_macos_brew() {
  ensure_homebrew

  log "Updating Homebrew"
  run brew update

  log "Installing Homebrew packages"
  run brew install \
    coreutils curl git unzip stow zsh tmux ripgrep fd fzf \
    gcc llvm gdb cmake ninja python fontconfig
}

install_base_packages() {
  case "$PM" in
    apt)
      install_linux_apt
      ;;
    dnf)
      install_linux_dnf
      ;;
    pacman)
      install_linux_pacman
      ;;
    brew)
      install_macos_brew
      ;;
    *)
      die "Unknown package manager: $PM"
      ;;
  esac
}

# =============================================================================
# User-local executable path
# =============================================================================

ensure_user_local_bin_path() {
  local line='export PATH="$HOME/.local/bin:$PATH"'
  local file

  export PATH="$HOME/.local/bin:$PATH"
  hash -r

  for file in "$HOME/.profile" "$HOME/.zprofile"; do
    if [[ -f "$file" ]] && grep -Fqx "$line" "$file"; then
      continue
    fi

    if [[ ! -e "$file" || ! -L "$file" ]]; then
      log "Ensuring ~/.local/bin is on PATH in $file"

      if (( DRY_RUN )); then
        printf '[dry-run] append %q to %q\n' "$line" "$file"
      else
        {
          printf '\n# Added by portable dotfiles bootstrap\n'
          printf '%s\n' "$line"
        } >>"$file"
      fi
    else
      warn "$file is a symlink managed by dotfiles; add this line to its source:"
      warn "  $line"
    fi
  done
}

# =============================================================================
# Neovim installation
# =============================================================================

installed_neovim_version() {
  need nvim || return 1

  nvim --version 2>/dev/null |
    head -n 1 |
    awk '{print $2}' |
    sed 's/^v//'
}

resolve_linux_neovim_asset() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf '%s\n' "nvim-linux-x86_64.tar.gz"
      ;;
    aarch64|arm64)
      printf '%s\n' "nvim-linux-arm64.tar.gz"
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_neovim_download_url() {
  local asset="$1"

  if [[ "$NEOVIM_VERSION" == "stable" ]]; then
    printf '%s\n' \
      "https://github.com/neovim/neovim-releases/releases/latest/download/$asset"
  else
    printf '%s\n' \
      "https://github.com/neovim/neovim-releases/releases/download/v${NEOVIM_VERSION}/$asset"
  fi
}

install_neovim_linux() {
  local asset
  asset="$(resolve_linux_neovim_asset)" ||
    {
      warn "No official Neovim archive mapping for $(uname -m)"
      return 1
    }

  local url
  url="$(resolve_neovim_download_url "$asset")"

  local install_root="$HOME/.local/opt"
  local destination="$install_root/nvim-${NEOVIM_VERSION}"
  local archive="/tmp/$asset"
  local extract_dir=""

  log "Installing upstream Neovim release '$NEOVIM_VERSION'"
  log "  URL: $url"
  log "  Destination: $destination"

  run mkdir -p "$install_root" "$HOME/.local/bin"

  run curl \
    --fail \
    --location \
    --retry 3 \
    --retry-delay 2 \
    --output "$archive" \
    "$url" ||
    {
      warn "Official Neovim download failed"
      return 1
    }

  if (( DRY_RUN )); then
    run tar -xzf "$archive" -C "$install_root"
    run ln -sfn "$destination/bin/nvim" "$HOME/.local/bin/nvim"
    return 0
  fi

  extract_dir="$(mktemp -d)"
  tar -xzf "$archive" -C "$extract_dir"

  local extracted
  extracted="$(
    find "$extract_dir" \
      -mindepth 1 \
      -maxdepth 1 \
      -type d \
      -name 'nvim-linux-*' \
      -print \
      -quit
  )"

  if [[ -z "$extracted" || ! -x "$extracted/bin/nvim" ]]; then
    rm -rf "$extract_dir" "$archive"
    warn "The Neovim archive layout was not recognized"
    return 1
  fi

  # For "stable", replace the stable slot on every explicit bootstrap run.
  rm -rf "$destination"
  mv "$extracted" "$destination"
  rm -rf "$extract_dir" "$archive"

  ln -sfn "$destination/bin/nvim" "$HOME/.local/bin/nvim"

  export PATH="$HOME/.local/bin:$PATH"
  hash -r

  log "Installed $(nvim --version | head -n 1)"
  log "Neovim executable selected by bootstrap: $(command -v nvim)"
  log "New shells must include $HOME/.local/bin before /usr/bin"
}

install_neovim_macos() {
  ensure_homebrew

  if [[ "$NEOVIM_VERSION" != "stable" ]]; then
    warn "Homebrew installs its current stable Neovim formula."
    warn "Exact NEOVIM_VERSION pinning is supported by this script on Linux."
  fi

  if brew list neovim >/dev/null 2>&1; then
    run brew upgrade neovim || true
  else
    run brew install neovim
  fi
}

install_neovim() {
  if ! module_selected nvim; then
    log "Neovim module is not selected; skipping Neovim installation"
    return 0
  fi

  case "$OS" in
    linux|linux-wsl)
      install_neovim_linux ||
        warn "Upstream Neovim installation failed"
      ;;
    macos)
      install_neovim_macos ||
        warn "Homebrew Neovim installation failed"
      ;;
  esac
}

# =============================================================================
# Tree-sitter CLI
# =============================================================================

version_at_least() {
  local actual="$1"
  local required="$2"

  [[ "$(printf '%s\n%s\n' "$required" "$actual" | sort -V | head -n 1)" == "$required" ]]
}

tree_sitter_cli_version() {
  need tree-sitter || return 1

  tree-sitter --version 2>/dev/null |
    awk '{print $2}' |
    head -n 1
}

install_tree_sitter_from_distro() {
  case "$PM" in
    apt)
      if apt-cache show tree-sitter-cli >/dev/null 2>&1; then
        run $SUDO apt-get install -y tree-sitter-cli
      else
        return 1
      fi
      ;;

    dnf)
      if dnf list --available tree-sitter-cli >/dev/null 2>&1 ||
         dnf list --installed tree-sitter-cli >/dev/null 2>&1; then
        run $SUDO dnf -y install tree-sitter-cli
      else
        return 1
      fi
      ;;

    pacman)
      run $SUDO pacman -S --needed --noconfirm tree-sitter-cli
      ;;

    brew)
      run brew install tree-sitter ||
        run brew upgrade tree-sitter ||
        true
      ;;

    *)
      return 1
      ;;
  esac
}

ensure_cargo() {
  need cargo && return 0

  case "$PM" in
    apt)
      run $SUDO apt-get install -y cargo
      ;;
    dnf)
      run $SUDO dnf -y install cargo
      ;;
    pacman)
      run $SUDO pacman -S --needed --noconfirm rust
      ;;
    brew)
      run brew install rust
      ;;
    *)
      return 1
      ;;
  esac
}

install_tree_sitter_cli() {
  module_selected nvim ||
    {
      log "Neovim module is not selected; skipping Tree-sitter CLI"
      return 0
    }

  local current=""
  current="$(tree_sitter_cli_version || true)"

  if [[ -n "$current" ]] &&
     version_at_least "$current" "$TREE_SITTER_CLI_MIN_VERSION"; then
    log "Tree-sitter CLI $current is already installed"
    return 0
  fi

  if [[ -n "$current" ]]; then
    warn "Tree-sitter CLI $current is older than required $TREE_SITTER_CLI_MIN_VERSION"
  else
    log "Tree-sitter CLI is not installed"
  fi

  log "Trying the native package manager first"

  if install_tree_sitter_from_distro; then
    current="$(tree_sitter_cli_version || true)"

    if [[ -n "$current" ]] &&
       version_at_least "$current" "$TREE_SITTER_CLI_MIN_VERSION"; then
      log "Installed Tree-sitter CLI $current from the native package manager"
      return 0
    fi

    warn "The distribution Tree-sitter CLI is missing or too old"
  fi

  log "Falling back to Cargo for Tree-sitter CLI $TREE_SITTER_CLI_MIN_VERSION"

  if ! ensure_cargo; then
    warn "Cargo is unavailable; Tree-sitter CLI installation skipped"
    return 0
  fi

  run cargo install \
    --locked \
    --force \
    --version "$TREE_SITTER_CLI_MIN_VERSION" \
    tree-sitter-cli ||
    {
      warn "Cargo could not install tree-sitter-cli"
      return 0
    }

  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
  hash -r

  current="$(tree_sitter_cli_version || true)"

  if [[ -z "$current" ]] ||
     ! version_at_least "$current" "$TREE_SITTER_CLI_MIN_VERSION"; then
    warn "Tree-sitter CLI is still unavailable after installation"
    warn "Ensure this directory is on PATH:"
    warn "  $HOME/.cargo/bin"
    return 0
  fi

  log "Installed Tree-sitter CLI $current"
}

# =============================================================================
# Fonts
# =============================================================================

have_nerd_font() {
  need fc-list &&
    fc-list 2>/dev/null |
      grep -qi "nerd"
}

install_fonts_linux() {
  local archive="/tmp/$DEFAULT_FONT_ARCHIVE"
  local font_dir="$HOME/.local/share/fonts"
  local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$DEFAULT_FONT_ARCHIVE"

  log "Installing $DEFAULT_FONT_NAME"

  run mkdir -p "$font_dir"

  run curl \
    --fail \
    --location \
    --retry 3 \
    --output "$archive" \
    "$url" ||
    {
      warn "Nerd Font download failed"
      return 0
    }

  run unzip -o "$archive" -d "$font_dir" ||
    {
      warn "Nerd Font extraction failed"
      return 0
    }

  need fc-cache &&
    run fc-cache -fv ||
    true
}

install_fonts_macos() {
  ensure_homebrew

  run brew install --cask "$DEFAULT_FONT_MAC_CASK" ||
    warn "Nerd Font cask installation failed"
}

ensure_fonts() {
  (( DO_FONTS )) ||
    {
      log "Skipping fonts (--no-fonts)"
      return 0
    }

  if have_nerd_font; then
    log "A Nerd Font is already installed"
    return 0
  fi

  case "$OS" in
    linux|linux-wsl)
      install_fonts_linux
      ;;
    macos)
      install_fonts_macos
      ;;
  esac

  if ! have_nerd_font; then
    warn "No Nerd Font was detected after installation"
  fi
}

# =============================================================================
# Oh My Zsh and Powerlevel10k
# =============================================================================

ensure_oh_my_zsh() {
  if ! module_selected zsh; then
    log "Zsh module is not selected; skipping Oh My Zsh"
    return 0
  fi

  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log "Oh My Zsh is already installed"
    return 0
  fi

  log "Installing Oh My Zsh non-interactively"

  if (( DRY_RUN )); then
    printf '[dry-run] install Oh My Zsh\n'
    return 0
  fi

  RUNZSH=no \
  CHSH=no \
  KEEP_ZSHRC=yes \
    sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" ||
    warn "Oh My Zsh installer returned a non-zero status"
}

ensure_powerlevel10k() {
  if ! module_selected zsh; then
    return 0
  fi

  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local destination="$zsh_custom/themes/powerlevel10k"

  if [[ -d "$destination/.git" ]]; then
    log "Powerlevel10k is already installed"
    return 0
  fi

  log "Installing Powerlevel10k"

  run mkdir -p "$(dirname "$destination")"

  run git clone \
    --depth=1 \
    https://github.com/romkatv/powerlevel10k.git \
    "$destination" ||
    warn "Powerlevel10k clone failed"
}

# =============================================================================
# External Oh My Zsh plugins
# =============================================================================

install_oh_my_zsh_plugin() {
  local plugin_name="$1"
  local repository="$2"

  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local destination="$zsh_custom/plugins/$plugin_name"

  if [[ -d "$destination/.git" ]]; then
    log "Oh My Zsh plugin is already installed: $plugin_name"
    return 0
  fi

  if [[ -e "$destination" ]]; then
    local backup="${destination}.broken.$(date +%Y%m%d-%H%M%S)"
    warn "Incomplete plugin directory detected:"
    warn "  $destination"
    warn "Moving it to:"
    warn "  $backup"
    run mv "$destination" "$backup"
  fi

  log "Installing Oh My Zsh plugin: $plugin_name"

  run mkdir -p "$(dirname "$destination")"

  run git clone \
    --depth=1 \
    "$repository" \
    "$destination" ||
    {
      warn "Failed to install Oh My Zsh plugin: $plugin_name"
      return 0
    }
}

setup_oh_my_zsh_plugins() {
  module_selected zsh ||
    {
      log "Zsh module is not selected; skipping external Zsh plugins"
      return 0
    }

  (( DO_ZSH_PLUGINS )) ||
    {
      log "Skipping external Oh My Zsh plugins"
      return 0
    }

  [[ -d "$HOME/.oh-my-zsh" ]] ||
    {
      warn "Oh My Zsh is unavailable; external plugins cannot be installed"
      return 0
    }

  install_oh_my_zsh_plugin \
    "zsh-autosuggestions" \
    "https://github.com/zsh-users/zsh-autosuggestions.git"

  install_oh_my_zsh_plugin \
    "zsh-syntax-highlighting" \
    "https://github.com/zsh-users/zsh-syntax-highlighting.git"

  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  [[ -f "$zsh_custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" ||
     -f "$zsh_custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] ||
    warn "zsh-autosuggestions was cloned but its entry file was not found"

  [[ -f "$zsh_custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh" ||
     -f "$zsh_custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] ||
    warn "zsh-syntax-highlighting was cloned but its entry file was not found"
}

# =============================================================================
# Stow conflict handling
# =============================================================================

backup_generated_zshrc() {
  local root="$1"
  local source="$root/zsh/.zshrc"
  local target="$HOME/.zshrc"

  [[ -f "$source" ]] || return 0
  [[ -e "$target" && ! -L "$target" ]] || return 0

  local backup="${target}.pre-dotfiles.$(date +%Y%m%d-%H%M%S)"

  log "Backing up existing ~/.zshrc before Stow"
  log "  $target -> $backup"

  run mv "$target" "$backup"
}

stow_extra_args_for_module() {
  local module="$1"

  if [[ "$module" == "zsh" ]]; then
    printf '%s\n' \
      '--ignore=(^|/)ros2-tools[.]plugin[.]zsh$'
  fi
}

stow_dotfiles() {
  local root
  root="$(repo_root)"

  backup_generated_zshrc "$root"

  local -a modules=()
  mapfile -t modules < <(compute_modules)

  if (( ${#modules[@]} == 0 )); then
    warn "No Stow modules were selected"
    return 0
  fi

  log "Stow modules: ${modules[*]}"

  local module
  for module in "${modules[@]}"; do
    local source="$root/$module"

    if [[ ! -d "$source" ]]; then
      warn "Stow module '$module' does not exist at $source"
      continue
    fi

    local -a extra_args=()
    mapfile -t extra_args < <(
      stow_extra_args_for_module "$module"
    )

    log "Previewing Stow module: $module"

    if ! run stow \
      -nv \
      "${extra_args[@]}" \
      --target="$HOME" \
      "$module"; then
      warn "Stow preview reported a problem for '$module'"
    fi

    local conflicts=0

    while IFS= read -r -d '' file; do
      local relative="${file#"$source"/}"

      if [[ "$module" == "zsh" &&
            "$relative" == "ros2-tools.plugin.zsh" ]]; then
        continue
      fi

      local target="$HOME/$relative"

      if [[ -e "$target" && ! -L "$target" ]]; then
        (( ++conflicts ))
        printf '  conflict: %s exists and is not a symlink\n' "$target"
      fi
    done < <(find "$source" -type f -print0)

    if (( conflicts > 0 )); then
      warn "$conflicts conflict(s) found in '$module'; skipping it"
      warn "Review before using:"
      warn "  stow --adopt --target=\"$HOME\" $module"
      continue
    fi

    log "Applying Stow module: $module"

    run stow \
      --restow \
      "${extra_args[@]}" \
      --target="$HOME" \
      "$module"
  done
}

# =============================================================================
# ROS 2 Zsh plugin
# =============================================================================

setup_ros2_tools_plugin() {
  module_selected zsh ||
    {
      log "Zsh module is not selected; skipping ROS 2 plugin"
      return 0
    }

  local root
  root="$(repo_root)"

  local source="$root/$ROS2_PLUGIN_RELATIVE_PATH"
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local destination_dir="$zsh_custom/plugins/ros2-tools"
  local destination="$destination_dir/ros2-tools.plugin.zsh"

  if [[ ! -f "$source" ]]; then
    log "No ROS 2 Zsh plugin source found; skipping"
    return 0
  fi

  log "Validating ROS 2 plugin"
  run zsh -n "$source" ||
    die "Invalid Zsh syntax in $source"

  log "Installing ROS 2 plugin"
  log "  source:      $source"
  log "  destination: $destination"

  run mkdir -p "$destination_dir"
  run install -m 0644 "$source" "$destination"

  run zsh -n "$destination" ||
    die "Installed ROS 2 plugin is invalid"

  if (( ! DRY_RUN )); then
    cmp -s "$source" "$destination" ||
      die "Installed ROS 2 plugin differs from its source"
  fi
}

# =============================================================================
# Login shell
# =============================================================================

maybe_set_default_shell() {
  (( DO_SET_DEFAULT_SHELL )) ||
    {
      log "Skipping login-shell change"
      return 0
    }

  module_selected zsh ||
    return 0

  [[ "${SHELL:-}" == *zsh ]] &&
    {
      log "The login shell is already Zsh"
      return 0
    }

  if ! need chsh; then
    warn "chsh is unavailable; set Zsh manually if desired"
    return 0
  fi

  log "Attempting to set Zsh as the login shell"

  if ! run chsh -s "$(command -v zsh)"; then
    warn "chsh failed; run this manually:"
    warn "  chsh -s \"$(command -v zsh)\""
  fi
}

# =============================================================================
# tmux plugins
# =============================================================================

setup_tmux_plugins() {
  module_selected tmux ||
    {
      log "tmux module is not selected; skipping TPM"
      return 0
    }

  (( DO_TMUX_PLUGINS )) ||
    {
      log "Skipping tmux plugins"
      return 0
    }

  local tpm="$HOME/.tmux/plugins/tpm"

  if [[ ! -d "$tpm/.git" ]]; then
    if [[ -e "$tpm" ]]; then
      local backup="${tpm}.broken.$(date +%Y%m%d-%H%M%S)"
      warn "Existing TPM directory is incomplete; moving it to $backup"
      run mv "$tpm" "$backup"
    fi

    log "Installing TPM"

    run git clone \
      --depth=1 \
      https://github.com/tmux-plugins/tpm \
      "$tpm" ||
      {
        warn "TPM clone failed"
        return 0
      }
  fi

  if [[ -x "$tpm/bin/install_plugins" ]]; then
    log "Installing tmux plugins"
    run "$tpm/bin/install_plugins" ||
      warn "One or more tmux plugins failed to install"
  fi
}

# =============================================================================
# Neovim plugins
# =============================================================================

detect_lazy_concurrency() {
  if [[ "$NVIM_PLUGIN_CONCURRENCY" != "auto" ]]; then
    printf '%s\n' "$NVIM_PLUGIN_CONCURRENCY"
    return 0
  fi

  local memory_mb=0

  if [[ "$OS" == "macos" ]]; then
    memory_mb="$(
      sysctl -n hw.memsize 2>/dev/null |
        awk '{print int($1 / 1024 / 1024)}'
    )"
  elif [[ -r /proc/meminfo ]]; then
    memory_mb="$(
      awk '/MemTotal:/ {print int($2 / 1024)}' /proc/meminfo
    )"
  fi

  if (( memory_mb > 0 && memory_mb < 4096 )); then
    printf '%s\n' 1
  elif (( memory_mb > 0 && memory_mb < 8192 )); then
    printf '%s\n' 2
  else
    printf '%s\n' 4
  fi
}

validate_lazy_lockfile() {
  local lockfile="$1"

  python3 - "$lockfile" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

with path.open(encoding="utf-8") as stream:
    data = json.load(stream)

if not isinstance(data, dict):
    raise SystemExit("lazy-lock.json must contain a JSON object")

for name, entry in data.items():
    if not isinstance(name, str):
        raise SystemExit("lazy-lock.json contains a non-string plugin name")

    if not isinstance(entry, dict):
        raise SystemExit(f"invalid lock entry for {name}")

    commit = entry.get("commit")
    if not isinstance(commit, str) or not commit:
        raise SystemExit(f"missing commit for {name}")
PY
}

bootstrap_neovim_plugins() {
  module_selected nvim ||
    {
      log "Neovim module is not selected; skipping plugins"
      return 0
    }

  (( DO_NVIM_PLUGINS )) ||
    {
      log "Skipping Neovim plugins"
      return 0
    }

  need nvim ||
    {
      warn "Neovim is unavailable; skipping plugin bootstrap"
      return 0
    }

  local root
  root="$(repo_root)"

  # The authoritative lockfile lives in the dotfiles repository:
  #
  #   dev-env/dotfiles/nvim/.config/nvim/lazy-lock.json
  #
  # Because the nvim module is stowed, Neovim should see the same file at:
  #
  #   ~/.config/nvim/lazy-lock.json
  #
  local repository_lockfile="$root/nvim/.config/nvim/lazy-lock.json"
  local active_lockfile="$HOME/.config/nvim/lazy-lock.json"

  if [[ ! -f "$repository_lockfile" ]]; then
    warn "No repository lazy-lock.json found:"
    warn "  $repository_lockfile"
    warn "Refusing a floating plugin installation"
    return 0
  fi

  if ! validate_lazy_lockfile "$repository_lockfile"; then
    warn "Repository lazy-lock.json is invalid; plugin restoration skipped"
    return 0
  fi

  if [[ ! -f "$active_lockfile" ]]; then
    warn "Neovim cannot see the stowed lazy-lock.json:"
    warn "  $active_lockfile"
    warn "Expected repository source:"
    warn "  $repository_lockfile"
    warn "Check that the nvim Stow module was applied successfully"
    return 0
  fi

  local repository_lockfile_real
  local active_lockfile_real

  repository_lockfile_real="$(readlink -f "$repository_lockfile")"
  active_lockfile_real="$(readlink -f "$active_lockfile")"

  if [[ "$repository_lockfile_real" != "$active_lockfile_real" ]]; then
    warn "The active Neovim lockfile does not resolve to the repository lockfile"
    warn "  repository: $repository_lockfile_real"
    warn "  active:     $active_lockfile_real"
    warn "Plugin restoration skipped to avoid using the wrong versions"
    return 0
  fi

  local lazypath="$HOME/.local/share/nvim/lazy/lazy.nvim"

  if [[ ! -d "$lazypath/.git" ]]; then
    if [[ -e "$lazypath" ]]; then
      local backup="${lazypath}.broken.$(date +%Y%m%d-%H%M%S)"
      warn "Existing lazy.nvim checkout is incomplete; moving it to $backup"
      run mv "$lazypath" "$backup"
    fi

    log "Installing lazy.nvim from its stable branch"

    run mkdir -p "$(dirname "$lazypath")"

    run git clone \
      --filter=blob:none \
      --single-branch \
      --branch=stable \
      https://github.com/folke/lazy.nvim.git \
      "$lazypath" ||
      {
        warn "lazy.nvim installation failed"
        return 0
      }
  fi

  if ! need timeout; then
    warn "The timeout command is unavailable"
    warn "Refusing unattended Neovim plugin restoration"
    return 0
  fi

  local concurrency
  concurrency="$(detect_lazy_concurrency)"

  log "Restoring Neovim plugins from lazy-lock.json"
  log "  Neovim:     $(nvim --version | head -n 1)"
  log "  Lockfile:   $repository_lockfile"
  log "  Concurrency: $concurrency"
  log "  Timeout:     ${NVIM_BOOTSTRAP_TIMEOUT}s"

  if ! (
    ulimit -n 1024 2>/dev/null || true

    export MALLOC_ARENA_MAX=2
    export GIT_OPTIONAL_LOCKS=0

    timeout \
      --signal=TERM \
      --kill-after=30s \
      "${NVIM_BOOTSTRAP_TIMEOUT}s" \
      nice -n 10 \
      nvim --headless \
        "+lua require('lazy.core.config').options.concurrency=${concurrency}" \
        "+Lazy! restore" \
        +qa
  ); then
    warn "Neovim plugin restoration failed or timed out"
    warn "The overall bootstrap will continue"
    warn "Inspect later with: nvim +Lazy"
    return 0
  fi

  log "Neovim plugins were restored to locked commits"

  local treesitter_plugin="$HOME/.local/share/nvim/lazy/nvim-treesitter"

  if [[ ! -d "$treesitter_plugin" ]]; then
    warn "nvim-treesitter is not installed."
    warn "Ensure the Neovim plugin specification includes:"
    warn "  nvim-treesitter/nvim-treesitter"
    warn "and commit its entry in lazy-lock.json."
  else
    log "nvim-treesitter plugin is installed"
  fi

  (( DO_MASON_UPDATE )) ||
    {
      log "Skipping Mason registry refresh"
      return 0
    }

  log "Refreshing Mason registry"

  if ! timeout \
    --signal=TERM \
    --kill-after=30s \
    "${NVIM_BOOTSTRAP_TIMEOUT}s" \
    nice -n 10 \
    nvim --headless \
      "+MasonUpdate" \
      +qa; then
    warn "Mason registry refresh failed or timed out"
  fi
}

# =============================================================================
# Embedded-development tools
# =============================================================================

install_embedded_tools() {
  (( DO_EMBEDDED )) ||
    {
      log "Skipping embedded-development tools"
      return 0
    }

  case "$PM" in
    apt)
      log "Installing embedded-development tools"

      run $SUDO apt-get install -y \
        gdb-multiarch \
        openocd \
        minicom \
        gcc-arm-none-eabi \
        binutils-arm-none-eabi ||
        warn "Some embedded tools could not be installed"
      ;;

    brew)
      log "Installing available embedded-development tools"

      run brew install openocd arm-none-eabi-gcc ||
        warn "Some embedded tools could not be installed"
      ;;

    *)
      warn "Embedded tool installation is not implemented for $PM"
      ;;
  esac
}

# =============================================================================
# Sanity report
# =============================================================================

sanity_report() {
  log "Sanity report"

  local command_name

  for command_name in \
    git zsh tmux nvim stow rg fd fzf cmake gcc g++ clang clangd gdb python3
  do
    if need "$command_name"; then
      printf '  - %-8s ok      %s\n' \
        "$command_name" \
        "$(command -v "$command_name")"
    else
      printf '  - %-8s MISSING\n' "$command_name"
    fi
  done

  if need nvim; then
    printf '  - %-8s %s\n' \
      "nvim-ver" \
      "$(nvim --version | head -n 1)"
  fi

  local ros_plugin="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/ros2-tools/ros2-tools.plugin.zsh"

  if [[ -f "$ros_plugin" ]]; then
    printf '  - %-8s ok      %s\n' "ros2-zsh" "$ros_plugin"
  elif module_selected zsh; then
    printf '  - %-8s optional/not-installed\n' "ros2-zsh"
  fi

  if [[ "$OS" == "linux-wsl" ]]; then
    warn "WSL: select a Nerd Font in the Windows terminal settings"
  fi

  if (( MINIMAL )); then
    printf '\nMinimal mode completed without plugin bootstrapping.\n'
  fi
}

# =============================================================================
# Main
# =============================================================================

main() {
  ensure_user_local_bin_path

  log "Starting bootstrap at $(now)"

  check_network
  install_base_packages
  install_neovim
  install_tree_sitter_cli
  ensure_fonts

  ensure_oh_my_zsh
  ensure_powerlevel10k
  setup_oh_my_zsh_plugins

  stow_dotfiles
  setup_ros2_tools_plugin

  maybe_set_default_shell

  setup_tmux_plugins
  bootstrap_neovim_plugins
  install_embedded_tools

  sanity_report

  log "Done"
  log "Open a new terminal or run: exec zsh"
}

main "$@"
