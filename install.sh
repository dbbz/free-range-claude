#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(dirname "$(realpath "$0")")"

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
docker build ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} -t claude-sandbox "$INSTALL_DIR"
success "claude-sandbox image built"

# --- Add shell alias/abbreviation ---

step "Shell integration"

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

echo ""
printf "${GREEN}Done!${NC} Next steps:\n"
echo ""
printf "  ${BOLD}1.${NC} Reload your shell:  ${DIM}source ~/.zshrc${NC}\n"
printf "  ${BOLD}2.${NC} Set up a project:   ${DIM}cd my-project && claude-devcontainer-init${NC}\n"
printf "  ${BOLD}3.${NC} Start the sandbox:  ${DIM}just dev::up${NC}\n"
printf "  ${BOLD}4.${NC} Launch Claude:      ${DIM}just dev::claude${NC}\n"
echo ""
printf "${DIM}iTerm2 tip: set the tmux profile window style to Maximized${NC}\n"
printf "${DIM}  Preferences > Profiles > tmux > Window > Style: Maximized${NC}\n"
echo ""
