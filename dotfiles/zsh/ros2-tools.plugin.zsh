# =============================================================================
# Generic ROS 2 workspace tools for Oh My Zsh
#
# File:
#   ~/.oh-my-zsh/custom/plugins/ros2-tools/ros2-tools.plugin.zsh
#
# Design:
#   - Loaded only when rosload is called from ~/.zshrc.
#   - Uses installed ROS underlays only.
#   - Supports multiple generic colcon workspaces.
#   - Does not clone repositories or build ROS itself.
#   - Lists only explicitly registered workspaces.
# =============================================================================

if [[ -n "${ROS2_TOOLS_LOADED:-}" ]]; then
  return 0
fi

typeset -g ROS2_TOOLS_LOADED=1

# =============================================================================
# Configuration
# =============================================================================

typeset -g ROS2_DISTRO_NAME="${ROS2_DISTRO_NAME:-lyrical}"

# Existing projects can remain under ~/workspace. A marker file controls which
# directories appear in the managed ROS workspace list.
typeset -g ROS2_WORKSPACES_ROOT="${ROS2_WORKSPACES_ROOT:-$HOME/workspace}"
typeset -g ROS2_WORKSPACE_MARKER="${ROS2_WORKSPACE_MARKER:-.ros2-workspace}"

# Empty means that only the configured underlay is active.
typeset -g ROS2_ACTIVE_WS=""

if (( ! ${+ROS2_UNDERLAY_SETUPS} )); then
  typeset -ga ROS2_UNDERLAY_SETUPS=(
    "/opt/ros/${ROS2_DISTRO_NAME}/setup.zsh"
  )
else
  typeset -ga ROS2_UNDERLAY_SETUPS
fi

# =============================================================================
# Base environment storage
# =============================================================================

typeset -g _ROS2_BASE_ENV_CAPTURED=0
typeset -ga _ROS2_BASE_PATH=()

typeset -g _ROS2_BASE_LD_LIBRARY_PATH=""
typeset -g _ROS2_BASE_PKG_CONFIG_PATH=""
typeset -g _ROS2_BASE_CMAKE_PREFIX_PATH=""
typeset -g _ROS2_BASE_PYTHONPATH=""

# =============================================================================
# Output helpers
# =============================================================================

_ros2_info() {
  print -P "%F{green}ROS 2:%f $*"
}

_ros2_warning() {
  print -P "%F{yellow}ROS 2 warning:%f $*"
}

_ros2_error() {
  print -P "%F{red}ROS 2 error:%f $*"
}

# =============================================================================
# Generic internal helpers
# =============================================================================

_ros2_require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    _ros2_error "required command not found: $command_name"
    return 1
  fi
}

_ros2_restore_variable() {
  local variable_name="$1"
  local saved_value="$2"

  if [[ -n "$saved_value" ]]; then
    export "${variable_name}=${saved_value}"
  else
    unset "$variable_name"
  fi
}

_ros2_deactivate_conda() {
  if (( $+functions[conda] || $+commands[conda] )); then
    while [[ -n "${CONDA_PREFIX:-}" ]]; do
      conda deactivate >/dev/null 2>&1 || break
    done
  fi

  unset CONDA_PREFIX
  unset CONDA_DEFAULT_ENV
  unset CONDA_PROMPT_MODIFIER
  unset CONDA_SHLVL
  unset VIRTUAL_ENV
}

_ros2_capture_base_environment() {
  if (( _ROS2_BASE_ENV_CAPTURED )); then
    return 0
  fi

  _ros2_deactivate_conda

  _ROS2_BASE_PATH=("${path[@]}")
  _ROS2_BASE_LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}"
  _ROS2_BASE_PKG_CONFIG_PATH="${PKG_CONFIG_PATH-}"
  _ROS2_BASE_CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH-}"
  _ROS2_BASE_PYTHONPATH="${PYTHONPATH-}"

  _ROS2_BASE_ENV_CAPTURED=1
}

_ros2_reset_environment() {
  _ros2_deactivate_conda
  _ros2_capture_base_environment

  unset AMENT_PREFIX_PATH
  unset COLCON_PREFIX_PATH
  unset CMAKE_PREFIX_PATH

  unset ROS_DISTRO
  unset ROS_VERSION
  unset ROS_PYTHON_VERSION

  unset PYTHONHOME
  unset PYTHON_EXECUTABLE
  unset Python_EXECUTABLE
  unset Python3_EXECUTABLE
  unset VIRTUAL_ENV

  path=("${_ROS2_BASE_PATH[@]}")
  typeset -U path PATH
  export PATH

  _ros2_restore_variable LD_LIBRARY_PATH "$_ROS2_BASE_LD_LIBRARY_PATH"
  _ros2_restore_variable PKG_CONFIG_PATH "$_ROS2_BASE_PKG_CONFIG_PATH"
  _ros2_restore_variable CMAKE_PREFIX_PATH "$_ROS2_BASE_CMAKE_PREFIX_PATH"
  _ros2_restore_variable PYTHONPATH "$_ROS2_BASE_PYTHONPATH"

  rehash
}

_ros2_source_underlays() {
  _ros2_reset_environment

  local setup_file

  for setup_file in "${ROS2_UNDERLAY_SETUPS[@]}"; do
    if [[ ! -r "$setup_file" ]]; then
      _ros2_error "underlay setup script was not found:"
      echo "  $setup_file"
      return 1
    fi

    source "$setup_file" || {
      _ros2_error "failed to source underlay:"
      echo "  $setup_file"
      return 1
    }
  done
}

_ros2_normalize_path() {
  local input_path="$1"

  input_path="${input_path/#\~/$HOME}"
  print -r -- "${input_path:A}"
}

_ros2_workspace_path() {
  local reference="$1"
  local workspace

  if [[ "$reference" == /* ||
        "$reference" == ./* ||
        "$reference" == ../* ||
        "$reference" == "~"* ||
        "$reference" == */* ]]; then
    workspace="$(_ros2_normalize_path "$reference")"
  else
    workspace="$(_ros2_normalize_path "$ROS2_WORKSPACES_ROOT/$reference")"
  fi

  print -r -- "$workspace"
}

