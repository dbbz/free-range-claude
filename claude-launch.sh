#!/usr/bin/env bash
# Launcher used by tmux default-command. If CLAUDE_TAB_RGB="R;G;B" is set in
# the tmux session env, emit an iTerm2 "tab color" escape (OSC 1337), wrapped
# in tmux's DCS passthrough so the sequence reaches iTerm2 untouched. Any args
# are forwarded to claude.
#
# The escape is emitted twice — once immediately and once ~0.3s later from a
# backgrounded subshell — because iTerm2 sometimes hasn't finished associating
# the new tmux window with a native tab by the time the first one fires, and
# claude's own terminal init can clobber it. Two shots makes it stick.

if [ -n "${CLAUDE_TAB_RGB:-}" ]; then
    IFS=';' read -r R G B <<< "$CLAUDE_TAB_RGB"
    set_tab_color() {
        printf '\033Ptmux;\033\033]1337;SetColors=tab=%02x%02x%02x\007\033\\' "$R" "$G" "$B" || true
    }
    set_tab_color
    (sleep 0.3; set_tab_color) &
fi

exec claude --dangerously-skip-permissions "$@"
