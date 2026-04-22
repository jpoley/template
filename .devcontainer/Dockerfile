# .NET 10 preview SDK image ships with vscode user and common build tools.
FROM mcr.microsoft.com/dotnet/sdk:10.0

ARG USERNAME=vscode

# Base tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl unzip git ca-certificates gnupg lsb-release jq less \
 && rm -rf /var/lib/apt/lists/*

# Bun (global, for all users)
RUN curl -fsSL https://bun.sh/install | bash \
 && mv /root/.bun /usr/local/bun \
 && ln -s /usr/local/bun/bin/bun /usr/local/bin/bun \
 && ln -s /usr/local/bun/bin/bunx /usr/local/bin/bunx

# Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash \
 || npm install -g @anthropic-ai/claude-code

# GitHub Copilot CLI extension is installed through `gh extension install github/gh-copilot`
# after the gh feature sets up the `gh` binary. We do that in postCreate.sh so it runs as the user.

USER $USERNAME