_ros2_resolve_workspace() {
  local reference="${1:-}"
  local workspace

  if [[ -z "$reference" ]]; then
    if [[ -n "$ROS2_ACTIVE_WS" && -d "$ROS2_ACTIVE_WS/src" ]]; then
      print -r -- "$ROS2_ACTIVE_WS"
      return 0
    fi

    _ros2_error "no workspace is active."
    echo
    echo "Activate one:"
    echo "  rw WORKSPACE_NAME"
    echo
    echo "Create one:"
    echo "  rwc WORKSPACE_NAME"
    return 1
  fi

  workspace="$(_ros2_workspace_path "$reference")"

  if [[ ! -d "$workspace/src" ]]; then
    _ros2_error "workspace was not found:"
    echo "  $workspace"
    echo
    echo "Expected directory:"
    echo "  $workspace/src"
    return 1
  fi

  print -r -- "$workspace"
}

_ros2_active_workspace() {
  _ros2_resolve_workspace ""
}

_ros2_is_registered_workspace() {
  local workspace="$1"
  [[ -d "$workspace/src" && -f "$workspace/$ROS2_WORKSPACE_MARKER" ]]
}

_ros2_activate_workspace_environment() {
  local workspace="$1"

  _ros2_source_underlays || return 1

  if [[ -f "$workspace/install/setup.zsh" ]]; then
    source "$workspace/install/setup.zsh" || {
      _ros2_error "failed to source workspace overlay:"
      echo "  $workspace/install/setup.zsh"
      return 1
    }
  fi

  ROS2_ACTIVE_WS="$workspace"
  export _colcon_cd_root="$workspace"
}

_ros2_activate_current_environment() {
  if [[ -n "${ROS2_ACTIVE_WS:-}" && -d "$ROS2_ACTIVE_WS/src" ]]; then
    _ros2_activate_workspace_environment "$ROS2_ACTIVE_WS"
  else
    _ros2_source_underlays
  fi
}

# =============================================================================
# Underlay commands
# =============================================================================

ros_underlay_activate() {
  _ros2_source_underlays || return 1
  ROS2_ACTIVE_WS=""

  _ros2_info "underlay environment activated."

  echo
  echo "Configured underlays:"

  local setup_file
  for setup_file in "${ROS2_UNDERLAY_SETUPS[@]}"; do
    echo "  $setup_file"
  done

  echo
  echo "ROS distribution:"
  echo "  ${ROS_DISTRO:-not detected}"

  echo
  echo "Python:"
  echo "  $(command -v python3)"
}

ros_underlay_list() {
  echo "Configured ROS 2 underlays:"
  echo

  local index=1
  local setup_file

  for setup_file in "${ROS2_UNDERLAY_SETUPS[@]}"; do
    if [[ -r "$setup_file" ]]; then
      printf "  %d. [available] %s\n" "$index" "$setup_file"
    else
      printf "  %d. [missing]   %s\n" "$index" "$setup_file"
    fi

    (( index++ ))
  done
}

# =============================================================================
# Workspace creation, registration, and activation
# =============================================================================

ros_workspace_create() {
  local reference="${1:-}"

  if [[ -z "$reference" ]]; then
    echo "Usage:"
    echo "  rwc WORKSPACE_NAME"
    echo "  rwc PATH"
    return 1
  fi

  local workspace
  workspace="$(_ros2_workspace_path "$reference")"

  mkdir -p "$workspace/src" || {
    _ros2_error "failed to create workspace:"
    echo "  $workspace"
    return 1
  }

  touch "$workspace/$ROS2_WORKSPACE_MARKER" || return 1
  ros_workspace_use "$workspace"
}

ros_workspace_register() {
  local workspace
  workspace="$(_ros2_resolve_workspace "${1:-}")" || return 1

  touch "$workspace/$ROS2_WORKSPACE_MARKER" || return 1

  _ros2_info "workspace registered:"
  echo "  $workspace"
}

ros_workspace_unregister() {
  local workspace
  workspace="$(_ros2_resolve_workspace "${1:-}")" || return 1

  rm -f "$workspace/$ROS2_WORKSPACE_MARKER"

  _ros2_info "workspace removed from the managed list:"
  echo "  $workspace"
  echo
  echo "No workspace files were deleted."
}

ros_workspace_use() {
  local workspace
  workspace="$(_ros2_resolve_workspace "${1:-}")" || return 1

  _ros2_activate_workspace_environment "$workspace" || return 1
  cd "$workspace" || return 1

  _ros2_info "workspace activated:"
  echo "  $workspace"

  if [[ ! -f "$workspace/$ROS2_WORKSPACE_MARKER" ]]; then
    echo
    _ros2_warning "this workspace is not registered in rwl."
    echo "Register it with:"
    echo "  rwreg $workspace"
  fi

  if [[ -f "$workspace/install/setup.zsh" ]]; then
    echo
    echo "Overlay sourced:"
    echo "  $workspace/install/setup.zsh"
  else
    echo
    _ros2_warning "workspace has not been built yet."
    echo "Build it with:"
    echo "  rwb"
  fi
}

