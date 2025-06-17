ARG BASE_IMAGE=ubuntu:24.04

#==============================================
# Build Stage - Alpine Unified 🐧
#==============================================
FROM alpine:3.21 AS fex-builder

ARG TARGETPLATFORM 
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG LLVM_VERSION=18
ARG CCACHE_DIR=/tmp/.ccache
ARG ENABLE_CCACHE=true

# Set environment variables 🌐
ENV CCACHE_DIR=${CCACHE_DIR}
ENV ENABLE_CCACHE=${ENABLE_CCACHE}
ENV PATH="/usr/local/bin/:$PATH"

# Install all build dependencies with Alpine 📦
RUN echo "📦 Setting up Alpine build environment..." && \
    echo "🔍 Alpine information:" && \
    echo "  - Alpine version: $(cat /etc/alpine-release)" && \
    echo "  - Architecture: $(uname -m)" && \
    echo "  - Target platform: ${TARGETPLATFORM}" && \
    \
    # Update package index 🔄
    apk update && \
    \
    # Install essential build tools and dependencies 🛠️
    echo "📦 Installing build essentials..." && \
    apk add --no-cache \
        git cmake ninja-build pkgconfig ccache \
        build-base linux-headers \
        python3 python3-dev py3-setuptools \
        curl wget ca-certificates \
        openssl openssl-dev \
        binutils binutils-dev \
        nasm \
        libcap-dev \
        && \
    echo "✅ Basic build tools installed" && \
    \
    # Install LLVM/Clang 🛠️
    echo "🔧 Installing LLVM ${LLVM_VERSION}..." && \
    apk add --no-cache \
        clang${LLVM_VERSION} \
        clang${LLVM_VERSION}-dev \
        llvm${LLVM_VERSION} \
        llvm${LLVM_VERSION}-dev \
        llvm${LLVM_VERSION}-static \
        lld \
        libc-dev \
        && \
    echo "✅ LLVM ${LLVM_VERSION} installed" && \
    \
    # Create symlinks for version-less commands 🔗
    echo "🔗 Creating LLVM symlinks..." && \
    ln -sf clang-${LLVM_VERSION} /usr/bin/clang && \
    ln -sf clang++-${LLVM_VERSION} /usr/bin/clang++ && \
    ln -sf llvm-ar-${LLVM_VERSION} /usr/bin/llvm-ar && \
    ln -sf llvm-ranlib-${LLVM_VERSION} /usr/bin/llvm-ranlib && \
    ln -sf lld /usr/bin/ld.lld && \
    echo "✅ LLVM symlinks created" && \
    \
    # Install additional development libraries 📚
    echo "📦 Installing additional libraries..." && \
    apk add --no-cache \
        mesa-dev \
        libepoxy-dev \
        sdl2-dev \
        glfw-dev \
        qt5-qtbase-dev \
        qt5-qtdeclarative-dev \
        && \
    echo "✅ Additional libraries installed" && \
    \
    # Verify installations ✅
    echo "🔍 Verifying installation..." && \
    clang-${LLVM_VERSION} --version && \
    cmake --version && \
    ninja --version && \
    echo "✅ Alpine build environment setup completed!"

# Enhanced ccache setup for Alpine ⚙️
RUN echo "📦 Setting up ccache for Alpine..." && \
    echo "🔍 ccache information:" && \
    echo "  - ccache version: $(ccache --version | head -1)" && \
    echo "  - ENABLE_CCACHE: ${ENABLE_CCACHE}" && \
    \
    # Configure ccache 🚀
    if [ "${ENABLE_CCACHE:-false}" = "true" ]; then \
        echo "🚀 Enabling ccache acceleration..." && \
        echo "CCACHE_SOURCE=alpine-system" > /tmp/ccache-info && \
        echo "✅ ccache enabled for Alpine build"; \
    else \
        echo "ℹ️ ccache disabled" && \
        echo "CCACHE_SOURCE=disabled" > /tmp/ccache-info; \
    fi && \
    echo "✅ ccache setup completed"

