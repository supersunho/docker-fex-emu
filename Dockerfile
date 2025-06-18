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
        echo "DISTRO_TYPE=fedora" > /etc/distro-info && \
        echo "🔧 Configuring DNF cache for Fedora/RHEL..." && \
        echo "keepcache=True" >> /etc/dnf/dnf.conf && \
        echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf; \
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
        echo "🐧 Detected: Debian/Ubuntu distribution" && \
        echo "DISTRO_TYPE=debian" > /etc/distro-info && \
        export DEBIAN_FRONTEND=noninteractive && \
        ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
        echo $TZ > /etc/timezone && \
        echo "🔧 Configuring APT cache for Ubuntu/Debian..." && \
        rm -f /etc/apt/apt.conf.d/docker-clean && \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
    else \
        echo "❌ Unknown distribution type" && \
        echo "DISTRO_TYPE=unknown" > /etc/distro-info; \
    fi && \
    echo "✅ OS detection completed"

# Install build dependencies  
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    echo "📦 Starting package installation..." && \
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
        rm -rf /var/tmp/* && \
        echo "✅ Debian/Ubuntu setup completed successfully"; \
    elif [ "$DISTRO_TYPE" = "fedora" ]; then \
        echo "🔧 Setting up Fedora environment..." && \
        dnf update -q -y && \
        # Universal Fedora dnf optimization  
        echo "📦 Optimizing dnf configuration for all Fedora versions..." && \
        echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf && \
        echo "fastestmirror=True" >> /etc/dnf/dnf.conf && \
        echo "📦 Installing Fedora packages with optimizations..." && \
        dnf groupinstall -q -y "Development Tools" -x grubby && \
        dnf install -q -y --setopt=install_weak_deps=False \
            cmake ninja-build pkg-config ccache \
            llvm clang lld compiler-rt libomp \
            libstdc++-devel libstdc++-static glibc-devel \
            gcc-c++ binutils-devel binutils \
            nasm python3-clang python3-setuptools openssl-devel \
            libcap-devel glfw-devel libepoxy-devel SDL2-devel \
            qt5-qtdeclarative-devel qt5-qtquickcontrols qt5-qtquickcontrols2 \
            curl wget which && \ 
        \
        echo "✅ Fedora setup completed successfully"; \
    else \
        echo "❌ Unsupported distribution type" && exit 1; \
    fi && \
    echo "🎉 Package installation completed!"

# ccache setup 
RUN echo "📦 Setting up ccache..." && \
    echo "🔍 System information:" && \
    echo "  - GLIBC version: $(ldd --version | head -1)" && \
    echo "  - Ubuntu version: ${ROOTFS_VERSION}" && \
    echo "  - Architecture: $(uname -m)" && \
    \
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && command -v ccache >/dev/null 2>&1; then \
        echo "🔄 Using system ccache..." && \
        echo "CCACHE_SOURCE=system" > /tmp/ccache-info && \
        echo "✅ System ccache found"; \
    else \
        echo "⚠️ No ccache available, disabling" && \
        echo "CCACHE_SOURCE=disabled" > /tmp/ccache-info; \
    fi && \
    \
    echo "✅ ccache setup completed"

ENV PATH="/usr/local/bin/:$PATH"

# Copy FEX source from build context  
COPY --from=fex-sources / /tmp/fex-source  
RUN --mount=type=cache,target=/tmp/.ccache \
    echo "🏗️ Starting FEX build process (V4 Optimized)..." && \
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
    # Enhanced ccache configuration  
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && [ "${CCACHE_SOURCE}" != "disabled" ]; then \
        echo "🚀 Configuring ccache acceleration..." && \
        export CCACHE_BASEDIR=/tmp/fex-source && \
        export CCACHE_DIR=/tmp/.ccache && \
        export CCACHE_MAXSIZE=2G && \
        export CCACHE_SLOPPINESS=pch_defines,time_macros && \
        export CC="ccache $CC_COMPILER" && \
        export CXX="ccache $CXX_COMPILER" && \
        ccache --zero-stats && \
        echo "✅ ccache enabled with optimizations"; \
    else \
        echo "ℹ️ ccache disabled for this build"; \
    fi && \
    \
    # Enhanced CMake configuration with static linking for compatibility
    echo "⚙️ Running CMake configuration..." && \
    cmake \
        -DCMAKE_INSTALL_PREFIX=/usr/local/fex \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_LINKER=lld \
        -DENABLE_LTO=True \
        -DBUILD_TESTS=False \
        -DENABLE_ASSERTIONS=False \
        -DCMAKE_C_COMPILER="$CC_COMPILER" \
        -DCMAKE_CXX_COMPILER="$CXX_COMPILER" \
        -DCMAKE_AR="$AR_TOOL" \
        -DCMAKE_RANLIB="$RANLIB_TOOL" \
        -DCMAKE_C_COMPILER_AR="$AR_TOOL" \
        -DCMAKE_CXX_COMPILER_AR="$AR_TOOL" \
        -DCMAKE_EXE_LINKER_FLAGS="-static-libgcc -static-libstdc++" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++" \
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
    rm -rf /tmp/fex-source /tmp/ccache-info && \
    echo "🎉 FEX build completed successfully!"

#==============================================
# RootFS Preparation Stage (Ubuntu-based)
#==============================================
FROM ubuntu:24.04 AS rootfs-preparer

ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs
ARG ROOTFS_URL=""

# Install RootFS extraction tools and dependencies for Ubuntu
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo "📦 Installing RootFS extraction tools and dependencies..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        sudo \
        coreutils \
        squashfs-tools \
        erofs-utils \
        e2fsprogs \
        util-linux && \   
    echo "✅ All RootFS tools and dependencies installed"

# Create fex user for FEXRootFSFetcher
RUN echo "👤 Creating fex user..." && \
    useradd -m -s /bin/bash fex && \
    usermod -aG sudo fex && \
    echo "fex ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "✅ fex user created with sudo privileges"
    
COPY --from=fex-builder /usr/local/fex /usr/local/fex
RUN echo "✅ FEX binaries copied successfully" && \
    echo "📊 FEX installation summary:" && \
    ls -la /usr/local/fex/bin/ && \
    echo "🔧 Optimizing FEX binaries..." && \
    strip /usr/local/fex/bin/* 2>/dev/null || true && \
    find /usr/local/fex -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    echo "✅ FEX binary optimization completed"

ENV PATH="/usr/local/fex/bin:$PATH"

# Setup RootFS using FEXRootFSFetcher first, manual fallback for Ubuntu
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "🚀 Starting RootFS setup process..." && \
    echo "📊 RootFS configuration:" && \
    echo "  - Target OS: ${ROOTFS_OS}" && \
    echo "  - Target Version: ${ROOTFS_VERSION}" && \
    echo "  - RootFS Type: ${ROOTFS_TYPE}" && \
    echo "  - RootFS URL: ${ROOTFS_URL}" && \
    \
    # Try FEXRootFSFetcher first
    FEXROOTFS_SUCCESS=false && \
    for attempt in 1 2 3; do \
        echo "⏳ FEXRootFSFetcher attempt $attempt/3..." && \
        if timeout 300 FEXRootFSFetcher -yx --distro-name=${ROOTFS_OS} --distro-version=${ROOTFS_VERSION} --force-ui=tty 2>/dev/null; then \
            echo "✅ FEXRootFSFetcher completed successfully (attempt $attempt)" && \
            FEXROOTFS_SUCCESS=true && \
            break; \
        else \
            echo "❌ FEXRootFSFetcher failed (attempt $attempt)" && \
            if [ $attempt -lt 3 ]; then \
                echo "⏳ Waiting 5 seconds before retry..." && \
                sleep 5; \
            fi; \
        fi; \
    done && \
    \
    # Fallback to manual setup with direct URL download
    if [ "$FEXROOTFS_SUCCESS" = "false" ]; then \
        echo "🔄 FEXRootFSFetcher failed - falling back to manual setup with direct URL download..." && \
        \
        mkdir -p /home/fex/.fex-emu/RootFS && \
        mkdir -p /tmp/fex-rootfs && \
        \
        if [ -z "$ROOTFS_URL" ]; then \
            echo "❌ ROOTFS_URL is not provided for manual download" && \
            exit 1; \
        fi && \
        \
        echo "📥 Downloading RootFS from URL: $ROOTFS_URL" && \
        ROOTFS_FILE=$(basename "$ROOTFS_URL") && \
        ROOTFS_LOCAL_PATH="/tmp/fex-rootfs/$ROOTFS_FILE" && \
        \
        # Download RootFS using curl with retry logic
        DOWNLOAD_SUCCESS=false && \
        for download_attempt in 1 2 3; do \
            echo "⏳ Download attempt $download_attempt/3..." && \
            if curl -H 'Cache-Control: no-cache' -L --connect-timeout 30 --max-time 600 \
                    --retry 3 --retry-delay 5 \
                    "$ROOTFS_URL" -o "$ROOTFS_LOCAL_PATH"; then \
                echo "✅ RootFS downloaded successfully (attempt $download_attempt)" && \
                DOWNLOAD_SUCCESS=true && \
                break; \
            else \
                echo "❌ Download failed (attempt $download_attempt)" && \
                if [ $download_attempt -lt 3 ]; then \
                    echo "⏳ Waiting 10 seconds before retry..." && \
                    sleep 10; \
                fi; \
            fi; \
        done && \
        \
        if [ "$DOWNLOAD_SUCCESS" = "false" ]; then \
            echo "❌ Failed to download RootFS after 3 attempts" && \
            exit 1; \
        fi && \
        \
        echo "✅ Found RootFS file: $ROOTFS_FILE" && \
        echo "📊 File size: $(du -h "$ROOTFS_LOCAL_PATH" | cut -f1)" && \
        \
        ROOTFS_DIRNAME="$(echo ${ROOTFS_OS} | sed 's/^./\U&/')_$(echo ${ROOTFS_VERSION} | sed 's/\./_/g')" && \
        EXTRACT_DIR="/home/fex/.fex-emu/RootFS/${ROOTFS_DIRNAME}" && \
        echo "📋 RootFS directory name: $ROOTFS_DIRNAME" && \
        \
        if [ -d "$EXTRACT_DIR" ]; then \
            echo "🗑️ Removing existing RootFS directory..." && \
            rm -rf "$EXTRACT_DIR"; \
        fi && \
        mkdir -p "$EXTRACT_DIR" && \
        \
        if echo "$ROOTFS_FILE" | grep -q '\.sqsh$\|\.squashfs$'; then \
            echo "🔧 Extracting SquashFS file using unsquashfs..." && \
            if command -v unsquashfs >/dev/null 2>&1; then \
                unsquashfs -f -d "$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" && \
                echo "✅ SquashFS extraction completed"; \
            else \
                echo "📦 unsquashfs not found. Installing squashfs-tools..." && \
                apt-get update && apt-get install -y squashfs-tools && \
                unsquashfs -f -d "$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" && \
                echo "✅ SquashFS extraction completed"; \
            fi; \
        elif echo "$ROOTFS_FILE" | grep -q '\.ero$\|\.erofs$'; then \
            echo "🔧 Extracting EROFS file..." && \
            if ! command -v dump.erofs >/dev/null 2>&1; then \
                echo "📦 Installing erofs-utils..." && \
                apt-get update && apt-get install -y erofs-utils; \
            fi && \
            dump.erofs --extract="$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" && \
            echo "✅ EROFS extraction completed"; \
        else \
            echo "❌ Unknown RootFS file format: $ROOTFS_FILE" && \
            exit 1; \
        fi && \
        \
        echo "⚙️ Writing FEX configuration..." && \
        CONFIG_PATH="/home/fex/.fex-emu/Config.json" && \
        printf '{"Config":{"RootFS":"%s"},"ThunksDB":{}}' "$ROOTFS_DIRNAME" > "$CONFIG_PATH" && \
        echo "✅ FEX configuration written to $CONFIG_PATH" && \
        \
        chown -R fex:fex /home/fex/.fex-emu && \
        \
        echo "🔍 Verifying manual RootFS installation..." && \
        if [ -d "$EXTRACT_DIR" ]; then \
            ROOTFS_CONTENT_COUNT=$(find "$EXTRACT_DIR" -type f | wc -l) && \
            echo "📊 Manual RootFS verification results:" && \
            echo "  - Directory: $EXTRACT_DIR" && \
            echo "  - Files: $ROOTFS_CONTENT_COUNT" && \
            if [ "$ROOTFS_CONTENT_COUNT" -gt 100 ]; then \
                echo "✅ Manual RootFS appears to be properly extracted"; \
            else \
                echo "⚠️ Manual RootFS may be incomplete (too few files)"; \
            fi; \
        else \
            echo "❌ Manual RootFS directory not found after extraction" && \
            exit 1; \
        fi && \
        \
        echo "🎉 Manual RootFS setup completed successfully as fallback!"; \
    else \
        echo "🎉 FEXRootFSFetcher setup completed successfully!" && \
        chown -R fex:fex /home/fex/.fex-emu; \
    fi && \
    \
    # Final verification
    echo "🔧 Final RootFS verification..." && \
    if [ -d "/home/fex/.fex-emu/RootFS" ]; then \
        ROOTFS_COUNT=$(find /home/fex/.fex-emu/RootFS -maxdepth 1 -type d | wc -l) && \
        ROOTFS_FILES=$(find /home/fex/.fex-emu/RootFS -type f | wc -l) && \
        echo "📊 Final RootFS verification:" && \
        echo "  - RootFS directories: $ROOTFS_COUNT" && \
        echo "  - RootFS files: $ROOTFS_FILES" && \
        echo "  - Method used: $( [ "$FEXROOTFS_SUCCESS" = "true" ] && echo "FEXRootFSFetcher (primary)" || echo "Manual setup (fallback)" )" && \
        if [ "$ROOTFS_FILES" -gt 0 ]; then \
            echo "✅ Final RootFS verification passed"; \
        else \
            echo "❌ Final RootFS verification failed - no files found" && \
            exit 1; \
        fi; \
    else \
        echo "❌ RootFS directory not found" && \
        exit 1; \
    fi && \
    \
    # Cleanup
    echo "🧹 Cleaning up temporary RootFS artifacts..." && \
    rm -rf /tmp/fex-rootfs && \
    find /home/fex/.fex-emu/RootFS -name "*.sqsh" -delete 2>/dev/null || true && \
    find /home/fex/.fex-emu/RootFS -name "*.ero" -delete 2>/dev/null || true && \
    echo "💾 Final RootFS size: $(du -sh /home/fex/.fex-emu/ 2>/dev/null || echo 'unknown')" && \
    echo "🎉 RootFS setup completed successfully!"

USER fex
WORKDIR /home/fex 
RUN chown -R fex:fex /home/fex/.fex-emu && \
    echo "🎉 RootFS pre-installed in image!" && \
    echo "📊 Pre-installed RootFS verification:" && \
    echo "  - RootFS directory: $(ls -d /home/fex/.fex-emu/RootFS/*/ | head -1)" && \
    echo "  - RootFS files: $(find /home/fex/.fex-emu/RootFS -type f | wc -l)" && \
    echo "  - RootFS size: $(du -sh /home/fex/.fex-emu/RootFS)" && \
    echo "  - Config file: $(ls -la /home/fex/.fex-emu/Config.json)" && \
    echo "✅ Ready for immediate x86 application execution!"