ros_workspace_list() {
  mkdir -p "$ROS2_WORKSPACES_ROOT"

  echo "Managed ROS 2 workspaces:"
  echo "  $ROS2_WORKSPACES_ROOT"
  echo

  local found=0
  local workspace

  for workspace in "$ROS2_WORKSPACES_ROOT"/*(/N); do
    if _ros2_is_registered_workspace "$workspace"; then
      (( found++ ))

      if [[ "$workspace" == "$ROS2_ACTIVE_WS" ]]; then
        printf "  * %-30s %s\n" "${workspace:t}" "$workspace"
      else
        printf "    %-30s %s\n" "${workspace:t}" "$workspace"
      fi
    fi
  done

  if (( found == 0 )); then
    echo "  No registered ROS workspaces found."
    echo
    echo "Create one:"
    echo "  rwc WORKSPACE_NAME"
    echo
    echo "Register an existing one:"
    echo "  rwreg PATH"
  fi
}

ros_workspace_info() {
  local workspace
  workspace="$(_ros2_resolve_workspace "${1:-}")" || return 1

  echo "Workspace:"
  echo "  $workspace"

  echo
  echo "Registered:"
  if [[ -f "$workspace/$ROS2_WORKSPACE_MARKER" ]]; then
    echo "  yes"
  else
    echo "  no"
  fi

  echo
  echo "Generated directories:"
  [[ -d "$workspace/build" ]] && echo "  build/   present" || echo "  build/   missing"
  [[ -d "$workspace/install" ]] && echo "  install/ present" || echo "  install/ missing"
  [[ -d "$workspace/log" ]] && echo "  log/     present" || echo "  log/     missing"

  echo
  echo "Packages:"

  (
    _ros2_source_underlays || exit 1

    command colcon list \
      --base-paths "$workspace/src" \
      2>/dev/null |
      sed 's/^/  /'
  )
}

ros_workspace_src() {
  local workspace
  workspace="$(_ros2_resolve_workspace "${1:-}")" || return 1
  cd "$workspace/src" || return 1
}

ros_workspace_root() {
  local workspace
  workspace="$(_ros2_resolve_workspace "${1:-}")" || return 1
  cd "$workspace" || return 1
}

ros_workspace_tree() {
  local workspace
  workspace="$(_ros2_resolve_workspace "${1:-}")" || return 1

  if command -v tree >/dev/null 2>&1; then
    tree -L 4 "$workspace"
  else
    find "$workspace" -maxdepth 4 -print
  fi
}

# =============================================================================
# Generic ROS and colcon wrappers
# =============================================================================

ros_cli() {
  _ros2_activate_current_environment || return 1
  command ros2 "$@"
}

ros_colcon() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  _ros2_source_underlays || return 1

  (
    cd "$workspace" || exit 1
    command colcon "$@"
  )
}

# =============================================================================
# Build commands
# =============================================================================

_ros2_build_workspace() {
  local workspace="$1"
  shift

  # Build only against installed underlays.
  # Do not source a possibly stale workspace overlay.
  _ros2_source_underlays || return 1

  cd "$workspace" || return 1

  local -a user_arguments
  user_arguments=("$@")

  local -a build_arguments
  build_arguments=(
    --symlink-install
    --event-handlers
    console_cohesion+
  )

  local -a normal_arguments
  local -a cmake_arguments

  local argument
  local reading_cmake_arguments=0

  for argument in "${user_arguments[@]}"; do
    if [[ "$argument" == "--cmake-args" ]]; then
      reading_cmake_arguments=1
      continue
    fi

    if (( reading_cmake_arguments )); then
      # A new colcon option ends the cmake-argument section.
      if [[ "$argument" == --* &&
            "$argument" != -D* &&
            "$argument" != -U* &&
            "$argument" != -W* ]]; then
        reading_cmake_arguments=0
        normal_arguments+=("$argument")
      else
        cmake_arguments+=("$argument")
      fi
    else
      normal_arguments+=("$argument")
    fi
  done

  # Add it only once.
  if (( ! ${cmake_arguments[(Ie)-DCMAKE_EXPORT_COMPILE_COMMANDS=ON]} )); then
    cmake_arguments+=(
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    )
  fi

  build_arguments+=("${normal_arguments[@]}")

  if (( ${#cmake_arguments[@]} > 0 )); then
    build_arguments+=(
      --cmake-args
      "${cmake_arguments[@]}"
    )
  fi

  command colcon build "${build_arguments[@]}"

  local build_status=$?

  if (( build_status != 0 )); then
    _ros2_error "workspace build failed."
    return "$build_status"
  fi

  # Generate one workspace-level database for clangd.
  _ros2_merge_compile_commands "$workspace" || {
    _ros2_warning \
      "build succeeded, but compile_commands.json could not be generated."
  }

  if [[ ! -f "$workspace/install/setup.zsh" ]]; then
    _ros2_error "no workspace setup script was generated:"
    echo "  $workspace/install/setup.zsh"
    return 1
  fi

  _ros2_activate_workspace_environment "$workspace" || return 1

  cd "$workspace" || return 1

  _ros2_info "build completed."

  echo
  echo "Workspace overlay sourced:"
  echo "  $workspace/install/setup.zsh"

  if [[ -f "$workspace/compile_commands.json" ]]; then
    echo
    echo "Compilation database:"
    echo "  $workspace/compile_commands.json"
  fi
}

ros_workspace_build() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1
  _ros2_build_workspace "$workspace" "$@"
}

ros_workspace_rebuild() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  echo "Removing generated directories:"
  echo "  $workspace/build"
  echo "  $workspace/install"
  echo "  $workspace/log"

  rm -rf "$workspace/build" "$workspace/install" "$workspace/log"
  _ros2_build_workspace "$workspace" "$@"
}

ros_workspace_build_sequential() {
  ros_workspace_build --executor sequential "$@"
}

ros_workspace_build_package() {
  local package_name="${1:-}"

  if [[ -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rwbp PACKAGE_NAME [COLCON_ARGUMENTS...]"
    return 1
  fi

  shift
  ros_workspace_build --packages-select "$package_name" "$@"
}

ros_workspace_build_up_to() {
  local package_name="${1:-}"

  if [[ -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rwbup PACKAGE_NAME [COLCON_ARGUMENTS...]"
    return 1
  fi

  shift
  ros_workspace_build --packages-up-to "$package_name" "$@"
}

ros_workspace_build_skip() {
  local package_name="${1:-}"

  if [[ -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rwbskip PACKAGE_NAME [COLCON_ARGUMENTS...]"
    return 1
  fi

  shift
  ros_workspace_build --packages-skip "$package_name" "$@"
}

ros_workspace_build_debug() {
  ros_workspace_build \
    --cmake-args \
      -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    "$@"
}

ros_workspace_build_release() {
  ros_workspace_build \
    --cmake-args \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    "$@"
}

ros_workspace_build_no_tests() {
  ros_workspace_build \
    --cmake-args \
      -DBUILD_TESTING=OFF \
    "$@"
}

ros_workspace_build_mixin() {
  local mixin_name="${1:-}"

  if [[ -z "$mixin_name" ]]; then
    echo "Usage:"
    echo "  rwbm MIXIN_NAME [COLCON_ARGUMENTS...]"
    return 1
  fi

  shift
  ros_workspace_build --mixin "$mixin_name" "$@"
}

ros_workspace_source() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  if [[ ! -f "$workspace/install/setup.zsh" ]]; then
    _ros2_error "workspace has not been built:"
    echo "  $workspace"
    return 1
  fi

  _ros2_activate_workspace_environment "$workspace" || return 1
  cd "$workspace" || return 1

  _ros2_info "workspace overlay sourced:"
  echo "  $workspace/install/setup.zsh"
}

ros_workspace_clean() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  echo "Removing generated directories:"
  echo "  $workspace/build"
  echo "  $workspace/install"
  echo "  $workspace/log"

  rm -rf "$workspace/build" "$workspace/install" "$workspace/log"

  _ros2_source_underlays || return 1
  ROS2_ACTIVE_WS="$workspace"
  export _colcon_cd_root="$workspace"
  cd "$workspace" || return 1

  _ros2_info "workspace cleaned."
}

# =============================================================================
# rosdep
# =============================================================================

ros_workspace_dependencies_install() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  _ros2_require_command rosdep || return 1
  _ros2_source_underlays || return 1

  (
    cd "$workspace" || exit 1

    command rosdep install \
      --from-paths src \
      --ignore-src \
      --rosdistro "${ROS_DISTRO:-$ROS2_DISTRO_NAME}" \
      -r \
      -y \
      "$@"
  )
}

ros_workspace_dependencies_check() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  _ros2_require_command rosdep || return 1
  _ros2_source_underlays || return 1

  (
    cd "$workspace" || exit 1

    command rosdep check \
      --from-paths src \
      --ignore-src \
      --rosdistro "${ROS_DISTRO:-$ROS2_DISTRO_NAME}" \
      "$@"
  )
}

ros_workspace_dependency_keys() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  _ros2_require_command rosdep || return 1
  _ros2_source_underlays || return 1

  (
    cd "$workspace" || exit 1

    command rosdep keys \
      --from-paths src \
      --ignore-src \
      "$@"
  )
}

rosdep_initialize() {
  _ros2_require_command rosdep || return 1

  echo "Initializing rosdep system sources."
  echo "This is normally required only once per machine."
  sudo rosdep init
}

rosdep_update_database() {
  _ros2_require_command rosdep || return 1
  command rosdep update "$@"
}

# =============================================================================
# Package discovery
# =============================================================================

ros_package_list() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  (
    _ros2_source_underlays || exit 1
    command colcon list --base-paths "$workspace/src"
  )
}

ros_package_graph() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  (
    _ros2_source_underlays || exit 1
    cd "$workspace" || exit 1
    command colcon graph "$@"
  )
}

# =============================================================================
# Package creation
# =============================================================================

_ros2_create_package() {
  local build_type="$1"
  local package_name="$2"
  local node_name="$3"

  shift 3

  if [[ -z "$package_name" ]]; then
    _ros2_error "package name is required."
    return 1
  fi

  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  local -a create_command
  create_command=(
    ros2 pkg create
    --build-type "$build_type"
    --license Apache-2.0
  )

  if [[ -n "$node_name" ]]; then
    create_command+=(--node-name "$node_name")
  fi

  # Place the positional package name before --dependencies because
  # --dependencies accepts a variable number of values.
  create_command+=("$package_name")

  if (( $# > 0 )); then
    create_command+=(--dependencies "$@")
  fi

  echo "Creating package:"
  echo "  Workspace:  $workspace"
  echo "  Package:    $package_name"
  echo "  Build type: $build_type"

  if [[ -n "$node_name" ]]; then
    echo "  Node:       $node_name"
  fi

  if (( $# > 0 )); then
    echo "  Dependencies:"
    printf "    %s\n" "$@"
  fi

  (
    _ros2_source_underlays || exit 1
    cd "$workspace/src" || exit 1
    "${create_command[@]}"
  )
}

_ros2_configure_interface_package() {
  local workspace="$1"
  local package_name="$2"
  shift 2

  local package_directory="$workspace/src/$package_name"
  local cmake_file="$package_directory/CMakeLists.txt"
  local package_xml="$package_directory/package.xml"

  if [[ ! -d "$package_directory" ]]; then
    _ros2_error "interface package directory was not created:"
    echo "  $package_directory"
    return 1
  fi

  mkdir -p \
    "$package_directory/msg" \
    "$package_directory/srv" \
    "$package_directory/action" ||
    return 1

  {
    cat <<EOF
cmake_minimum_required(VERSION 3.20)
project(${package_name})

find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
EOF

    local dependency
    for dependency in "$@"; do
      printf 'find_package(%s REQUIRED)\n' "$dependency"
    done

    cat <<'EOF'

# Automatically discover this package's own interface-definition files.
#
# These globs do not find ROS packages. They only collect local files such as:
#
#   msg/Num.msg
#   srv/AddThreeInts.srv
#   action/FlyTo.action
#
# CONFIGURE_DEPENDS asks CMake to reconfigure when matching files are added
# or removed.
file(GLOB message_files
  RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
  CONFIGURE_DEPENDS
  "msg/*.msg"
)

file(GLOB service_files
  RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
  CONFIGURE_DEPENDS
  "srv/*.srv"
)

file(GLOB action_files
  RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
  CONFIGURE_DEPENDS
  "action/*.action"
)

set(interface_files
  ${message_files}
  ${service_files}
  ${action_files}
)

# A newly-created package contains empty msg/, srv/, and action/ directories.
# Build successfully until at least one definition file has been added.
if(interface_files)
  rosidl_generate_interfaces(
    ${PROJECT_NAME}
    ${interface_files}
EOF

    if (( $# > 0 )); then
      echo "    DEPENDENCIES"

      for dependency in "$@"; do
        printf '      %s\n' "$dependency"
      done
    fi

    cat <<'EOF'
  )
endif()

ament_export_dependencies(rosidl_default_runtime)

ament_package()
EOF
  } >"$cmake_file" || return 1

  python3 - "$package_xml" "$@" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

path = Path(sys.argv[1])
external_dependencies = sys.argv[2:]

tree = ET.parse(path)
root = tree.getroot()


def has_entry(tag: str, value: str) -> bool:
    return any(
        element.tag == tag and (element.text or "").strip() == value
        for element in root
    )


def insert_before_export(tag: str, value: str) -> None:
    if has_entry(tag, value):
        return

    element = ET.Element(tag)
    element.text = value

    children = list(root)
    export_index = next(
        (index for index, child in enumerate(children) if child.tag == "export"),
        len(children),
    )
    root.insert(export_index, element)


insert_before_export("buildtool_depend", "rosidl_default_generators")
insert_before_export("exec_depend", "rosidl_default_runtime")
insert_before_export("member_of_group", "rosidl_interface_packages")

for dependency in external_dependencies:
    insert_before_export("depend", dependency)

ET.indent(tree, space="  ")
tree.write(path, encoding="utf-8", xml_declaration=True)
PY

  _ros2_info "interface package configured:"
  echo "  $package_directory"
  echo
  echo "Interface directories:"
  echo "  msg/"
  echo "  srv/"
  echo "  action/"

  if (( $# > 0 )); then
    echo
    echo "External interface dependencies:"
    printf "  %s\n" "$@"
  fi

  echo
  echo "Add definition files, then build with:"
  echo "  rwbp $package_name"
}

_ros2_create_interface_package() {
  local package_name="$1"
  shift

  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  _ros2_create_package \
    ament_cmake \
    "$package_name" \
    "" \
    "$@" ||
    return 1

  _ros2_configure_interface_package \
    "$workspace" \
    "$package_name" \
    "$@"
}

ros_package_cpp() {
  local interface_mode=0

  case "${1:-}" in
    -i|--interface)
      interface_mode=1
      shift
      ;;
  esac

  local package_name="${1:-}"

  if [[ -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rpcpp PACKAGE_NAME [DEPENDENCY...]"
    echo "  rpcpp -i PACKAGE_NAME [INTERFACE_DEPENDENCY...]"
    echo "  rpcpp --interface PACKAGE_NAME [INTERFACE_DEPENDENCY...]"
    return 1
  fi

  shift

  if (( interface_mode )); then
    _ros2_create_interface_package "$package_name" "$@"
  else
    _ros2_create_package ament_cmake "$package_name" "" "$@"
  fi
}

ros_package_python() {
  local package_name="${1:-}"

  if [[ -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rppy PACKAGE_NAME [DEPENDENCY...]"
    return 1
  fi

  shift
  _ros2_create_package ament_python "$package_name" "" "$@"
}

ros_package_cmake() {
  local package_name="${1:-}"

  if [[ -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rpcmake PACKAGE_NAME [DEPENDENCY...]"
    return 1
  fi

  shift
  _ros2_create_package cmake "$package_name" "" "$@"
}

# Argument order mirrors the native command's conceptual order:
# --node-name NODE_NAME PACKAGE_NAME
ros_package_cpp_node() {
  local node_name="${1:-}"
  local package_name="${2:-}"

  if [[ -z "$node_name" || -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rpcppn NODE_NAME PACKAGE_NAME [DEPENDENCY...]"
    return 1
  fi

  shift 2
  _ros2_create_package ament_cmake "$package_name" "$node_name" "$@"
}

ros_package_python_node() {
  local node_name="${1:-}"
  local package_name="${2:-}"

  if [[ -z "$node_name" || -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rpyn NODE_NAME PACKAGE_NAME [DEPENDENCY...]"
    return 1
  fi

  shift 2
  _ros2_create_package ament_python "$package_name" "$node_name" "$@"
}

# =============================================================================
# Testing
# =============================================================================

ros_workspace_test() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  _ros2_activate_workspace_environment "$workspace" || return 1
  cd "$workspace" || return 1

  command colcon test \
    --event-handlers console_cohesion+ \
    "$@"
}

ros_workspace_test_package() {
  local package_name="${1:-}"

  if [[ -z "$package_name" ]]; then
    echo "Usage:"
    echo "  rwtp PACKAGE_NAME [COLCON_ARGUMENTS...]"
    return 1
  fi

  shift
  ros_workspace_test --packages-select "$package_name" "$@"
}

ros_workspace_test_single() {
  local package_name="${1:-}"
  local test_regex="${2:-}"

  if [[ -z "$package_name" || -z "$test_regex" ]]; then
    echo "Usage:"
    echo "  rwts PACKAGE_NAME TEST_REGEX"
    return 1
  fi

  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  _ros2_activate_workspace_environment "$workspace" || return 1
  cd "$workspace" || return 1

  command colcon test \
    --packages-select "$package_name" \
    --ctest-args -R "$test_regex" \
    --event-handlers console_direct+
}

ros_workspace_test_result() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  cd "$workspace" || return 1
  command colcon test-result --verbose
}

# =============================================================================
# Running ROS commands
# =============================================================================

ros_run() {
  if [[ -z "${1:-}" || -z "${2:-}" ]]; then
    echo "Usage:"
    echo "  rrun PACKAGE EXECUTABLE [ROS_ARGUMENTS...]"
    return 1
  fi

  _ros2_activate_current_environment || return 1
  command ros2 run "$@"
}

ros_launch() {
  if [[ -z "${1:-}" || -z "${2:-}" ]]; then
    echo "Usage:"
    echo "  rlaunch PACKAGE LAUNCH_FILE [LAUNCH_ARGUMENTS...]"
    return 1
  fi

  _ros2_activate_current_environment || return 1
  command ros2 launch "$@"
}

# =============================================================================
# COLCON_IGNORE
# =============================================================================

_ros2_find_package_directory() {
  local workspace="$1"
  local package_or_path="$2"

  if [[ -d "$package_or_path" ]]; then
    _ros2_normalize_path "$package_or_path"
    return 0
  fi

  local package_path

  package_path="$(
    (
      _ros2_source_underlays || exit 1
      command colcon list --base-paths "$workspace/src" 2>/dev/null
    ) |
      awk -v package="$package_or_path" \
        '$1 == package { print $2; exit }'
  )"

  if [[ -n "$package_path" ]]; then
    _ros2_normalize_path "$package_path"
    return 0
  fi

  return 1
}

ros_package_ignore() {
  local package_or_path="${1:-}"

  if [[ -z "$package_or_path" ]]; then
    echo "Usage:"
    echo "  rignore PACKAGE_NAME"
    echo "  rignore PACKAGE_DIRECTORY"
    return 1
  fi

  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  local package_directory
  package_directory="$(
    _ros2_find_package_directory "$workspace" "$package_or_path"
  )" || {
    _ros2_error "package or directory was not found:"
    echo "  $package_or_path"
    return 1
  }

  touch "$package_directory/COLCON_IGNORE"

  _ros2_info "colcon will ignore:"
  echo "  $package_directory"
}

ros_package_unignore() {
  local package_directory="${1:-}"

  if [[ -z "$package_directory" ]]; then
    echo "Usage:"
    echo "  runignore PACKAGE_DIRECTORY"
    return 1
  fi

  package_directory="$(_ros2_normalize_path "$package_directory")"

  if [[ ! -d "$package_directory" ]]; then
    _ros2_error "directory was not found:"
    echo "  $package_directory"
    return 1
  fi

  rm -f "$package_directory/COLCON_IGNORE"

  _ros2_info "COLCON_IGNORE removed from:"
  echo "  $package_directory"
}

ros_package_ignored_list() {
  local workspace
  workspace="$(_ros2_active_workspace)" || return 1

  find "$workspace/src" -name COLCON_IGNORE -print
}

# =============================================================================
# Colcon mixins
# =============================================================================

ros_mixin_install() {
  _ros2_require_command colcon || return 1

  if command colcon mixin list 2>/dev/null | grep -q '^default'; then
    _ros2_info "default mixin repository already exists."
    command colcon mixin update default
    return
  fi

  command colcon mixin add default \
    https://raw.githubusercontent.com/colcon/colcon-mixin-repository/master/index.yaml \
    || return 1

  command colcon mixin update default
}

ros_mixin_update() {
  command colcon mixin update default
}

ros_mixin_list() {
  command colcon mixin list
}

# =============================================================================
# Diagnostics
# =============================================================================

ros_environment() {
  echo
  echo "ROS distribution:"
  echo "  ${ROS_DISTRO:-not active}"

  echo
  echo "Active workspace:"
  echo "  ${ROS2_ACTIVE_WS:-none}"

  echo
  echo "Managed workspace root:"
  echo "  $ROS2_WORKSPACES_ROOT"

  echo
  echo "Workspace marker:"
  echo "  $ROS2_WORKSPACE_MARKER"

  echo
  echo "Python:"
  echo "  $(command -v python3 2>/dev/null || echo not-found)"
  echo "  $(python3 --version 2>&1)"

  echo
  echo "ROS executable:"
  echo "  $(command -v ros2 2>/dev/null || echo not-found)"

  echo
  echo "colcon executable:"
  echo "  $(command -v colcon 2>/dev/null || echo not-found)"

  echo
  echo "rosdep executable:"
  echo "  $(command -v rosdep 2>/dev/null || echo not-found)"

  echo
  echo "Configured underlays:"

  local setup_file
  for setup_file in "${ROS2_UNDERLAY_SETUPS[@]}"; do
    echo "  $setup_file"
  done

  echo
  echo "Environment variables:"

  env |
    grep -E \
      '^(ROS|AMENT|COLCON|CMAKE_PREFIX|PYTHON|CONDA|LD_LIBRARY_PATH|PKG_CONFIG_PATH)=' |
    sort
}

ros_check() {
  echo "ROS 2 development environment check"
  echo

  local command_name

  for command_name in python3 ros2 colcon rosdep cmake; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf "  %-12s %s\n" "$command_name" "$(command -v "$command_name")"
    else
      printf "  %-12s %s\n" "$command_name" "MISSING"
    fi
  done

  echo
  echo "Underlays:"

  local setup_file
  for setup_file in "${ROS2_UNDERLAY_SETUPS[@]}"; do
    if [[ -r "$setup_file" ]]; then
      echo "  [available] $setup_file"
    else
      echo "  [missing]   $setup_file"
    fi
  done
}

# =============================================================================
# colcon_cd and completion
# =============================================================================

for colcon_cd_script in \
  /usr/share/colcon_cd/function/colcon_cd.sh \
  "$HOME/.local/share/colcon_cd/function/colcon_cd.sh" \
  /usr/local/share/colcon_cd/function/colcon_cd.sh
do
  if [[ -r "$colcon_cd_script" ]]; then
    source "$colcon_cd_script"
    break
  fi
done

for colcon_completion_script in \
  /usr/share/colcon_argcomplete/hook/colcon-argcomplete.zsh \
  "$HOME/.local/share/colcon_argcomplete/hook/colcon-argcomplete.zsh" \
  /usr/local/share/colcon_argcomplete/hook/colcon-argcomplete.zsh
do
  if [[ -r "$colcon_completion_script" ]]; then
    source "$colcon_completion_script"
    break
  fi
done

_ros2_workspace_completion() {
  local -a workspace_names
  local workspace

  for workspace in "$ROS2_WORKSPACES_ROOT"/*(/N); do
    if _ros2_is_registered_workspace "$workspace"; then
      workspace_names+=("${workspace:t}")
    fi
  done

  _describe "registered ROS 2 workspace" workspace_names
}

if (( $+functions[compdef] )); then
  compdef \
    _ros2_workspace_completion \
    ros_workspace_use \
    ros_workspace_info \
    ros_workspace_src \
    ros_workspace_root \
    ros_workspace_tree \
    ros_workspace_unregister \
    rw \
    rwi \
    rwsrc \
    rwroot \
    rwtree \
    rwunreg
fi

# =============================================================================
# Help
# =============================================================================

ros_help() {
  local topic="${1:-all}"

  if [[ "$topic" == "-h" || "$topic" == "--help" ]]; then
    topic="all"
  fi

  case "$topic" in
    all)
      cat <<'EOF'
Generic ROS 2 workspace plugin

Help

  rh
      Show all commands.

  rh TOPIC
      Show detailed help for a topic.

  Topics:
      environment workspace dependencies build package test
      run ignore mixin navigation


Environment

  ru
      Activate only the configured ROS underlays.

  rul
      List configured underlays.

  renv
      Display the active ROS environment.

  rcheck
      Check ROS, colcon, rosdep, Python, CMake, and underlays.


Workspace management

  rwc NAME_OR_PATH
      Create, register, and activate a workspace.

  rw NAME_OR_PATH
      Activate an existing workspace.

  rwl
      List registered workspaces.

  rwreg NAME_OR_PATH
      Register an existing workspace in rwl.

  rwunreg NAME_OR_PATH
      Remove a workspace from rwl without deleting it.

  rwi [NAME_OR_PATH]
      Show workspace information and packages.

  rwsrc [NAME_OR_PATH]
      Enter the workspace src directory.

  rwroot [NAME_OR_PATH]
      Enter the workspace root.

  rwtree [NAME_OR_PATH]
      Display the workspace directory tree.


Workspace dependency management

  rwdep [ROSDEP_ARGUMENTS...]
      Install missing dependencies declared by packages in the active workspace.

  rwdepcheck [ROSDEP_ARGUMENTS...]
      Check whether active-workspace dependencies are satisfied.

  rwdepkeys [ROSDEP_ARGUMENTS...]
      List rosdep keys used by packages in the active workspace.

  rdepinit
      Initialize rosdep system sources. Usually run once per machine.

  rdepupdate
      Update the local rosdep database. This is not workspace-specific.


Build

  rwb [COLCON_ARGUMENTS...]
      Build the active workspace and source its overlay.

  rwbr [COLCON_ARGUMENTS...]
      Clean and rebuild the active workspace.

  rwbs [COLCON_ARGUMENTS...]
      Build sequentially.

  rwbp PACKAGE [COLCON_ARGUMENTS...]
      Build one package.

  rwbup PACKAGE [COLCON_ARGUMENTS...]
      Build a package and its workspace dependencies.

  rwbskip PACKAGE [COLCON_ARGUMENTS...]
      Skip a package.

  rwbd
      Build in Debug mode.

  rwbrelease
      Build in Release mode.

  rwbnt
      Build without configuring tests.

  rwbm MIXIN
      Build using a colcon mixin.

  rwclean
      Remove build, install, and log.

  rws
      Source the existing workspace overlay.

  rc COLCON_ARGUMENTS...
      Run any colcon command from the active workspace.

  rwcc
      Merge package compilation databases into:
      ACTIVE_WORKSPACE/compile_commands.json

      This is normally done automatically after every successful build.

Package creation and discovery

  rpcpp PACKAGE [DEPENDENCY...]
      Create a normal ament_cmake package.

  rpcpp -i PACKAGE [INTERFACE_DEPENDENCY...]
  rpcpp --interface PACKAGE [INTERFACE_DEPENDENCY...]
      Create an interface-only ament_cmake package scaffold with:
        msg/
        srv/
        action/
        rosidl_default_generators
        rosidl_default_runtime
        rosidl_interface_packages group membership

      Additional arguments are packages referenced by fields inside the
      interface definitions, for example geometry_msgs or sensor_msgs.

  rppy PACKAGE [DEPENDENCY...]
      Create an ament_python package.

  rpcmake PACKAGE [DEPENDENCY...]
      Create a pure CMake package.

  rpcppn NODE PACKAGE [DEPENDENCY...]
      Create an ament_cmake package with an initial node.

  rpyn NODE PACKAGE [DEPENDENCY...]
      Create an ament_python package with an initial node.

  rpkgs
      List packages in the active workspace.

  rpgraph
      Display the package dependency graph.


Testing

  rwt
      Run all tests.

  rwtp PACKAGE
      Run tests for one package.

  rwts PACKAGE TEST_REGEX
      Run one matching CTest test.

  rwtr
      Show detailed test results.


ROS execution

  r2 ROS2_ARGUMENTS...
      Run any ros2 command using the current ROS environment.

  rrun PACKAGE EXECUTABLE [ARGUMENTS...]
      Run a ROS executable.

  rlaunch PACKAGE LAUNCH_FILE [ARGUMENTS...]
      Run a ROS launch file.


COLCON_IGNORE

  rignore PACKAGE_OR_PATH
      Create COLCON_IGNORE.

  runignore PACKAGE_PATH
      Remove COLCON_IGNORE.

  rignored
      List ignored package directories.


Mixins

  rmi
      Install the default colcon mixin repository.

  rmu
      Update default mixins.

  rml
      List available mixins.


Navigation

  colcon_cd PACKAGE
      Enter a package directory in the active workspace.
EOF
      ;;

    environment)
      cat <<'EOF'
Environment model

ru
  Resets old ROS / Conda state and sources only the configured underlays.

rw WORKSPACE
  Sources the underlays and then sources WORKSPACE/install/setup.zsh
  when the workspace has already been built.

r2, rrun, and rlaunch
  Work in both modes:
    - underlay only
    - underlay plus the active workspace overlay

The plugin itself is lazy-loaded by rosload. Loading the plugin does not
automatically activate ROS.
EOF
      ;;

    workspace)
      cat <<'EOF'
Workspace management

The root directory is:

  $ROS2_WORKSPACES_ROOT

Only directories containing both:

  src/
  .ros2-workspace

appear in rwl.

Create a managed workspace:

  rwc precision_land_ws

Register an existing workspace:

  rwreg ~/workspace/px4_ros_wc

Remove it from the list without deleting files:

  rwunreg ~/workspace/px4_ros_wc

A full path can always be activated even if it is not registered:

  rw ~/somewhere/custom_ws
EOF
      ;;

    dependencies)
      cat <<'EOF'
rosdep commands

rwdep
  Workspace-oriented. From the active workspace root, it runs:

    rosdep install \
      --from-paths src \
      --ignore-src \
      --rosdistro $ROS2_DISTRO_NAME \
      -r \
      -y

  Additional rosdep arguments are forwarded:

    rwdep --skip-keys "some_dependency"


rwdepcheck
  Checks whether dependencies declared by packages under src/ are satisfied.

    rwdepcheck


rwdepkeys
  Lists the rosdep keys declared by packages in the active workspace.

    rwdepkeys


rdepinit
  Machine-level operation. Initializes rosdep sources and normally requires
  sudo. Usually needed only once:

    rdepinit


rdepupdate
  User-level database refresh. It is not tied to a workspace:

    rdepupdate

The rw prefix is used for install/check/keys because those commands inspect
the currently active workspace. init/update are global, so they use rdep.
EOF
      ;;

    build)
      cat <<'EOF'
Build commands

rwb [COLCON_ARGUMENTS...]
  Runs colcon build --symlink-install for the active workspace.
  After success, install/setup.zsh is sourced automatically.

rwbr
  Removes build/, install/, and log/, then rebuilds.

rwbs
  Adds --executor sequential.

rwbp PACKAGE
  Adds --packages-select PACKAGE.

rwbup PACKAGE
  Adds --packages-up-to PACKAGE.

rwbskip PACKAGE
  Adds --packages-skip PACKAGE.

rwbd
  Adds:
    -DCMAKE_BUILD_TYPE=Debug
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

rwbrelease
  Adds:
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

rwbnt
  Adds:
    -DBUILD_TESTING=OFF

rwbm MIXIN
  Adds --mixin MIXIN.

rwclean
  Removes generated directories without rebuilding.

rws
  Sources the existing workspace overlay without rebuilding.

Examples:

  rwb
  rwbp offboard
  rwbup offboard
  rwbp turtlesim --allow-overriding turtlesim
EOF
      ;;

    package)
      cat <<'EOF'
Package commands

Create a C++ package:

  rpcpp offboard rclcpp px4_msgs geometry_msgs eigen3_cmake_module

Create an interface package containing only primitive fields:

  rpcpp -i tutorial_interfaces

Create an interface package whose definitions may reference geometry_msgs:

  rpcpp -i tutorial_interfaces geometry_msgs

The -i/--interface scaffold creates msg/, srv/, and action/ directories and
configures rosidl generation. It creates no executable target.

Create a C++ package with an initial node:

  rpcppn offboard_node offboard \
    rclcpp px4_msgs geometry_msgs eigen3_cmake_module

Create a Python package:

  rppy monitor rclpy px4_msgs

Create a Python package with an initial node:

  rpyn monitor_node monitor rclpy px4_msgs

The node helpers use this order:

  NODE_NAME PACKAGE_NAME

All packages are created under:

  ACTIVE_WORKSPACE/src
EOF
      ;;

    test)
      cat <<'EOF'
Testing

Run all tests:

  rwt

Run tests for one package:

  rwtp offboard

Run one matching CTest test:

  rwts offboard test_name

Show detailed results:

  rwtr
EOF
      ;;

    run)
      cat <<'EOF'
ROS execution

Run any ros2 command:

  r2 topic list
  r2 node list
  r2 pkg executables offboard
  r2 run turtlesim turtlesim_node

Run a package executable directly:

  rrun turtlesim turtlesim_node
  rrun offboard offboard

Launch a launch file:

  rlaunch offboard offboard.launch.py

r2 includes the ros2 subcommand. rrun does not:

  r2 run PACKAGE EXECUTABLE
  rrun PACKAGE EXECUTABLE
EOF
      ;;

    ignore)
      cat <<'EOF'
COLCON_IGNORE

Ignore a package by name or path:

  rignore experimental_package

List ignored directories:

  rignored

An ignored package is no longer discoverable by package name, so remove
COLCON_IGNORE using its directory path:

  runignore ~/workspace/my_ws/src/experimental_package
EOF
      ;;

    mixin)
      cat <<'EOF'
Colcon mixins

Install the official default mixin repository:

  rmi

Update it:

  rmu

List available mixins:

  rml

Build with a mixin:

  rwbm debug
EOF
      ;;

    navigation)
      cat <<'EOF'
Navigation

Enter the active workspace root:

  rwroot

Enter its src directory:

  rwsrc

Display its tree:

  rwtree

Jump to a package directory:

  colcon_cd PACKAGE_NAME

The plugin updates _colcon_cd_root whenever a workspace is activated.
EOF
      ;;

    *)
      _ros2_error "unknown help topic: $topic"
      echo
      echo "Available topics:"
      echo "  environment workspace dependencies build package"
      echo "  test run ignore mixin navigation"
      return 1
      ;;
  esac
}
# =============================================================================
# Compilation database
# =============================================================================

_ros2_merge_compile_commands() {
  local workspace="$1"

  if [[ -z "$workspace" || ! -d "$workspace" ]]; then
    _ros2_error "invalid workspace for compilation database."
    return 1
  fi

  local output_file="$workspace/compile_commands.json"

  python3 - "$workspace" "$output_file" <<'PY'
import json
import os
import sys
from pathlib import Path

workspace = Path(sys.argv[1]).resolve()
output_file = Path(sys.argv[2]).resolve()
build_directory = workspace / "build"

if not build_directory.is_dir():
    print(
        f"ROS 2 warning: build directory does not exist: "
        f"{build_directory}",
        file=sys.stderr,
    )
    sys.exit(0)

databases = sorted(
    build_directory.glob("*/compile_commands.json")
)

