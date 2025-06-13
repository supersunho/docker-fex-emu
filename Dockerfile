# Declare ARG before FROM command
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}
ARG TARGETPLATFORM 
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs
 
# Detect OS type and set package manager
RUN if [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then \
        echo "DISTRO_TYPE=fedora" > /etc/distro-info && \
        echo "PKG_MANAGER=dnf" >> /etc/distro-info; \
    elif [ -f /etc/arch-release ] || [ -f /etc/pacman.conf ]; then \
        echo "DISTRO_TYPE=arch" > /etc/distro-info && \
        echo "PKG_MANAGER=pacman" >> /etc/distro-info; \
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
        echo "DISTRO_TYPE=debian" > /etc/distro-info && \
        echo "PKG_MANAGER=apt" >> /etc/distro-info && \
        export DEBIAN_FRONTEND=noninteractive; \
    else \
        echo "DISTRO_TYPE=unknown" > /etc/distro-info && \
        echo "PKG_MANAGER=unknown" >> /etc/distro-info; \
    fi

# Install packages based on detected OS
RUN . /etc/distro-info && \
    if [ "$DISTRO_TYPE" = "debian" ]; then \
        apt-get update && apt-get install -y \
            curl wget jq sudo squashfs-tools binfmt-support software-properties-common && \
        if [ "${ROOTFS_OS}" = "ubuntu" ] && [ "${ROOTFS_VERSION}" != "24.04" ]; then \
            echo "Installing latest libstdc++6 for Ubuntu ${ROOTFS_VERSION}" && \
            add-apt-repository ppa:ubuntu-toolchain-r/test -y && \
            apt-get update && \
            apt-get install --only-upgrade libstdc++6 -y && \
            echo "GLIBCXX versions available:" && \
            strings /usr/lib/aarch64-linux-gnu/libstdc++.so.6 | grep GLIBCXX | tail -5; \
        else \
            echo "Using default libstdc++6 for Ubuntu ${ROOTFS_VERSION}"; \
        fi && \
        rm -rf /var/lib/apt/lists/*; \
    elif [ "$DISTRO_TYPE" = "fedora" ]; then \
        dnf update -y && \
        dnf install -y \
            curl wget jq sudo squashfs-tools util-linux-core && \
        dnf clean all; \
    elif [ "$DISTRO_TYPE" = "arch" ]; then \
        pacman -Syu --noconfirm && \
        pacman -S --noconfirm \
            curl wget jq sudo squashfs-tools util-linux && \
        pacman -Scc --noconfirm; \
    else \
        echo "❌ Unsupported distribution type: $DISTRO_TYPE" && exit 1; \
    fi

# Copy all FEX files prepared from workflow at once
COPY --from=fex-binaries / /usr/

# Verify execution permissions (insurance, already set in workflow)
RUN chmod +x /usr/bin/FEX* 2>/dev/null || true

# Create user with OS-specific commands
RUN . /etc/distro-info && \
    if [ "$DISTRO_TYPE" = "debian" ]; then \
        useradd -m -s /bin/bash fex && \
        usermod -aG sudo fex && \
        echo "fex ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/fex; \
    elif [ "$DISTRO_TYPE" = "fedora" ]; then \
        useradd -m -s /bin/bash fex && \
        usermod -aG wheel fex && \
        echo "fex ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/fex; \
    elif [ "$DISTRO_TYPE" = "arch" ]; then \
        useradd -m -s /bin/bash fex && \
        usermod -aG wheel fex && \
        echo "fex ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/fex; \
    fi

# Setup RootFS with dynamic version selection (OS-agnostic)
RUN echo "Setting up RootFS: ${ROOTFS_OS} ${ROOTFS_VERSION} (${ROOTFS_TYPE})" && \
    mkdir -p /home/fex/.fex-emu/RootFS && \
    curl -s https://rootfs.fex-emu.gg/RootFS_links.json > /tmp/rootfs_links.json && \
    # Handle latest version
    if [ "$ROOTFS_VERSION" = "latest" ]; then \
        ACTUAL_VERSION=$(jq -r --arg os "$ROOTFS_OS" --arg type "$ROOTFS_TYPE" \
            '.v1[] | select(.DistroMatch == $os and .Type == $type) | .DistroVersion' \
            /tmp/rootfs_links.json | sort -V | tail -1); \
    else \
        ACTUAL_VERSION="$ROOTFS_VERSION"; \
    fi && \
    echo "Target: $ROOTFS_OS $ACTUAL_VERSION ($ROOTFS_TYPE)" && \
    # Direct search
    ROOTFS_URL=$(jq -r --arg os "$ROOTFS_OS" --arg version "$ACTUAL_VERSION" --arg type "$ROOTFS_TYPE" \
        '.v1[] | select(.DistroMatch == $os and .DistroVersion == $version and .Type == $type) | .URL' \
        /tmp/rootfs_links.json) && \
    if [ -z "$ROOTFS_URL" ] || [ "$ROOTFS_URL" = "null" ]; then \
        echo "❌ $ROOTFS_OS $ACTUAL_VERSION ($ROOTFS_TYPE) not found" && \
        echo "Available options:" && \
        jq -r '.v1[] | "\(.DistroMatch) \(.DistroVersion) (\(.Type))"' /tmp/rootfs_links.json | sort -u && \
        exit 1; \
    fi && \
    echo "Download URL: $ROOTFS_URL" && \
    FILENAME=$(basename "$ROOTFS_URL") && \
    wget -q "$ROOTFS_URL" -O "/home/fex/.fex-emu/RootFS/${FILENAME}" && \
    echo "{\"Config\":{\"RootFS\":\"${FILENAME%.*}\"}}" > /home/fex/.fex-emu/Config.json && \
    chown -R fex:fex /home/fex/.fex-emu && \
    rm /tmp/rootfs_links.json && \
    echo "✅ RootFS installed: ${FILENAME}"

USER fex
WORKDIR /home/fex
