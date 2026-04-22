# .NET 10 SDK. The official SDK image ships with `app` + `ubuntu` users but no
# `vscode` user, so we create it ourselves — matches the convention used by
# Microsoft's devcontainers/* images and is what `remoteUser` expects.
FROM mcr.microsoft.com/dotnet/sdk:10.0

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Base tools. `sudo` is required by devcontainer features and by our
# install/ scripts (playwright --with-deps, apt-based docker install, ...).
# `python3` is used by install-terraform.sh to unzip without requiring unzip.
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip git ca-certificates gnupg lsb-release jq less sudo python3 \
 && rm -rf /var/lib/apt/lists/*

# Create the vscode user at UID 1000. The base image's `ubuntu` user already
# occupies 1000, so drop it first.
RUN if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu 2>/dev/null || true; fi \
 && groupadd --gid $USER_GID $USERNAME \
 && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/$USERNAME \
 && chmod 0440 /etc/sudoers.d/$USERNAME

# Bun, system-wide. Features install node/gh/az/terraform later.
RUN curl -fsSL https://bun.sh/install | bash \
 && mv /root/.bun /usr/local/bun \
 && ln -s /usr/local/bun/bin/bun /usr/local/bin/bun \
 && ln -s /usr/local/bun/bin/bunx /usr/local/bin/bunx

USER $USERNAME