#==============================================
# Runtime Stage with Pre-installed RootFS
#==============================================
FROM ${BASE_IMAGE} AS runtime

ARG TARGETPLATFORM 
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs

# Set environment variables for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive 
ENV TZ=Asia/Seoul

RUN echo "🔍 Starting OS detection..." && \
    if [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then \
        echo "🐧 Detected: Fedora/RHEL distribution" && \
        echo "DISTRO_TYPE=fedora" > /etc/distro-info && \
        echo "🔧 Configuring DNF cache for Fedora/RHEL..." && \
        echo "keepcache=True" >> /etc/dnf/dnf.conf && \
        echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf; \
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
        echo "🐧 Detected: Debian/Ubuntu distribution" && \
        echo "DISTRO_TYPE=debian" > /etc/distro-info && \
        export DEBIAN_FRONTEND=noninteractive && \
        ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
        echo $TZ > /etc/timezone && \
        echo "🔧 Configuring APT cache for Ubuntu/Debian..." && \
        rm -f /etc/apt/apt.conf.d/docker-clean && \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
    else \
        echo "❌ Unknown distribution type" && \
        echo "DISTRO_TYPE=unknown" > /etc/distro-info; \
    fi && \
    echo "✅ OS detection completed"

# Install runtime dependencies 
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    echo "📦 Starting runtime dependencies installation..." && \
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
            libstdc++6 libc6 file && \
        echo "✅ Runtime packages installed" && \
        \
        # Cleanup for size optimization
        echo "🧹 Performing cleanup for size optimization..." && \ 
        rm -rf /var/tmp/* && \
        echo "✅ Debian/Ubuntu runtime setup completed successfully"; \
    elif [ "$DISTRO_TYPE" = "fedora" ]; then \
        echo "🔧 Setting up Fedora runtime environment..." && \
        echo "📦 Installing minimal Fedora runtime packages..." && \
        dnf install -q -y --setopt=install_weak_deps=False \
            sudo curl wget jq \
            util-linux-core libstdc++ glibc file && \
        echo "✅ Fedora runtime packages installed" && \
        echo "🧹 Cleaning up Fedora package cache..." && \ 
        rm -rf /var/tmp/* && \
        echo "✅ Fedora runtime setup completed successfully"; \
    else \
        echo "❌ Unsupported distribution type for runtime" && exit 1; \
    fi && \
    echo "🎉 Runtime dependencies installation completed!"

# Copy FEX binaries from build stage and optimize
COPY --from=fex-builder /usr/local/fex /usr/local/fex
RUN echo "✅ FEX binaries copied successfully" && \
    echo "📊 FEX installation summary:" && \
    ls -la /usr/local/fex/bin/ && \
    echo "🔧 Optimizing FEX binaries..." && \
    strip /usr/local/fex/bin/* 2>/dev/null || true && \
    find /usr/local/fex -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    echo "✅ FEX binary optimization completed"
ENV PATH="/usr/local/fex/bin:$PATH"

# Create user with OS-specific configuration
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

# Copy pre-extracted RootFS
COPY --from=rootfs-preparer /home/fex/.fex-emu/ /home/fex/.fex-emu/ 

# Set proper ownership and verify
RUN chown -R fex:fex /home/fex/.fex-emu && \
    echo "🎉 RootFS pre-installed in image!" && \
    echo "📊 Pre-installed RootFS verification:" && \
    echo "  - RootFS directory: $(ls -d /home/fex/.fex-emu/RootFS/*/ | head -1)" && \
    echo "  - RootFS files: $(find /home/fex/.fex-emu/RootFS -type f | wc -l)" && \
    echo "  - RootFS size: $(du -sh /home/fex/.fex-emu/RootFS)" && \
    echo "  - Config file: $(ls -la /home/fex/.fex-emu/Config.json)" && \
    echo "✅ Ready for immediate x86 application execution!"

# Switch to fex user
USER fex
WORKDIR /home/fex 
CMD ["/bin/bash", "-c", "echo '🚀 FEX-Emu ready!' && echo '🔧 Built with Ubuntu Linux for maximum compatibility!' && echo '💡 Try: FEXBash' && /bin/bash"]