merged_entries = []
seen_files = set()

for database in databases:
    try:
        entries = json.loads(database.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(
            f"ROS 2 warning: skipped invalid database "
            f"{database}: {error}",
            file=sys.stderr,
        )
        continue

    if not isinstance(entries, list):
        print(
            f"ROS 2 warning: skipped non-list database: "
            f"{database}",
            file=sys.stderr,
        )
        continue

    for entry in entries:
        if not isinstance(entry, dict):
            continue

        source_file = entry.get("file")

        if not source_file:
            continue

        directory = Path(
            entry.get("directory", workspace)
        )

        source_path = Path(source_file)

        if not source_path.is_absolute():
            source_path = directory / source_path

        source_path = source_path.resolve()
        source_key = os.fspath(source_path)

        # Keep only the latest entry for a source file.
        if source_key in seen_files:
            continue

        seen_files.add(source_key)

        normalized_entry = dict(entry)
        normalized_entry["file"] = source_key
        normalized_entry["directory"] = os.fspath(
            directory.resolve()
        )

        merged_entries.append(normalized_entry)

if not merged_entries:
    print(
        "ROS 2 warning: no compile_commands.json files "
        "were found under build/*/.",
        file=sys.stderr,
    )

    try:
        output_file.unlink()
    except FileNotFoundError:
        pass

    sys.exit(0)

temporary_file = output_file.with_suffix(
    ".json.tmp"
)

temporary_file.write_text(
    json.dumps(
        merged_entries,
        indent=2,
    )
    + "\n"
)

temporary_file.replace(output_file)

print(
    f"Created {output_file} with "
    f"{len(merged_entries)} entries from "
    f"{len(databases)} package databases."
)
PY

  local merge_status=$?

  if (( merge_status != 0 )); then
    _ros2_error "failed to create workspace compilation database."
    return "$merge_status"
  fi

  if [[ -f "$output_file" ]]; then
    _ros2_info "clangd compilation database updated:"
    echo "  $output_file"
  fi
}

