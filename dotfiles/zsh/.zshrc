# -------------------------
# Paths
# -------------------------
typeset -U path PATH

path=(
  $HOME/.local/bin
  $HOME/bin
  /usr/local/bin
  /usr/bin
  /bin
  /usr/sbin
  /sbin
  /home/nelmensh/Downloads/flutter/bin
  $path
)

export PATH

# -------------------------
# Oh My Zsh / Theme
# -------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(

  git
  docker
  docker-compose
  sudo
  extract
  colored-man-pages
  command-not-found
  zsh-autosuggestions
  zsh-syntax-highlighting
)
bindkey -v

source $ZSH/oh-my-zsh.sh

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# -------------------------
# Editor
# -------------------------
export EDITOR=nvim
export VISUAL=nvim

# -------------------------
# Safety
# -------------------------
export IGNOREEOF=3


# =============================================================================
# Lazy ROS 2 plugin loader
# =============================================================================

rosload() {
  local plugin_file="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/ros2-tools/ros2-tools.plugin.zsh"

  if [[ -n "${ROS2_TOOLS_LOADED:-}" ]]; then
    echo "ROS 2 tools are already loaded."
    return 0
  fi

  if [[ ! -r "$plugin_file" ]]; then
    echo "ROS 2 tools plugin was not found:"
    echo "  $plugin_file"
    return 1
  fi

  source "$plugin_file" || return 1

  echo "ROS 2 tools loaded."
  echo
  echo "Use:"
  echo "  ru              activate installed ROS only"
  echo "  rw WORKSPACE    activate a workspace"
  echo "  rh              show all commands"
}

# Load the plugin and activate a workspace in one command.
roswork() {
  local workspace="${1:-}"

  if [[ -z "$workspace" ]]; then
    echo "Usage:"
    echo "  roswork WORKSPACE_NAME"
    return 1
  fi

  rosload || return 1
  ros_workspace_use "$workspace"
}

alias rl='rosload'
alias rosw='roswork'# ------------------------------------------------------------
#  Aliases 
# ------------------------------------------------------------
alias zshrc='nvim ~/.zshrc'
alias reload='source ~/.zshrc'
