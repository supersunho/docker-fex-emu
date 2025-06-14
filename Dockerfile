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
COPY --from=builder /tmp/fex-build/bin/* /usr/bin/
COPY --from=builder /tmp/fex-build/lib/libFEXCore.so /usr/lib/
COPY --from=builder /tmp/fex-build/lib/binfmt.d/ /usr/lib/binfmt.d/
COPY --from=builder /tmp/fex-build/share/fex-emu/ /usr/share/fex-emu/

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

USER fex
WORKDIR /home/fex

# Setup RootFS using FEXRootFSFetcher
RUN FEXRootFSFetcher -yx --distro-name=${ROOTFS_OS} --distro-version=${ROOTFS_VERSION} --force-ui=tty && \
    chown -R fex:fex /home/fex/.fex-emu && \
    rm -rf /home/fex/.fex-emu/RootFS/*.sqsh && \
    rm -rf /home/fex/.fex-emu/RootFS/*.ero && \
    echo "✅ RootFS extracted and configured"

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/bin/bash"]