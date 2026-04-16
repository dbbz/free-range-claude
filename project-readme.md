# Claude Code Sandbox

This project uses [claude-devcontainer](https://github.com/dbbz/free-range-claude)
to run Claude Code autonomously inside a firewalled container.

## Usage

```bash
just dev::claude             # launch Claude Code (starts sandbox automatically)
just dev::claude -p "prompt" # run with a specific prompt
just dev::exec cargo test    # run any command inside the sandbox
just dev::exec zsh           # interactive shell inside the sandbox
just dev::status             # container & firewall health at a glance
just dev::logs               # tail container logs (-f to follow)
just dev::down               # stop and remove the container
just dev::rebuild            # rebuild image (cached) + restart
just dev::doctor             # verify and repair: tools, colima, image
just dev::playwright-on      # enable Playwright MCP (browser automation)
just dev::playwright-off     # disable it
```

Cmd+T in the iTerm2 window opens a new parallel Claude session.

## Files

- `devcontainer.json` -- container config: image, mounts, capabilities, firewall
- `dev.just` -- just module with all recipes
- `README.md` -- this file
