#!/usr/bin/with-contenv bashio

# Enable strict error handling
set -e
set -o pipefail

# Initialize environment for Claude Code CLI using /data (HA best practice)
init_environment() {
    # Use /data exclusively - guaranteed writable by HA Supervisor
    local data_home="/data/home"
    local config_dir="/data/.config"
    local cache_dir="/data/.cache"
    local state_dir="/data/.local/state"
    local claude_config_dir="/data/.config/claude"
    local gh_config_dir="/data/.config/gh"
    local persist_root="/data/packages"
    local persist_bin="$persist_root/bin"
    local persist_lib="$persist_root/lib"
    local persist_python="$persist_root/python"

    bashio::log.info "Initializing Claude Code environment in /data..."

    # Create all required directories
    if ! mkdir -p "$data_home" "$config_dir/claude" "$config_dir/gh" "$cache_dir" "$state_dir" "/data/.local" \
                  "$persist_bin" "$persist_lib" "$persist_python"; then
        bashio::log.error "Failed to create directories in /data"
        exit 1
    fi

    # Set permissions
    chmod 755 "$data_home" "$config_dir" "$cache_dir" "$state_dir" "$claude_config_dir" "$gh_config_dir" \
              "$persist_root" "$persist_bin" "$persist_lib" "$persist_python"

    # Ensure Claude native binary is available at $HOME/.local/bin/claude.
    # The native installer places it at /root/.local/bin/claude during Docker build,
    # but at runtime HOME=/data/home, so Claude's self-check looks in /data/home/.local/bin/.
    #
    # ALWAYS re-point this launcher at the image's baked binary. If someone runs
    # `claude update`, the native updater drops a new build into XDG_DATA_HOME
    # (/data/.local/share, persistent) and repoints this launcher at it — which
    # both drifts from the add-on's pinned version and, on an old base, bricked
    # launch with `statx: symbol not found`. Forcing the link each boot makes the
    # baked version authoritative: any such drift is reset on the next restart.
    local native_bin_dir="$data_home/.local/bin"
    mkdir -p "$native_bin_dir"
    if [ -f /root/.local/bin/claude ]; then
        ln -sfn /root/.local/bin/claude "$native_bin_dir/claude"
        bashio::log.info "  - Claude native binary linked (baked image version): $native_bin_dir/claude"
    fi

    # Set XDG and application environment variables
    export HOME="$data_home"
    export XDG_CONFIG_HOME="$config_dir"
    export XDG_CACHE_HOME="$cache_dir"
    export XDG_STATE_HOME="$state_dir"
    export XDG_DATA_HOME="/data/.local/share"

    # Claude-specific environment variables
    export ANTHROPIC_CONFIG_DIR="$claude_config_dir"
    export ANTHROPIC_HOME="/data"

    # Disable auto-updates: binary is baked into the container image,
    # updates are delivered via add-on releases, not CLI self-update
    export DISABLE_AUTOUPDATER=1

    # GitHub CLI persistent configuration
    export GH_CONFIG_DIR="$gh_config_dir"

    # Get dangerously-skip-permissions configuration
    local dangerously_skip_permissions
    dangerously_skip_permissions=$(bashio::config 'dangerously_skip_permissions' 'false')
    export CLAUDE_DANGEROUS_MODE="$dangerously_skip_permissions"

    # Set IS_SANDBOX=1 to allow --dangerously-skip-permissions when running as root
    if [ "$dangerously_skip_permissions" = "true" ]; then
        export IS_SANDBOX=1
    fi

    # Setup persistent package paths (HIGHEST PRIORITY)
    export PATH="$persist_bin:$persist_python/venv/bin:$data_home/.local/bin:$PATH"
    export LD_LIBRARY_PATH="$persist_lib:${LD_LIBRARY_PATH:-}"
    export PKG_CONFIG_PATH="$persist_lib/pkgconfig:${PKG_CONFIG_PATH:-}"

    # Python virtual environment if it exists
    if [ -d "$persist_python/venv" ]; then
        export VIRTUAL_ENV="$persist_python/venv"
        bashio::log.info "  - Python venv: active"
    fi

    # Create profile script for persistent environment variables
    # This ensures ALL bash sessions (including ttyd shells) have correct PATH
    cat > /etc/profile.d/persistent-packages.sh << 'PROFILE_EOF'
# Persistent package environment - auto-loaded for all bash sessions
export HOME="/data/home"
export XDG_CONFIG_HOME="/data/.config"
export XDG_CACHE_HOME="/data/.cache"
export XDG_STATE_HOME="/data/.local/state"
export XDG_DATA_HOME="/data/.local/share"
export ANTHROPIC_CONFIG_DIR="/data/.config/claude"
export ANTHROPIC_HOME="/data"

# Disable auto-updates inside container (updates via add-on releases)
export DISABLE_AUTOUPDATER=1

# GitHub CLI persistent configuration
export GH_CONFIG_DIR="/data/.config/gh"

# Persistent package paths and native Claude binary (HIGHEST PRIORITY)
export PATH="/data/packages/bin:/data/packages/python/venv/bin:/data/home/.local/bin:$PATH"
export LD_LIBRARY_PATH="/data/packages/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="/data/packages/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Python virtual environment if it exists
if [ -d "/data/packages/python/venv" ]; then
    export VIRTUAL_ENV="/data/packages/python/venv"
fi
PROFILE_EOF

    chmod 644 /etc/profile.d/persistent-packages.sh
    bashio::log.info "  - Profile script created: /etc/profile.d/persistent-packages.sh"

    # Migrate any existing authentication files from legacy locations
    migrate_legacy_auth_files "$claude_config_dir"

    # Setup Claude Code skills and commands
    if [ -d "/opt/.claude" ]; then
        if [ ! -d "$data_home/.claude" ]; then
            cp -r /opt/.claude "$data_home/.claude"
            bashio::log.info "  - Claude Code skills & commands installed"
        else
            bashio::log.info "  - Claude Code skills & commands: already configured"
        fi
    fi

    # Link the harness memory dir to git-tracked /config/.claude/memory.
    # HOME=/data/home is per-add-on, so a fresh /data has no memory symlink and
    # Claude Code silently recalls into a new empty dir. The memories themselves
    # live in /config (mounted, git-tracked) and survive; only the symlink needs
    # recreating. Project dir for cwd /config is sanitised to "-config".
    if [ -d "/config/.claude/memory" ]; then
        local mem_project_dir="$data_home/.claude/projects/-config"
        mkdir -p "$mem_project_dir"
        ln -sfn /config/.claude/memory "$mem_project_dir/memory"
        bashio::log.info "  - Harness memory linked: $mem_project_dir/memory -> /config/.claude/memory"
    fi

    bashio::log.info "Environment initialized:"
    bashio::log.info "  - Home: $HOME"
    bashio::log.info "  - Config: $XDG_CONFIG_HOME"
    bashio::log.info "  - Claude config: $ANTHROPIC_CONFIG_DIR"
    bashio::log.info "  - GitHub config: $GH_CONFIG_DIR"
    bashio::log.info "  - Cache: $XDG_CACHE_HOME"
    bashio::log.info "  - Persistent packages: $persist_root"
}

