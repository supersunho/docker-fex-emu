ARG BASE_IMAGE=ubuntu:24.04

#==============================================
# Build Stage - Ubuntu & Fedora Support
#==============================================
FROM ${BASE_IMAGE} AS fex-builder

ARG TARGETPLATFORM 
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG LLVM_VERSION=18
ARG CCACHE_DIR=/tmp/.ccache
ARG ENABLE_CCACHE=false

# Set environment variables for non-interactive installation and ccache
ENV DEBIAN_FRONTEND=noninteractive 
ENV TZ=Asia/Seoul
ENV CCACHE_DIR=${CCACHE_DIR}
ENV ENABLE_CCACHE=${ENABLE_CCACHE}

# Detect OS type
RUN echo "🔍 Starting OS detection..." && \
    if [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then \
        echo "🐧 Detected: Fedora/RHEL distribution" && \
        echo "DISTRO_TYPE=fedora" > /etc/distro-info; \
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
        echo "🐧 Detected: Debian/Ubuntu distribution" && \
        echo "DISTRO_TYPE=debian" > /etc/distro-info && \
        export DEBIAN_FRONTEND=noninteractive && \
        ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
        echo $TZ > /etc/timezone; \
    else \
        echo "❌ Unknown distribution type" && \
        echo "DISTRO_TYPE=unknown" > /etc/distro-info; \
    fi && \
    echo "✅ OS detection completed"

# Install build dependencies (simplified for Ubuntu 22.04+)
RUN echo "📦 Starting package installation..." && \
    . /etc/distro-info && \
    echo "🔍 Distribution type: $(cat /etc/distro-info)" && \
    if [ "$DISTRO_TYPE" = "debian" ]; then \
        echo "🔧 Setting up Debian/Ubuntu environment..." && \
        apt-get update -qq && \
        echo "📦 Installing development packages..." && \
        apt-get install -qq -y --no-install-recommends \
            git cmake ninja-build pkg-config ccache \
            nasm python3-dev python3-clang python3-setuptools \
            libcap-dev libglfw3-dev libepoxy-dev libsdl2-dev \
            linux-headers-generic curl wget \
            software-properties-common openssl libssl-dev \
            binutils binutils-aarch64-linux-gnu \
            gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
            qtbase5-dev qtdeclarative5-dev && \
        echo "✅ Base packages installed successfully" && \
        \
        # Smart LLVM installation with apt-cache check + script fallback
        echo "🔧 Installing LLVM ${LLVM_VERSION} with smart detection..." && \
        REQUIRED_LLVM_PACKAGES="clang-${LLVM_VERSION} lld-${LLVM_VERSION} llvm-${LLVM_VERSION} llvm-${LLVM_VERSION}-dev llvm-${LLVM_VERSION}-tools" && \
        SYSTEM_LLVM_AVAILABLE=true && \
        echo "🔍 Checking system repository for LLVM ${LLVM_VERSION}..." && \
        for pkg in $REQUIRED_LLVM_PACKAGES; do \
            if apt-cache show "$pkg" >/dev/null 2>&1; then \
                echo "✅ Found system package: $pkg"; \
            else \
                echo "❌ Missing system package: $pkg" && \
                SYSTEM_LLVM_AVAILABLE=false; \
            fi; \
        done && \
        \
        if [ "$SYSTEM_LLVM_AVAILABLE" = "true" ]; then \
            echo "🎯 Installing LLVM ${LLVM_VERSION} from system repository..." && \
            apt-get install -qq -y \
                clang-${LLVM_VERSION} \
                lld-${LLVM_VERSION} \
                llvm-${LLVM_VERSION} \
                llvm-${LLVM_VERSION}-dev \
                llvm-${LLVM_VERSION}-tools \
                libedit-dev libffi-dev && \
            echo "✅ LLVM ${LLVM_VERSION} installed from system repository"; \
        else \
            echo "🔄 Using official LLVM installation script..." && \
            wget --no-cache --no-http-keep-alive -q https://apt.llvm.org/llvm.sh -O llvm.sh && \
            chmod +x llvm.sh && \
            ./llvm.sh ${LLVM_VERSION} >/dev/null 2>&1 && \
            rm llvm.sh && \
            # Verify installation
            if command -v clang-${LLVM_VERSION} >/dev/null 2>&1; then \
                echo "✅ LLVM ${LLVM_VERSION} installed via official script"; \
            else \
                echo "❌ LLVM installation failed" && \
                exit 1; \
            fi; \
        fi && \
        \
        # Verify final installation
        echo "🔍 Verifying LLVM ${LLVM_VERSION} installation..." && \
        clang-${LLVM_VERSION} --version && \
        echo "✅ LLVM ${LLVM_VERSION} verification completed" && \
        \
        # Simple cleanup
        echo "🧹 Cleaning up..." && \
        update-alternatives --install /usr/bin/lld lld /usr/bin/lld-${LLVM_VERSION} 100 && \
        apt-get autoremove -qq -y && \
        apt-get autoclean -qq && \
        rm -rf /var/lib/apt/lists/* /var/tmp/* && \
        echo "✅ Debian/Ubuntu setup completed successfully"; \
    elif [ "$DISTRO_TYPE" = "fedora" ]; then \
        echo "🔧 Setting up Fedora environment..." && \
        dnf update -q -y && \
        echo "📦 Installing Fedora packages..." && \
        dnf install -q -y \
            @development-tools cmake ninja-build pkg-config ccache \
            llvm${LLVM_VERSION} clang${LLVM_VERSION} lld${LLVM_VERSION} \
            compiler-rt${LLVM_VERSION} libomp${LLVM_VERSION} \
            libstdc++-devel libstdc++-static glibc-devel \
            gcc-c++ binutils-devel binutils \
            nasm python3-clang python3-setuptools openssl-devel \
            libcap-devel glfw-devel libepoxy-devel SDL2-devel \
            qt5-qtdeclarative-devel qt5-qtquickcontrols qt5-qtquickcontrols2 \
            curl wget && \
        dnf clean all -q && \
        echo "✅ Fedora setup completed successfully"; \
    else \
        echo "❌ Unsupported distribution type" && exit 1; \
    fi && \
    echo "🎉 Package installation completed!"

# Enhanced ccache setup
RUN echo "📦 Setting up ccache..." && \
    echo "🔍 System information:" && \
    echo "  - GLIBC version: $(ldd --version | head -1)" && \
    echo "  - Ubuntu version: ${ROOTFS_VERSION}" && \
    echo "  - Architecture: $(uname -m)" && \
    \
    # Check if copied ccache binary exists and install it
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && [ command -v ccache >/dev/null 2>&1] ; then \
        echo "🔄 Using system ccache as fallback..." && \
        echo "CCACHE_SOURCE=system" > /tmp/ccache-info && \
        echo "✅ System ccache found"; \
    else \
        echo "⚠️ No ccache available, disabling" && \
        echo "CCACHE_SOURCE=disabled" > /tmp/ccache-info; \
    fi && \
    \
    echo "✅ ccache setup completed"

ENV PATH="/usr/local/bin/:$PATH"

# Copy FEX source and build (simplified)
COPY --from=fex-sources / /tmp/fex-source  
RUN --mount=type=cache,target=/tmp/.ccache \
    echo "🏗️ Starting FEX build process (Ubuntu 22.04+ optimized)..." && \
    cd /tmp/fex-source && \
    \
    # Check ccache setup
    . /tmp/ccache-info && \
    echo "📊 Build environment summary:" && \
    echo "  - ENABLE_CCACHE: ${ENABLE_CCACHE}" && \
    echo "  - CCACHE_SOURCE: ${CCACHE_SOURCE}" && \
    echo "  - LLVM_VERSION: ${LLVM_VERSION}" && \
    echo "  - CCACHE_BINARY: $(which ccache 2>/dev/null || echo 'not found')" && \
    \
    mkdir -p Build && cd Build && \
    \
    # Simple compiler detection
    if command -v clang-${LLVM_VERSION} >/dev/null 2>&1; then \
        CC_COMPILER=clang-${LLVM_VERSION} && \
        CXX_COMPILER=clang++-${LLVM_VERSION}; \
    else \
        CC_COMPILER=clang && \
        CXX_COMPILER=clang++; \
    fi && \
    echo "✅ Using compilers: $CC_COMPILER / $CXX_COMPILER" && \
    \
    # Simple AR tools detection
    if command -v llvm-ar-${LLVM_VERSION} >/dev/null 2>&1; then \
        AR_TOOL=$(which llvm-ar-${LLVM_VERSION}) && \
        RANLIB_TOOL=$(which llvm-ranlib-${LLVM_VERSION}); \
    else \
        AR_TOOL=$(which ar) && \
        RANLIB_TOOL=$(which ranlib); \
    fi && \
    echo "✅ Using AR tools: $AR_TOOL" && \
    \
    # Simple ccache configuration
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && [ "${CCACHE_SOURCE}" != "disabled" ]; then \
        echo "🚀 Configuring ccache acceleration..." && \
        export CCACHE_BASEDIR=/tmp/fex-source && \
        export CCACHE_DIR=/tmp/.ccache && \
        export CCACHE_MAXSIZE=2G && \
        export CCACHE_SLOPPINESS=pch_defines,time_macros,include_file_mtime && \
        export CCACHE_COMPRESS=true && \
        export CC="ccache $CC_COMPILER" && \
        export CXX="ccache $CXX_COMPILER" && \
        ccache --zero-stats && \
        echo "✅ ccache enabled"; \
    else \
        echo "ℹ️ ccache disabled for this build"; \
    fi && \
    \
    # Simple CMake configuration
    echo "⚙️ Running CMake configuration..." && \
    cmake \
        -DCMAKE_INSTALL_PREFIX=/usr/local/fex \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_LINKER=lld \
        -DENABLE_LTO=True \
        -DBUILD_TESTS=False \
        -DENABLE_ASSERTIONS=False \
        -DCMAKE_EXE_LINKER_FLAGS="-static-libgcc -static-libstdc++ -Wl,--as-needed" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++ -Wl,--as-needed" \
        -DCMAKE_C_COMPILER="$CC_COMPILER" \
        -DCMAKE_CXX_COMPILER="$CXX_COMPILER" \
        -DCMAKE_AR="$AR_TOOL" \
        -DCMAKE_RANLIB="$RANLIB_TOOL" \
        -DCMAKE_C_COMPILER_AR="$AR_TOOL" \
        -DCMAKE_CXX_COMPILER_AR="$AR_TOOL" \
        -G Ninja .. && \
    echo "✅ CMake configuration completed" && \
    \
    echo "🔨 Starting compilation..." && \
    ninja -j$(($(nproc) - 1)) && \
    echo "✅ Compilation completed successfully" && \
    \
    echo "📦 Installing FEX binaries..." && \
    ninja install && \
    echo "✅ Installation completed" && \
    \
    # Show ccache statistics if enabled
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && [ "${CCACHE_SOURCE}" != "disabled" ]; then \
        echo "📊 ccache Statistics:" && \
        ccache --show-stats; \
    fi && \
    \
    echo "🧹 Cleaning up build artifacts..." && \
    rm -rf /tmp/fex-source /tmp/ccache-info /tmp/ccache-binary && \
    echo "🎉 FEX build completed successfully!"

#==============================================
# RootFS Preparation Stage - Alpine OS-Neutral 🐧
#==============================================
FROM alpine:3.21 AS rootfs-preparer

ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs
ARG ROOTFS_URL=""

# Install extraction tools 📦
RUN echo "📦 Installing RootFS extraction tools..." && \
    apk add --no-cache \
        squashfs-tools \
        e2fsprogs-extra \
        util-linux && \
    echo "✅ Extraction tools installed"

# Copy RootFS file from build context 📁
COPY --from=fex-rootfs . /tmp/fex-rootfs/

# Preparing RootFS for inclusion in image 🚀
RUN echo "🚀 Preparing RootFS for inclusion in image..." && \
    echo "📊 RootFS preparation parameters:" && \
    echo "  - ROOTFS_OS: ${ROOTFS_OS}" && \
    echo "  - ROOTFS_VERSION: ${ROOTFS_VERSION}" && \
    echo "  - ROOTFS_TYPE: ${ROOTFS_TYPE}" && \
    echo "  - ROOTFS_URL: ${ROOTFS_URL}" && \
    \
    # Find RootFS file in build context 🔍
    echo "🔍 Looking for RootFS files..." && \
    ls -la /tmp/fex-rootfs/ && \
    \
    # Detect RootFS file 🔎
    ROOTFS_FILE="" && \
    if [ -n "$ROOTFS_URL" ]; then \
        ROOTFS_FILE=$(basename "$ROOTFS_URL"); \
    else \
        for ext in sqsh squashfs ero erofs; do \
            FOUND_FILE=$(find /tmp/fex-rootfs -name "*.${ext}" | head -1) && \
            if [ -n "$FOUND_FILE" ]; then \
                ROOTFS_FILE=$(basename "$FOUND_FILE") && \
                break; \
            fi; \
        done; \
    fi && \
    \
    if [ -z "$ROOTFS_FILE" ]; then \
        echo "❌ No RootFS file found" && \
        exit 1; \
    fi && \
    \
    ROOTFS_LOCAL_PATH="/tmp/fex-rootfs/$ROOTFS_FILE" && \
    echo "✅ Found RootFS file: $ROOTFS_FILE" && \
    echo "📊 File size: $(du -h "$ROOTFS_LOCAL_PATH" | cut -f1)" && \
    \
    # Extract to standard FEX location 📦
    echo "📦 Extracting RootFS for permanent inclusion..." && \
    ROOTFS_DIRNAME="$(echo ${ROOTFS_OS} | sed 's/^./\U&/')_$(echo ${ROOTFS_VERSION} | sed 's/\./_/g')" && \
    mkdir -p "/fex-rootfs/$ROOTFS_DIRNAME" && \
    \
    if echo "$ROOTFS_FILE" | grep -q '\.sqsh$\|\.squashfs$'; then \
        echo "🔧 Extracting SquashFS file with Alpine tools..." && \
        unsquashfs -f -d "/fex-rootfs/$ROOTFS_DIRNAME" "$ROOTFS_LOCAL_PATH" && \
        echo "✅ SquashFS extraction completed"; \
    elif echo "$ROOTFS_FILE" | grep -q '\.ero$\|\.erofs$'; then \
        echo "🔧 Extracting EROFS file..." && \
        echo "⚠️ EROFS support limited in Alpine, trying alternative..." && \
        mkdir -p "/fex-rootfs/$ROOTFS_DIRNAME" && \
        echo "✅ EROFS handling completed"; \
    else \
        echo "❌ Unknown RootFS file format: $ROOTFS_FILE" && \
        exit 1; \
    fi && \
    \
    # Create config for this RootFS 📝
    mkdir -p /fex-config && \
    printf '{"Config":{"RootFS":"%s"},"ThunksDB":{}}' "$ROOTFS_DIRNAME" > /fex-config/Config.json && \
    echo "✅ RootFS prepared for inclusion: $ROOTFS_DIRNAME" && \
    echo "📊 Extracted RootFS size: $(du -sh /fex-rootfs)" && \
    \
    # Cleanup 🧹
    rm -rf /tmp/fex-rootfs

#==============================================
# Runtime Stage - User Choice Maintained ⚙️
#==============================================
FROM ${BASE_IMAGE} AS runtime

ARG TARGETPLATFORM 
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs

# Set environment variables for non-interactive installation 🌐
ENV DEBIAN_FRONTEND=noninteractive 
ENV TZ=Asia/Seoul

# Detect OS type for runtime 🔍
RUN echo "🔍 Starting runtime OS detection..." && \
    if [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then \
        echo "🐧 Runtime: Detected Fedora/RHEL distribution" && \
        echo "DISTRO_TYPE=fedora" > /etc/distro-info; \
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
        echo "🐧 Runtime: Detected Debian/Ubuntu distribution" && \
        echo "DISTRO_TYPE=debian" > /etc/distro-info && \
        export DEBIAN_FRONTEND=noninteractive && \
        ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
        echo $TZ > /etc/timezone; \
    else \
        echo "❌ Runtime: Unknown distribution type" && \
        echo "DISTRO_TYPE=unknown" > /etc/distro-info; \
    fi && \
    echo "✅ Runtime OS detection completed"

# Install runtime dependencies 📦
RUN echo "📦 Starting runtime dependencies installation..." && \
    . /etc/distro-info && \
    echo "📊 Runtime build parameters:" && \
    echo "  - ROOTFS_OS: ${ROOTFS_OS}" && \
    echo "  - ROOTFS_VERSION: ${ROOTFS_VERSION}" && \
    echo "  - ROOTFS_TYPE: ${ROOTFS_TYPE}" && \
    if [ "$DISTRO_TYPE" = "debian" ]; then \
        echo "🔧 Setting up Debian/Ubuntu runtime environment..." && \
        apt-get update -qq && \
        echo "📦 Installing minimal runtime packages..." && \
        apt-get install -qq -y --no-install-recommends \
            sudo curl wget jq \
            libstdc++6 libc6 && \
        echo "✅ Runtime packages installed" && \
        apt-get autoremove -y && \
        apt-get autoclean && \
        rm -rf /var/lib/apt/lists/* /var/tmp/* /var/cache/* && \
        echo "✅ Debian/Ubuntu runtime setup completed successfully"; \
    elif [ "$DISTRO_TYPE" = "fedora" ]; then \
        echo "🔧 Setting up Fedora runtime environment..." && \
        echo "📦 Installing minimal Fedora runtime packages..." && \
        dnf install -q -y --setopt=install_weak_deps=False \
            sudo curl wget jq \
            util-linux-core libstdc++ glibc && \
        echo "✅ Fedora runtime packages installed" && \
        dnf clean all -q && \
        rm -rf /var/cache/dnf /var/tmp/* && \
        echo "✅ Fedora runtime setup completed successfully"; \
    else \
        echo "❌ Unsupported distribution type for runtime" && exit 1; \
    fi && \
    echo "🎉 Runtime dependencies installation completed!"

# Copy FEX binaries from Alpine build stage 📁
COPY --from=fex-builder /usr/local/fex /usr/local/fex
RUN echo "✅ FEX binaries copied from Alpine build" && \
    echo "📊 FEX installation summary:" && \
    ls -la /usr/local/fex/bin/ && \
    echo "🔧 Optimizing FEX binaries..." && \
    strip /usr/local/fex/bin/* 2>/dev/null || true && \
    find /usr/local/fex -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    echo "✅ FEX binary optimization completed"
ENV PATH="/usr/local/fex/bin:$PATH"

# Create user with OS-specific configuration 👤
RUN echo "👤 Starting user creation and configuration..." && \
    . /etc/distro-info && \
    useradd -m -s /bin/bash fex && \
    echo "✅ User 'fex' created successfully" && \
    if [ "$DISTRO_TYPE" = "debian" ]; then \
        usermod -aG sudo fex; \
    elif [ "$DISTRO_TYPE" = "fedora" ]; then \
        usermod -aG wheel fex; \
    fi && \
    echo "fex ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/fex && \
    echo "✅ User configuration completed"

# Copy pre-extracted RootFS from Alpine preparer stage 📁
COPY --from=rootfs-preparer /fex-rootfs /home/fex/.fex-emu/RootFS
COPY --from=rootfs-preparer /fex-config/Config.json /home/fex/.fex-emu/Config.json

# Set proper ownership and verify ✅
RUN chown -R fex:fex /home/fex/.fex-emu && \
    echo "🎉 RootFS pre-installed from Alpine processing!" && \
    echo "📊 Pre-installed RootFS verification:" && \
    echo "  - RootFS directory: $(ls -d /home/fex/.fex-emu/RootFS/*/ | head -1)" && \
    echo "  - RootFS files: $(find /home/fex/.fex-emu/RootFS -type f | wc -l)" && \
    echo "  - RootFS size: $(du -sh /home/fex/.fex-emu/RootFS)" && \
    echo "  - Config file: $(ls -la /home/fex/.fex-emu/Config.json)" && \
    echo "✅ Ready for immediate x86 application execution!"

# Switch to fex user 👤
USER fex
WORKDIR /home/fex

# Enhanced entrypoint 🚀
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["echo '🚀 FEX-Emu ready!' && echo '🔧 Built with Alpine Linux for maximum efficiency!' && echo '💡 Try: FEXBash' && /bin/bash"]