# =============================================================================
# Aliases
# =============================================================================

# Underlays and diagnostics.
alias ru='ros_underlay_activate'
alias rul='ros_underlay_list'
alias renv='ros_environment'
alias rcheck='ros_check'

# Workspace management.
alias rwc='ros_workspace_create'
alias rw='ros_workspace_use'
alias rwl='ros_workspace_list'
alias rwreg='ros_workspace_register'
alias rwunreg='ros_workspace_unregister'
alias rwi='ros_workspace_info'
alias rwsrc='ros_workspace_src'
alias rwroot='ros_workspace_root'
alias rwtree='ros_workspace_tree'

# rosdep.
alias rwdep='ros_workspace_dependencies_install'
alias rwdepcheck='ros_workspace_dependencies_check'
alias rwdepkeys='ros_workspace_dependency_keys'
alias rdepinit='rosdep_initialize'
alias rdepupdate='rosdep_update_database'

# Generic ROS and colcon.
alias r2='ros_cli'
alias rc='ros_colcon'

# Build.
alias rwb='ros_workspace_build'
alias rwbr='ros_workspace_rebuild'
alias rwbs='ros_workspace_build_sequential'
alias rwbp='ros_workspace_build_package'
alias rwbup='ros_workspace_build_up_to'
alias rwbskip='ros_workspace_build_skip'
alias rwbd='ros_workspace_build_debug'
alias rwbrelease='ros_workspace_build_release'
alias rwbnt='ros_workspace_build_no_tests'
alias rwbm='ros_workspace_build_mixin'
alias rwclean='ros_workspace_clean'
alias rws='ros_workspace_source'

# Package creation and discovery.
alias rpcpp='ros_package_cpp'
alias rppy='ros_package_python'
alias rpcmake='ros_package_cmake'
alias rpcppn='ros_package_cpp_node'
alias rpyn='ros_package_python_node'
alias rpkgs='ros_package_list'
alias rpgraph='ros_package_graph'

# Testing.
alias rwt='ros_workspace_test'
alias rwtp='ros_workspace_test_package'
alias rwts='ros_workspace_test_single'
alias rwtr='ros_workspace_test_result'

# Running and launching.
alias rrun='ros_run'
alias rlaunch='ros_launch'

# COLCON_IGNORE.
alias rignore='ros_package_ignore'
alias runignore='ros_package_unignore'
alias rignored='ros_package_ignored_list'

# Mixins.
alias rmi='ros_mixin_install'
alias rmu='ros_mixin_update'
alias rml='ros_mixin_list'

# Compile Merge
alias rwcc='ros_workspace_compile_commands'

# Help.
alias rh='ros_help'