# One-time migration of existing authentication files
migrate_legacy_auth_files() {
    local target_dir="$1"
    local migrated=false

    bashio::log.info "Checking for existing authentication files to migrate..."

    # Check common legacy locations
    local legacy_locations=(
        "/root/.config/anthropic"
        "/root/.anthropic" 
        "/config/claude-config"
        "/tmp/claude-config"
    )

    for legacy_path in "${legacy_locations[@]}"; do
        if [ -d "$legacy_path" ] && [ "$(ls -A "$legacy_path" 2>/dev/null)" ]; then
            bashio::log.info "Migrating auth files from: $legacy_path"
            
            # Copy files to new location
            if cp -r "$legacy_path"/* "$target_dir/" 2>/dev/null; then
                # Set proper permissions
                find "$target_dir" -type f -exec chmod 600 {} \;
                
                # Create compatibility symlink if this is a standard location
                if [[ "$legacy_path" == "/root/.config/anthropic" ]] || [[ "$legacy_path" == "/root/.anthropic" ]]; then
                    rm -rf "$legacy_path"
                    ln -sf "$target_dir" "$legacy_path"
                    bashio::log.info "Created compatibility symlink: $legacy_path -> $target_dir"
                fi
                
                migrated=true
                bashio::log.info "Migration completed from: $legacy_path"
            else
                bashio::log.warning "Failed to migrate from: $legacy_path"
            fi
        fi
    done

    if [ "$migrated" = false ]; then
        bashio::log.info "No existing authentication files found to migrate"
    fi
}

# Verify required tools. ttyd/jq/curl are baked into the image, so this is a
# no-op on a healthy build; only fall back to apk (network-dependent) if the
# terminal binary is somehow missing, instead of apk-ing on every boot.
install_tools() {
    if command -v ttyd >/dev/null 2>&1; then
        bashio::log.info "Required tools present (baked into image)"
        return 0
    fi
    bashio::log.warning "ttyd not found in image; installing at runtime..."
    if ! apk add --no-cache ttyd jq curl; then
        bashio::log.error "Failed to install required tools"
        exit 1
    fi
}

# (Removed setup_persistent_claude: it checked an obsolete
#  .../claude-code/cli.js path that current native installs no longer ship, so
#  it always warned and silently fell back, while npm-installing @latest into
#  /data/npm fought the baked-binary model. Claude is now baked at a pinned
#  CLAUDE_VERSION and the launcher is force-linked to it in init_environment.)

# Setup session picker script
setup_session_picker() {
    # Copy session picker script from built-in location
    if [ -f "/opt/scripts/claude-session-picker.sh" ]; then
        if ! cp /opt/scripts/claude-session-picker.sh /usr/local/bin/claude-session-picker; then
            bashio::log.error "Failed to copy claude-session-picker script"
            exit 1
        fi
        chmod +x /usr/local/bin/claude-session-picker
        bashio::log.info "Session picker script installed successfully"
    else
        bashio::log.warning "Session picker script not found, using auto-launch mode only"
    fi

    # Setup authentication helper if it exists
    if [ -f "/opt/scripts/claude-auth-helper.sh" ]; then
        chmod +x /opt/scripts/claude-auth-helper.sh
        bashio::log.info "Authentication helper script ready"
    fi
}

# Setup persistent package manager
setup_persistent_packages() {
    # Install persist-install command globally
    if [ -f "/opt/scripts/persist-install" ]; then
        cp /opt/scripts/persist-install /usr/local/bin/persist-install
        chmod +x /usr/local/bin/persist-install
        bashio::log.info "Persistent package manager installed: 'persist-install'"
    fi

    # Auto-install packages from configuration
    auto_install_packages
}

# Auto-install packages from add-on configuration
auto_install_packages() {
    # NOTE: bashio::config already expands a list option into newline-separated
    # raw values (it queries `.key[]` through `jq --raw-output`). Piping that
    # back through `jq -r '.[]'` double-parses it and aborts with
    # "jq: parse error: Invalid literal..." — so consume the lines directly.
    local apk_packages pip_packages
    apk_packages=$(bashio::config 'persistent_apk_packages')
    pip_packages=$(bashio::config 'persistent_pip_packages')

    # Check if any system (apk) packages are configured
    if [ -n "$apk_packages" ] && [ "$apk_packages" != "[]" ] && [ "$apk_packages" != "null" ]; then
        bashio::log.info "Auto-installing system packages from config..."
        while read -r pkg; do
            [ -n "$pkg" ] || continue
            bashio::log.info "  Installing: $pkg"
            /usr/local/bin/persist-install "$pkg" || bashio::log.warning "Failed to install: $pkg"
        done <<< "$apk_packages"
    fi

    # Check if any Python (pip) packages are configured
    if [ -n "$pip_packages" ] && [ "$pip_packages" != "[]" ] && [ "$pip_packages" != "null" ]; then
        bashio::log.info "Auto-installing Python packages from config..."

        # Collect all package names onto one line for a single pip invocation
        local all_packages
        all_packages=$(echo "$pip_packages" | tr '\n' ' ')

        if [ -n "${all_packages// /}" ]; then
            bashio::log.info "  Installing: $all_packages"
            /usr/local/bin/persist-install --python $all_packages || bashio::log.warning "Failed to install Python packages"
        fi
    fi
}

# Legacy monitoring functions removed - using simplified /data approach

# Determine Claude launch command based on configuration
# Session picker handles its own loop, so Claude exiting returns to the menu (#6)
get_claude_launch_command() {
    local auto_launch_claude
    local dangerously_skip_permissions
    local claude_flags=""

    # Get configuration values
    auto_launch_claude=$(bashio::config 'auto_launch_claude' 'true')
    dangerously_skip_permissions=$(bashio::config 'dangerously_skip_permissions' 'false')

    # Build Claude flags
    if [ "$dangerously_skip_permissions" = "true" ]; then
        claude_flags="--dangerously-skip-permissions"
        bashio::log.warning "Claude will run with --dangerously-skip-permissions (unrestricted file access)"
    fi

    if [ "$auto_launch_claude" = "true" ]; then
        # Auto-launch Claude first, then fall back to session picker on exit
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && echo 'Welcome to Claude Code!' && echo '' && echo 'Starting Claude...' && sleep 1 && claude ${claude_flags}; /usr/local/bin/claude-session-picker"
        else
            echo "clear && echo 'Welcome to Claude Code!' && echo '' && echo 'Starting Claude...' && sleep 1 && claude ${claude_flags}"
        fi
    else
        # Show interactive session picker (has its own while-true loop)
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && /usr/local/bin/claude-session-picker"
        else
            bashio::log.warning "Session picker not found, falling back to auto-launch"
            echo "clear && echo 'Welcome to Claude Code!' && echo '' && echo 'Starting Claude...' && sleep 1 && claude"
        fi
    fi
}


# Start image upload service
start_image_service() {
    local image_port=7680
    local ttyd_port=7681
    local upload_dir="/data/images"
    local service_dir="/opt/image-service"
    local server_file="${service_dir}/server.js"

    bashio::log.info "Starting image upload service on port ${image_port}..."

    # Create upload directory if it doesn't exist
    mkdir -p "${upload_dir}"
    chmod 755 "${upload_dir}"

    # Export environment variables for the image service
    export IMAGE_SERVICE_PORT="${image_port}"
    export TTYD_PORT="${ttyd_port}"
    export UPLOAD_DIR="${upload_dir}"

    # Check if server.js exists
    if [ ! -f "${server_file}" ]; then
        bashio::log.error "server.js not found at ${server_file}"
        ls -la "${service_dir}"
        return 1
    fi

    # Check if node_modules exists
    if [ ! -d "${service_dir}/node_modules" ]; then
        bashio::log.error "node_modules not found in ${service_dir}"
        bashio::log.info "Attempting to install dependencies..."
        cd "${service_dir}" && npm install || bashio::log.error "npm install failed"
        cd - > /dev/null
    fi

    # Start with better error logging (run from current directory with absolute path)
    bashio::log.info "Starting Node.js service from ${server_file}..."
    node "${server_file}" 2>&1 | while IFS= read -r line; do
        bashio::log.info "[Image Service] $line"
    done &

    # Store the PID for potential cleanup
    local image_service_pid=$!
    bashio::log.info "Image service started (PID: ${image_service_pid})"

    # Give it a moment to start
    sleep 3

    # Check if it's running
    if kill -0 "${image_service_pid}" 2>/dev/null; then
        bashio::log.info "Image service is running successfully"
    else
        bashio::log.error "Image service failed to start! Check logs above for errors"
        return 1
    fi
}

# Start main web terminal
start_web_terminal() {
    local port=7681
    bashio::log.info "Starting web terminal on port ${port}..."

    # Log environment information for debugging
    bashio::log.info "Environment variables:"
    bashio::log.info "ANTHROPIC_CONFIG_DIR=${ANTHROPIC_CONFIG_DIR}"
    bashio::log.info "HOME=${HOME}"

    # Get the appropriate launch command based on configuration
    local launch_command
    launch_command=$(get_claude_launch_command)

    # Log the configuration being used
    local auto_launch_claude
    auto_launch_claude=$(bashio::config 'auto_launch_claude' 'true')
    bashio::log.info "Auto-launch Claude: ${auto_launch_claude}"

    # Start the image upload service first
    start_image_service

    # Run ttyd with keepalive and reconnect configuration
    # --ping-interval 30: WebSocket ping every 30s (default 300s) to prevent idle disconnects
    # --client-option reconnect=5: xterm.js auto-reconnect after 5 seconds on disconnect
    exec ttyd \
        --port "${port}" \
        --interface 0.0.0.0 \
        --writable \
        --ping-interval 30 \
        --client-option reconnect=5 \
        bash -c "$launch_command"
}

# Run health check
run_health_check() {
    if [ -f "/opt/scripts/health-check.sh" ]; then
        bashio::log.info "Running system health check..."
        chmod +x /opt/scripts/health-check.sh
        /opt/scripts/health-check.sh || bashio::log.warning "Some health checks failed but continuing..."
    fi
}

# Main execution
main() {
    bashio::log.info "Initializing Claude Code for Home Assistant add-on..."

    # Run diagnostics first (especially helpful for VirtualBox issues)
    run_health_check

    init_environment
    install_tools
    setup_session_picker
    setup_persistent_packages
    start_web_terminal
}

# Execute main function
main "$@"