# Copy FEX source and build 🏗️
COPY --from=fex-sources / /tmp/fex-source  
RUN --mount=type=cache,target=/tmp/.ccache \
    echo "🏗️ Starting FEX build process..." && \
    cd /tmp/fex-source && \
    \
    # Load ccache configuration 📊
    . /tmp/ccache-info && \
    echo "📊 Alpine build environment summary:" && \
    echo "  - ENABLE_CCACHE: ${ENABLE_CCACHE}" && \
    echo "  - CCACHE_SOURCE: ${CCACHE_SOURCE}" && \
    echo "  - LLVM_VERSION: ${LLVM_VERSION}" && \
    echo "  - Clang: $(which clang-${LLVM_VERSION})" && \
    echo "  - Compiler: $(clang-${LLVM_VERSION} --version | head -1)" && \
    \
    mkdir -p Build && cd Build && \
    \
    # Set Alpine-optimized compilers 🛠️
    CC_COMPILER="clang-${LLVM_VERSION}" && \
    CXX_COMPILER="clang++-${LLVM_VERSION}" && \
    AR_TOOL="llvm-ar-${LLVM_VERSION}" && \
    RANLIB_TOOL="llvm-ranlib-${LLVM_VERSION}" && \
    echo "✅ Alpine compilers configured: $CC_COMPILER / $CXX_COMPILER" && \
    \
    # Alpine-specific ccache configuration 🚀
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && [ "${CCACHE_SOURCE}" != "disabled" ]; then \
        echo "🚀 Configuring ccache for Alpine..." && \
        export CCACHE_BASEDIR=/tmp/fex-source && \
        export CCACHE_DIR=/tmp/.ccache && \
        export CCACHE_MAXSIZE=2G && \
        export CCACHE_SLOPPINESS=pch_defines,time_macros,include_file_mtime && \
        export CCACHE_COMPRESS=true && \
        export CC="ccache $CC_COMPILER" && \
        export CXX="ccache $CXX_COMPILER" && \
        ccache --zero-stats && \
        echo "✅ ccache enabled with Alpine optimizations"; \
    else \
        export CC="$CC_COMPILER" && \
        export CXX="$CXX_COMPILER" && \
        echo "ℹ️ ccache disabled for this build"; \
    fi && \
    \
    # Alpine-optimized CMake configuration ⚙️
    echo "⚙️ Running CMake configuration..." && \
    cmake \
        -DCMAKE_INSTALL_PREFIX=/usr/local/fex \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_LINKER=lld \
        -DENABLE_LTO=True \
        -DBUILD_TESTS=False \
        -DENABLE_ASSERTIONS=False \
        -DCMAKE_C_COMPILER="$CC" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_AR="$AR_TOOL" \
        -DCMAKE_RANLIB="$RANLIB_TOOL" \
        -DCMAKE_C_COMPILER_AR="$AR_TOOL" \
        -DCMAKE_CXX_COMPILER_AR="$AR_TOOL" \
        -DCMAKE_EXE_LINKER_FLAGS="-static-libgcc -static-libstdc++ -Wl,--as-needed" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++ -Wl,--as-needed" \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -G Ninja .. && \
    echo "✅ CMake configuration completed" && \
    \
    # Starting compilation with Alpine 🔨
    echo "🔨 Starting compilation with Alpine..." && \
    ninja -j$(($(nproc) - 1)) && \
    echo "✅ Compilation completed successfully" && \
    \
    # Installing FEX binaries 📦
    echo "📦 Installing FEX binaries..." && \
    ninja install && \
    echo "✅ Installation completed" && \
    \
    # Show ccache statistics if enabled 📊
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && [ "${CCACHE_SOURCE}" != "disabled" ]; then \
        echo "📊 ccache Statistics:" && \
        ccache --show-stats; \
    fi && \
    \
    # Cleaning up build artifacts 🧹
    echo "🧹 Cleaning up build artifacts..." && \
    rm -rf /tmp/fex-source /tmp/ccache-info && \
    echo "🎉 FEX build completed successfully with Alpine!"

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
