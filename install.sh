#!/usr/bin/env bash
set -euo pipefail

# --- Self-bootstrap: clone template if needed, re-exec from canonical path ---
# This lets users install via: curl -fsSL <url>/install.sh | bash
TARGET="$HOME/.config/claude-devcontainer"
if [ "${CDEVC_BOOTSTRAPPED:-}" != "1" ]; then
    if [ ! -d "$TARGET/.git" ]; then
        command -v git &>/dev/null || { echo "git is required. Install it with: brew install git"; exit 1; }
        echo "Cloning free-range-claude to $TARGET..."
        git clone https://github.com/dbbz/free-range-claude.git "$TARGET"
    fi
    SELF="$(realpath "$0" 2>/dev/null || echo "")"
    if [ "$SELF" != "$TARGET/install.sh" ]; then
        export CDEVC_BOOTSTRAPPED=1
        exec bash "$TARGET/install.sh" "$@"
    fi
fi
INSTALL_DIR="$TARGET"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { printf "${BLUE}::${NC} %s\n" "$1"; }
success() { printf "${GREEN} ✓${NC} %s\n" "$1"; }
warn()    { printf "${YELLOW} !${NC} %s\n" "$1"; }
error()   { printf "${RED} ✗${NC} %s\n" "$1"; exit 1; }
step()    { printf "\n${BOLD}%s${NC}\n" "$1"; }

echo ""
printf "${BOLD}free-range-claude${NC} ${DIM}— install${NC}\n"
printf "${DIM}────────────────────────────────${NC}\n"
echo ""

# --- Check / install prerequisites ---

step "Checking prerequisites"

if ! command -v brew &>/dev/null; then
    error "Homebrew is required. Install it from https://brew.sh"
fi

for tool in colima docker just node; do
    if command -v "$tool" &>/dev/null; then
        success "$tool"
    else
        info "Installing $tool..."
        brew install "$tool"
        success "$tool installed"
    fi
done

if command -v devcontainer &>/dev/null; then
    success "devcontainer CLI"
else
    info "Installing devcontainer CLI..."
    npm install -g @devcontainers/cli
    success "devcontainer CLI installed"
fi

# --- Start colima if needed ---

step "Docker runtime"

if colima status &>/dev/null 2>&1; then
    success "Colima is running"
else
    info "Starting Colima..."
    colima start
    success "Colima started"
fi

# --- Build the base image ---

step "Building sandbox image"

BUILD_ARGS=()
if [ -n "${BASE_IMAGE:-}" ]; then
    info "Using base image: $BASE_IMAGE"
    BUILD_ARGS+=(--build-arg "BASE_IMAGE=$BASE_IMAGE")
fi

# Resolve Claude Code's latest version on the host so it becomes part of
# Docker's cache key — otherwise `@latest` in the Dockerfile is opaque to
# Docker and the npm-install layer is reused indefinitely.
if CLAUDE_VER=$(npm view @anthropic-ai/claude-code version 2>/dev/null) && [ -n "$CLAUDE_VER" ]; then
    info "Pinning Claude Code to $CLAUDE_VER (latest on npm)"
    BUILD_ARGS+=(--build-arg "CLAUDE_CODE_VERSION=$CLAUDE_VER")
else
    warn "Could not resolve latest Claude Code version from npm — image may use cached version"
fi

docker build --pull ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} -t claude-sandbox "$INSTALL_DIR"
success "claude-sandbox image built"

# --- Shell integration ---

step "Shell integration"

used_symlink=false

# Prefer symlink in ~/.local/bin (works immediately, no shell reload)
case ":$PATH:" in
    *":$HOME/.local/bin:"*)
        mkdir -p "$HOME/.local/bin"
        ln -sf "$INSTALL_DIR/init.sh" "$HOME/.local/bin/claude-devcontainer-init"
        success "Symlinked claude-devcontainer-init → ~/.local/bin (available immediately)"
        used_symlink=true
        ;;
esac

# Fall back to shell RC alias if symlink wasn't possible
if [ "$used_symlink" = false ]; then
    ALIAS_CMD="alias claude-devcontainer-init=\"$INSTALL_DIR/init.sh\""
    ABBR_CMD="abbr -a claude-devcontainer-init '$INSTALL_DIR/init.sh'"

    added_to_shell=false

    # zsh
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_RC_REAL="$(realpath "$HOME/.zshrc")"
        if grep -qF "claude-devcontainer-init" "$SHELL_RC_REAL" 2>/dev/null; then
            success "zsh alias already configured"
        else
            echo "" >> "$SHELL_RC_REAL"
            echo "$ALIAS_CMD" >> "$SHELL_RC_REAL"
            success "Added alias to .zshrc"
        fi
        added_to_shell=true
    fi

    # bash
    if [ -f "$HOME/.bashrc" ]; then
        BASH_RC_REAL="$(realpath "$HOME/.bashrc")"
        if grep -qF "claude-devcontainer-init" "$BASH_RC_REAL" 2>/dev/null; then
            success "bash alias already configured"
        else
            echo "" >> "$BASH_RC_REAL"
            echo "$ALIAS_CMD" >> "$BASH_RC_REAL"
            success "Added alias to .bashrc"
        fi
        added_to_shell=true
    fi

    # fish
    FISH_CONFIG="$HOME/.config/fish/config.fish"
    if [ -f "$FISH_CONFIG" ]; then
        if grep -qF "claude-devcontainer-init" "$FISH_CONFIG" 2>/dev/null; then
            success "fish abbreviation already configured"
        else
            echo "" >> "$FISH_CONFIG"
            echo "$ABBR_CMD" >> "$FISH_CONFIG"
            success "Added abbreviation to config.fish"
        fi
        added_to_shell=true
    fi

    if [ "$added_to_shell" = false ]; then
        warn "Could not find .zshrc, .bashrc, or config.fish"
        echo "  Add this alias manually:"
        printf "  ${DIM}%s${NC}\n" "$ALIAS_CMD"
    fi
fi

echo ""
printf "${GREEN}Done!${NC} Next steps:\n"
echo ""
if [ "$used_symlink" = true ]; then
    printf "  ${BOLD}1.${NC} Set up a project:  ${DIM}claude-devcontainer-init ~/my-project${NC}\n"
    printf "  ${BOLD}2.${NC} Launch Claude:     ${DIM}cd ~/my-project && just dev::claude${NC}\n"
else
    printf "  ${BOLD}1.${NC} Reload your shell: ${DIM}source ~/.zshrc${NC}\n"
    printf "  ${BOLD}2.${NC} Set up a project:  ${DIM}claude-devcontainer-init ~/my-project${NC}\n"
    printf "  ${BOLD}3.${NC} Launch Claude:     ${DIM}cd ~/my-project && just dev::claude${NC}\n"
fi
echo ""
printf "${DIM}iTerm2 tip: set the tmux profile window style to Maximized${NC}\n"
printf "${DIM}  Preferences > Profiles > tmux > Window > Style: Maximized${NC}\n"
echo ""
