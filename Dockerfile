# Multi-platform FEX build with dynamic OS detection
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG TARGETPLATFORM 
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs
ARG LLVM_VERSION=18


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

# Install build dependencies based on detected OS
# Install build dependencies based on detected OS
RUN . /etc/distro-info && \
    if [ "$DISTRO_TYPE" = "debian" ]; then \
        apt-get update && apt-get install -y \
            git cmake ninja-build pkg-config ccache clang lld llvm \
            nasm python3-dev python3-clang python3-setuptools \
            libcap-dev libglfw3-dev libepoxy-dev libsdl2-dev \
            linux-headers-generic qtbase5-dev qtdeclarative5-dev \
            squashfs-tools squashfuse openssl libssl-dev \
            curl wget jq sudo binfmt-support software-properties-common && \ 
        if [ "${ROOTFS_OS}" = "ubuntu" ] && [ "${ROOTFS_VERSION}" != "24.04" ]; then \
            echo "Installing latest libstdc++6 for Ubuntu ${ROOTFS_VERSION}" && \
            add-apt-repository ppa:ubuntu-toolchain-r/test -y && \
            apt-get update && \
            apt-get install --only-upgrade libstdc++6 -y; \
        fi && \
        wget https://apt.llvm.org/llvm.sh && \
        chmod +x llvm.sh && \
        ./llvm.sh ${LLVM_VERSION} && \
        ln -sf /usr/bin/lld-${LLVM_VERSION} /usr/bin/ld.lld && \
        ln -sf /usr/bin/lld-${LLVM_VERSION} /usr/bin/lld && \
        rm llvm.sh && \
        rm -rf /var/lib/apt/lists/*; \
    elif [ "$DISTRO_TYPE" = "fedora" ]; then \
        dnf update -y && \
        if dnf list available llvm${LLVM_VERSION} 2>/dev/null; then \
            dnf install -y \
                @development-tools \
                llvm${LLVM_VERSION}* clang${LLVM_VERSION}* lld${LLVM_VERSION}* \
                compiler-rt${LLVM_VERSION} libomp${LLVM_VERSION} && \
        else \
            echo "LLVM ${LLVM_VERSION} not available, installing default LLVM" && \
            dnf install -y llvm llvm-devel clang clang-devel lld; \
        fi && \
        for tool in ar nm objdump strip; do \
            if [ ! -f "/usr/bin/llvm-$tool-${LLVM_VERSION}" ] && [ -f "/usr/bin/llvm-$tool" ]; then \
                ln -s "/usr/bin/llvm-$tool" "/usr/bin/llvm-$tool-${LLVM_VERSION}"; \
                echo "Created symlink: /usr/bin/llvm-$tool => /usr/bin/llvm-$tool-${LLVM_VERSION}"; \
            fi; \
        done; && \
        dnf install -y \
            git cmake ninja-build pkg-config ccache \
            openssl-devel nasm python3-clang python3-setuptools \
            squashfs-tools squashfuse erofs-fuse erofs-utils \
            qt5-qtdeclarative-devel qt5-qtquickcontrols qt5-qtquickcontrols2 \
            libcap-devel glfw-devel libepoxy-devel SDL2-devel \
            curl wget jq sudo util-linux-core && \
        dnf clean all; \
    elif [ "$DISTRO_TYPE" = "arch" ]; then \
        pacman -Syu --noconfirm && \
        pacman -S --noconfirm \
            git cmake ninja pkgconfig ccache clang lld llvm \
            nasm python python-setuptools openssl \
            libcap mesa sdl2 qt5-declarative \
            squashfs-tools \
            curl wget jq sudo util-linux && \
        pacman -Scc --noconfirm; \
    else \
        echo "❌ Unsupported distribution type: $DISTRO_TYPE" && exit 1; \
    fi

# Clone and build FEX from source
COPY --from=fex-sources / /tmp/fex-source  
RUN cd /tmp/fex-source && \
    mkdir -p Build && \
    cd Build && \
    CC=clang CXX=clang++ cmake \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_LINKER=lld \
        -DENABLE_LTO=True \
        -DBUILD_TESTS=False \
        -DENABLE_ASSERTIONS=False \
        -G Ninja \
        .. && \
    ninja && \
    ninja install && \
    rm -rf /tmp/fex-source/Build

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
    echo "✅ RootFS extracted and configured"

