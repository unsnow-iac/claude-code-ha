ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install packages in a single layer to minimize image size.
# Node.js and npm kept for image-service dependency.
# ttyd + tmux are baked here (not apk'd at runtime) so the web terminal starts
# even when Alpine repos are unreachable, and tmux is always available.
RUN apk add --no-cache \
    nodejs \
    npm \
    bash \
    curl \
    nano \
    python3 \
    py3-pip \
    py3-requests \
    py3-aiohttp \
    py3-yaml \
    py3-beautifulsoup4 \
    jq \
    yq \
    git \
    vim \
    wget \
    tree \
    ttyd \
    tmux

# Install Claude Code CLI, pinned to a known-good version for reproducible
# builds. install.sh passes its argument to `claude install <version>`
# (stable | latest | X.Y.Z). Bump CLAUDE_VERSION to deliver a new Claude via
# an add-on release — that is the only supported update path; in-container
# `claude update` is disabled (DISABLE_AUTOUPDATER) and reset on restart.
# Native installer first (Bun runtime); npm fallback if the CPU lacks AVX.
ARG CLAUDE_VERSION=2.1.197
RUN (curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude) \
    || npm install -g @anthropic-ai/claude-code@"${CLAUDE_VERSION}"

# Install Home Assistant CLI (ha command), pinned + checksum-verified.
# Pinned (not `releases/latest`) for reproducible, offline-auditable builds and
# to drop the unauthenticated build-time GitHub API call. The HA CLI publishes
# no checksums file, so the expected sha256 of each release binary is hardcoded
# here — recompute both when bumping HA_CLI_VERSION:
#   curl -fsSL .../ha_<arch> | sha256sum
# Only the architectures this add-on actually builds (amd64, aarch64) are
# handled; see build.yaml / config.yaml `arch`.
ARG TARGETARCH
ARG HA_CLI_VERSION=5.2.0
RUN case "${TARGETARCH}" in \
        amd64)  HA_ARCH="amd64";   HA_SHA256="701be67aee9f1e092254097a40d006b450d1578641a262258b182237987e7479" ;; \
        arm64)  HA_ARCH="aarch64"; HA_SHA256="af8c03ccddb65d223d7b7dab1570197b8a2ff8fc7139c1db054d08a91a4f8073" ;; \
        *)      echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    echo "Installing Home Assistant CLI ${HA_CLI_VERSION} for ${HA_ARCH}..." && \
    curl -fsSL -o /usr/bin/ha \
        "https://github.com/home-assistant/cli/releases/download/${HA_CLI_VERSION}/ha_${HA_ARCH}" && \
    echo "${HA_SHA256}  /usr/bin/ha" | sha256sum -c - && \
    chmod +x /usr/bin/ha && \
    echo "Home Assistant CLI ${HA_CLI_VERSION} installed and verified"

# Install GitHub CLI (gh command), pinned + checksum-verified against the
# release's published gh_<ver>_checksums.txt (bump GH_VERSION to update).
ARG GH_VERSION=2.95.0
RUN case "${TARGETARCH}" in \
        amd64)  GH_ARCH="amd64" ;; \
        arm64)  GH_ARCH="arm64" ;; \
        *)      echo "Unsupported architecture for gh: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    GH_TARBALL="gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" && \
    echo "Installing GitHub CLI v${GH_VERSION} for ${GH_ARCH}..." && \
    curl -fsSL -o "/tmp/${GH_TARBALL}" \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${GH_TARBALL}" && \
    curl -fsSL -o /tmp/gh_checksums.txt \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt" && \
    (cd /tmp && grep " ${GH_TARBALL}$" gh_checksums.txt | sha256sum -c -) && \
    tar -xzf "/tmp/${GH_TARBALL}" -C /tmp && \
    mv /tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh /usr/bin/gh && \
    chmod +x /usr/bin/gh && \
    rm -rf /tmp/gh* && \
    echo "GitHub CLI v${GH_VERSION} installed and verified"

# Create directory for Claude configuration and set working directory
RUN mkdir -p /config/claude-config
WORKDIR /config

# Copy and install image service. `npm ci` installs strictly from the committed
# package-lock.json for reproducible builds (and gives Dependabot a lockfile to
# scan); it errors out if the lockfile and package.json ever drift.
COPY image-service/ /opt/image-service/
RUN cd /opt/image-service \
    && npm ci --omit=dev --omit=optional \
    && npm cache clean --force \
    && chmod +x server.js

# Copy startup script and modular scripts
COPY run.sh /run.sh
COPY scripts/ /opt/scripts/
COPY .claude/ /opt/.claude/
RUN chmod +x /run.sh \
    && chmod +x /opt/scripts/*.sh

# Use exec form for better signal handling
CMD ["/run.sh"]