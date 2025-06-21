ARG FEX_VERSION
ARG BASE_IMAGE=ubuntu:24.04

#==============================================
# Build Stage - Ubuntu LTS Base
#==============================================
FROM ubuntu:24.04 AS fex-builder

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

LABEL org.opencontainers.image.version="${FEX_VERSION}"
LABEL fex.emulator.version="${FEX_VERSION}"
LABEL build.platform="${TARGETPLATFORM}"
LABEL build.date="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Configure Ubuntu environment for FEX build
RUN echo "🔍 Setting up Ubuntu 24.04 LTS build environment..." && \
    echo "🏗️ Configuring Ubuntu for maximum compatibility..." && \
    export DEBIAN_FRONTEND=noninteractive && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    echo "⚙️ Configuring APT cache for optimal build performance..." && \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo "✅ Ubuntu environment configuration completed"

# Install build dependencies with Ubuntu packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "📦 Installing Ubuntu build packages..." && \
    echo "🔍 Using Ubuntu 24.04 LTS packages for maximum stability..." && \
    apt-get update -qq >/dev/null 2>&1 && \
    echo "📦 Installing development packages..." && \
    apt-get install -qq -y --no-install-recommends  \
        git cmake ninja-build pkg-config ccache \
        nasm python3-dev python3-clang python3-setuptools \
        libcap-dev libglfw3-dev libepoxy-dev libsdl2-dev \
        linux-headers-generic curl wget \
        software-properties-common openssl libssl-dev \
        binutils binutils-aarch64-linux-gnu \
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
        qtbase5-dev qtdeclarative5-dev && \
        >/dev/null 2>&1 && \
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
        echo "🎯 Installing LLVM ${LLVM_VERSION} from Ubuntu repository..." && \
        apt-get install -qq -y \
            clang-${LLVM_VERSION} \
            lld-${LLVM_VERSION} \
            llvm-${LLVM_VERSION} \
            llvm-${LLVM_VERSION}-dev \
            llvm-${LLVM_VERSION}-tools \
            libedit-dev libffi-dev >/dev/null 2>&1 && \
        echo "✅ LLVM ${LLVM_VERSION} installed from Ubuntu repository"; \
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
    # Ubuntu cleanup
    echo "🧹 Cleaning up Ubuntu packages..." && \
    update-alternatives --install /usr/bin/lld lld /usr/bin/lld-${LLVM_VERSION} 100 && \ 
    rm -rf /var/tmp/* && \
    echo "✅ Ubuntu build environment setup completed successfully"

# ccache setup for Ubuntu
RUN echo "📦 Setting up ccache for Ubuntu build..." && \
    echo "🔍 Ubuntu system information:" && \
    echo "  - GLIBC version: $(ldd --version | head -1)" && \
    echo "  - Ubuntu version: $(lsb_release -rs 2>/dev/null || echo '24.04')" && \
    echo "  - Architecture: $(uname -m)" && \
    echo "  - Target RootFS: ${ROOTFS_OS}-${ROOTFS_VERSION}" && \
    \
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && command -v ccache >/dev/null 2>&1; then \
        echo "🔄 Using Ubuntu ccache..." && \
        echo "CCACHE_SOURCE=system" > /tmp/ccache-info && \
        echo "✅ Ubuntu ccache found and configured"; \
    else \
        echo "ℹ️ ccache disabled or not available" && \
        echo "CCACHE_SOURCE=disabled" > /tmp/ccache-info; \
    fi && \
    \
    echo "✅ Ubuntu ccache setup completed"

ENV PATH="/usr/local/bin/:$PATH"

# Copy FEX source from build context and build with Ubuntu  
COPY --from=fex-sources / /tmp/fex-source  
RUN --mount=type=cache,target=/tmp/.ccache \
    echo "🏗️ Starting FEX build process on Ubuntu..." && \
    echo "🏷️ Building FEX version: ${FEX_VERSION}" && \
    echo "🎯 Target platform: ${TARGETPLATFORM}" && \
    echo "📊 Ubuntu build configuration:" && \
    echo "  - Base: Ubuntu 24.04 LTS" && \
    echo "  - Target RootFS: ${ROOTFS_OS}-${ROOTFS_VERSION}" && \
    echo "  - Build type: Release with LTO" && \
    cd /tmp/fex-source && \
    \
    # Check ccache setup
    . /tmp/ccache-info && \
    echo "📊 Ubuntu build environment summary:" && \
    echo "  - ENABLE_CCACHE: ${ENABLE_CCACHE}" && \
    echo "  - CCACHE_SOURCE: ${CCACHE_SOURCE}" && \
    echo "  - LLVM_VERSION: ${LLVM_VERSION}" && \
    echo "  - CCACHE_BINARY: $(which ccache 2>/dev/null || echo 'not found')" && \
    echo "  - Build directory: $(pwd)" && \
    \
    mkdir -p Build && cd Build && \
    \
    # Ubuntu compiler detection
    echo "🔍 Detecting Ubuntu compilers..." && \
    if command -v clang-${LLVM_VERSION} >/dev/null 2>&1; then \
        CC_COMPILER=clang-${LLVM_VERSION} && \
        CXX_COMPILER=clang++-${LLVM_VERSION} && \
        echo "🎯 Found version-specific Ubuntu compilers"; \
    else \
        CC_COMPILER=clang && \
        CXX_COMPILER=clang++ && \
        echo "🔄 Using default Ubuntu compiler names"; \
    fi && \
    echo "✅ Ubuntu compilers configured: $CC_COMPILER / $CXX_COMPILER" && \
    \
    # Ubuntu AR tools detection
    echo "🔍 Detecting Ubuntu archiver tools..." && \
    if command -v llvm-ar-${LLVM_VERSION} >/dev/null 2>&1; then \
        AR_TOOL=$(which llvm-ar-${LLVM_VERSION}) && \
        RANLIB_TOOL=$(which llvm-ranlib-${LLVM_VERSION}) && \
        echo "🎯 Found LLVM-specific Ubuntu tools"; \
    else \
        AR_TOOL=$(which ar) && \
        RANLIB_TOOL=$(which ranlib) && \
        echo "🔄 Using Ubuntu default tools"; \
    fi && \
    echo "✅ Ubuntu archiver tools configured: $AR_TOOL" && \
    \
    # Enhanced ccache configuration for Ubuntu
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && [ "${CCACHE_SOURCE}" != "disabled" ]; then \
        echo "🚀 Configuring ccache acceleration for Ubuntu..." && \
        export CCACHE_BASEDIR=/tmp/fex-source && \
        export CCACHE_DIR=/tmp/.ccache && \
        export CCACHE_MAXSIZE=2G && \
        export CCACHE_SLOPPINESS=pch_defines,time_macros && \
        export CC="ccache $CC_COMPILER" && \
        export CXX="ccache $CXX_COMPILER" && \
        ccache --zero-stats && \        
        CCACHE_CMAKE_ARGS="-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache" && \
        echo "✅ ccache enabled with Ubuntu optimizations"; \
    else \
        CCACHE_CMAKE_ARGS="" && \
        echo "ℹ️ ccache disabled for this Ubuntu build"; \
    fi && \
    \
    # Ubuntu-optimized CMake configuration
    echo "⚙️ Running CMake configuration for Ubuntu..." && \
    echo "🎯 Optimizing for Ubuntu LTS stability and compatibility..." && \
    cmake \
        -DCMAKE_INSTALL_PREFIX=/usr/local/fex \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_LINKER=lld \
        -DENABLE_LTO=True \
        -DBUILD_TESTS=False \
        -DENABLE_ASSERTIONS=False \
        -DCMAKE_C_COMPILER="$CC_COMPILER" \
        -DCMAKE_CXX_COMPILER="$CXX_COMPILER" \
        $CCACHE_CMAKE_ARGS \
        -DCMAKE_AR="$AR_TOOL" \
        -DCMAKE_RANLIB="$RANLIB_TOOL" \
        -DCMAKE_C_COMPILER_AR="$AR_TOOL" \
        -DCMAKE_CXX_COMPILER_AR="$AR_TOOL" \ 
        -G Ninja .. && \
    echo "✅ CMake configuration completed for Ubuntu" && \
    \
    echo "🔨 Starting compilation on Ubuntu..." && \
    echo "🚀 Building FEX with $(nproc) CPU cores..." && \
    ninja -j$(($(nproc) - 1)) && \
    echo "✅ Compilation completed successfully on Ubuntu" && \
    \
    echo "📦 Installing FEX binaries..." && \
    ninja install && \
    echo "✅ FEX installation completed" && \
    \
    # Show ccache statistics if enabled
    if [ "${ENABLE_CCACHE:-false}" = "true" ] && [ "${CCACHE_SOURCE}" != "disabled" ]; then \
        echo "📊 Ubuntu ccache Statistics:" && \
        ccache --show-stats; \
    fi && \
    \
    echo "🧹 Cleaning up Ubuntu build artifacts..." && \
    rm -rf /tmp/fex-source /tmp/ccache-info && \
    echo "🎉 FEX build completed successfully on Ubuntu!"

#==============================================
# 🔧 UNIFIED Runtime + RootFS Stage (Combined)
#==============================================
FROM ubuntu:24.04 AS runtime

ARG FEX_VERSION
ARG TARGETPLATFORM 
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs
ARG ROOTFS_URL=""

# Ubuntu runtime metadata
LABEL org.opencontainers.image.title="FEXBash Ubuntu-Unified ARM64 Container"
LABEL org.opencontainers.image.description="Unified RootFS+Runtime: High-performance x86/x86_64 emulation on ARM64"
LABEL org.opencontainers.image.version="${FEX_VERSION}"
LABEL fex.version="${FEX_VERSION}"
LABEL fex.rootfs.distribution="${ROOTFS_OS}-${ROOTFS_VERSION}"
LABEL build.platform="${TARGETPLATFORM}"
LABEL base.image="ubuntu:24.04"
LABEL build.type="unified-runtime-rootfs"

# Set environment variables for Ubuntu runtime
ENV DEBIAN_FRONTEND=noninteractive 
ENV TZ=Asia/Seoul
ENV FEX_VERSION=${FEX_VERSION}
ENV ROOTFS_INFO="${ROOTFS_OS}-${ROOTFS_VERSION}"

# Configure Ubuntu runtime environment
RUN echo "🏗️ Setting up UNIFIED Ubuntu 24.04 LTS runtime environment..." && \
    echo "🔧 COMBINED Runtime + RootFS setup in single stage!" && \
    echo "📊 Ubuntu unified configuration:" && \
    echo "  - Base: Ubuntu 24.04 LTS" && \
    echo "  - Target: High-performance x86 emulation runtime" && \
    echo "  - Features: Native glibc + LTS stability + Unified RootFS" && \
    export DEBIAN_FRONTEND=noninteractive && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    echo "⚙️ Configuring APT cache for Ubuntu runtime..." && \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo "✅ Ubuntu unified environment configured"

# Install Ubuntu runtime AND RootFS extraction dependencies (COMBINED)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "📦 Installing UNIFIED Ubuntu runtime + RootFS packages..." && \
    echo "🔍 Single-stage package installation for optimal compatibility..." && \
    echo "📊 Runtime build parameters:" && \
    echo "  - ROOTFS_OS: ${ROOTFS_OS}" && \
    echo "  - ROOTFS_VERSION: ${ROOTFS_VERSION}" && \
    echo "  - ROOTFS_TYPE: ${ROOTFS_TYPE}" && \
    apt-get update -qq >/dev/null 2>&1 && \
    echo "📦 Installing unified runtime packages..." && \
    apt-get install -qq -y --no-install-recommends  \
        sudo curl wget jq \
        libc6 \
        libstdc++6 \
        libssl3 \
        libzstd1 \
        squashfs-tools \
        erofs-utils \
        e2fsprogs \
        util-linux \
        coreutils \
        binfmt-support \
        apt-utils >/dev/null 2>&1 && \
    echo "✅ Unified Ubuntu packages installed successfully" && \
    echo "📊 Unified package summary:" && \
    echo "  - Runtime libraries: libstdc++6, libc6" && \
    echo "  - RootFS tools: squashfs-tools, erofs-utils" && \
    echo "  - Utilities: sudo, curl, wget, jq" && \
    echo "  - Architecture: ARM64 with x86 emulation support" && \
    \
    echo "🔒 Updating CA certificates for maximum compatibility..." && \
    apt-get install -y apt-utils ca-certificates && \
    update-ca-certificates && \ 
    echo "✅ CA certificates updated" && \
    # Ubuntu cleanup for size optimization
    echo "🧹 Performing Ubuntu cleanup for size optimization..." && \ 
    rm -rf /var/tmp/* && \
    echo "✅ Unified Ubuntu setup completed successfully" && \
    echo "🎉 Ubuntu unified environment ready!"

RUN echo "👤 Creating fex user for unified Ubuntu runtime..." && \
    echo "🔧 Configuring Ubuntu user management..." && \
    useradd -m -s /bin/bash fex && \
    usermod -aG sudo fex && \
    echo "fex ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/fex && \
    mkdir -p /home/fex/.fex-emu/RootFS && \    
    chown -R fex:fex /home/fex && \            
    echo "✅ Ubuntu user configuration completed successfully" && \
    echo "🎯 User 'fex' ready for unified x86 emulation!"

# Copy optimized FEX binaries from Ubuntu builder
COPY --from=fex-builder /usr/local/fex /usr/local/fex
RUN echo "📦 Copying FEX binaries to unified Ubuntu runtime..." && \
    echo "✅ FEX binaries copied to unified Ubuntu runtime successfully" && \
    echo "📊 FEX installation summary:" && \
    ls -la /usr/local/fex/bin/ && \
    echo "🚀 Ubuntu-optimized FEX ready for unified setup!"

ENV PATH="/usr/local/fex/bin:$PATH"

# Switch to fex user for RootFS setup
USER fex
WORKDIR /home/fex

# 🔧 UNIFIED RootFS Setup (In same stage as runtime!)
RUN echo "🚀 Starting UNIFIED RootFS setup process..." && \
    echo "🎯 CRITICAL: Setting up RootFS in SAME stage as runtime!" && \
    echo "📊 Unified RootFS configuration:" && \
    echo "  - Target OS: ${ROOTFS_OS}" && \
    echo "  - Target Version: ${ROOTFS_VERSION}" && \
    echo "  - RootFS Type: ${ROOTFS_TYPE}" && \
    echo "  - RootFS URL: ${ROOTFS_URL}" && \
    echo "  - Strategy: FEXRootFSFetcher + Manual fallback (UNIFIED)" && \
    \
    # Setup FEX directories first
    mkdir -p /home/fex/.fex-emu/RootFS && \
    # chown -R fex:fex /home/fex/.fex-emu && \
    \
    # Try FEXRootFSFetcher first (as fex user in unified environment)
    FEXROOTFS_SUCCESS=false && \
    echo "🎯 Attempting FEXRootFSFetcher in UNIFIED environment..." && \
    for attempt in 1 2 3; do \
        echo "⏳ FEXRootFSFetcher unified attempt $attempt/3..." && \
        if FEXRootFSFetcher -yx --distro-name=${ROOTFS_OS} --distro-version=${ROOTFS_VERSION} --force-ui=tty 2>/dev/null; then \
            echo "✅ FEXRootFSFetcher completed successfully in unified environment (attempt $attempt)" && \
            FEXROOTFS_SUCCESS=true && \
            break; \
        else \
            echo "❌ FEXRootFSFetcher failed in unified environment (attempt $attempt)" && \
            if [ $attempt -lt 3 ]; then \
                echo "⏳ Waiting 5 seconds before retry..." && \
                sleep 5; \
            fi; \
        fi; \
    done && \
    \
    # Fallback to manual setup if needed
    if [ "$FEXROOTFS_SUCCESS" = "false" ]; then \
        echo "🔄 FEXRootFSFetcher failed - activating unified manual setup fallback..." && \
        echo "📥 Switching to direct URL download method in unified environment..." && \
        \ 
        mkdir -p /tmp/fex-rootfs && \
        \
        if [ -z "$ROOTFS_URL" ]; then \
            echo "❌ ROOTFS_URL is not provided for manual download" && \
            exit 1; \
        fi && \
        \
        echo "📥 Downloading RootFS from official URL: $ROOTFS_URL" && \
        ROOTFS_FILE=$(basename "$ROOTFS_URL") && \
        ROOTFS_LOCAL_PATH="/tmp/fex-rootfs/$ROOTFS_FILE" && \
        \
        # Download RootFS using curl with retry logic
        DOWNLOAD_SUCCESS=false && \
        echo "🔍 Starting unified download with retry mechanism..." && \
        for download_attempt in 1 2 3; do \
            echo "⏳ Unified download attempt $download_attempt/3..." && \
            if curl -S -s -o -k -H 'Cache-Control: no-cache' -L --connect-timeout 30 --max-time 600 \
                    --retry 3 --retry-delay 5 \
                    "$ROOTFS_URL" -o "$ROOTFS_LOCAL_PATH"; then \
                echo "✅ RootFS downloaded successfully in unified environment (attempt $download_attempt)" && \
                DOWNLOAD_SUCCESS=true && \
                break; \
            else \
                echo "❌ Unified download failed (attempt $download_attempt)" && \
                if [ $download_attempt -lt 3 ]; then \
                    echo "⏳ Waiting 10 seconds before retry..." && \
                    sleep 10; \
                fi; \
            fi; \
        done && \
        \
        if [ "$DOWNLOAD_SUCCESS" = "false" ]; then \
            echo "❌ Failed to download RootFS after 3 attempts in unified environment" && \
            exit 1; \
        fi && \
        \
        echo "✅ Found RootFS file in unified setup: $ROOTFS_FILE" && \
        echo "📊 File size: $(du -h "$ROOTFS_LOCAL_PATH" | cut -f1)" && \
        \
        ROOTFS_DIRNAME="$(echo ${ROOTFS_OS} | sed 's/^./\U&/')_$(echo ${ROOTFS_VERSION} | sed 's/\./_/g')" && \
        EXTRACT_DIR="/home/fex/.fex-emu/RootFS/${ROOTFS_DIRNAME}" && \
        echo "📁 Unified RootFS directory name: $ROOTFS_DIRNAME" && \
        \
        if [ -d "$EXTRACT_DIR" ]; then \
            echo "🗑️ Removing existing RootFS directory in unified setup..." && \
            rm -rf "$EXTRACT_DIR"; \
        fi && \
        mkdir -p "$EXTRACT_DIR" && \
        echo "📁 Created unified extraction directory: $EXTRACT_DIR" && \
        \
        if echo "$ROOTFS_FILE" | grep -q '\.sqsh$\|\.squashfs$'; then \
            echo "🔧 Extracting SquashFS file using unsquashfs in unified environment..." && \
            unsquashfs -f -d "$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" >/dev/null 2>&1 && \
            echo "✅ SquashFS extraction completed successfully in unified environment"; \
        elif echo "$ROOTFS_FILE" | grep -q '\.ero$\|\.erofs$'; then \
            echo "🔧 Extracting EROFS file in unified environment..." && \
            dump.erofs --extract="$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" >/dev/null 2>&1 && \
            echo "✅ EROFS extraction completed successfully in unified environment"; \
        else \
            echo "❌ Unknown RootFS file format in unified setup: $ROOTFS_FILE" && \
            exit 1; \
        fi && \
        \
        echo "⚙️ Writing FEX configuration in unified environment..." && \
        CONFIG_PATH="/home/fex/.fex-emu/Config.json" && \
        printf '{"Config":{"RootFS":"%s"},"ThunksDB":{}}' "$ROOTFS_DIRNAME" > "$CONFIG_PATH" && \
        echo "✅ FEX configuration written to $CONFIG_PATH in unified environment" && \
        \
        chown -R fex:fex /home/fex/.fex-emu && \
        \
        echo "🔍 Verifying unified manual RootFS installation..." && \
        if [ -d "$EXTRACT_DIR" ]; then \
            ROOTFS_CONTENT_COUNT=$(find "$EXTRACT_DIR" -type f | wc -l) && \
            echo "📊 Unified manual RootFS verification results:" && \
            echo "  - Directory: $EXTRACT_DIR" && \
            echo "  - Files: $ROOTFS_CONTENT_COUNT" && \
            if [ "$ROOTFS_CONTENT_COUNT" -gt 100 ]; then \
                echo "✅ Unified manual RootFS appears to be properly extracted"; \
            else \
                echo "⚠️ Unified manual RootFS may be incomplete (too few files)"; \
            fi; \
        else \
            echo "❌ Unified manual RootFS directory not found after extraction" && \
            exit 1; \
        fi && \
        \
        echo "🎉 Unified manual RootFS setup completed successfully as fallback!"; \
    else \
        echo "🎉 FEXRootFSFetcher unified setup completed successfully!" && \
        chown -R fex:fex /home/fex/.fex-emu; \
    fi && \
    \
    # Final unified verification
    echo "🔍 Final unified RootFS verification and summary..." && \
    if [ -d "/home/fex/.fex-emu/RootFS" ]; then \
        ROOTFS_COUNT=$(find /home/fex/.fex-emu/RootFS -maxdepth 1 -type d | wc -l) && \
        ROOTFS_FILES=$(find /home/fex/.fex-emu/RootFS -type f | wc -l) && \
        echo "🎉 Unified RootFS setup completed successfully!" && \ 
        echo "📊 Final unified RootFS verification summary:" && \
        echo "  - RootFS directories: $ROOTFS_COUNT" && \
        echo "  - RootFS files: $ROOTFS_FILES" && \
        echo "  - Method used: $( [ "$FEXROOTFS_SUCCESS" = "true" ] && echo "FEXRootFSFetcher (unified primary)" || echo "Manual setup (unified fallback)" )" && \
        echo "  - RootFS size: $(du -sh /home/fex/.fex-emu/RootFS)" && \
        echo "  - Config file: $(ls -la /home/fex/.fex-emu/Config.json)" && \
        if [ "$ROOTFS_FILES" -gt 0 ]; then \
            echo "✅ Final unified RootFS verification passed successfully"; \
        else \
            echo "❌ Final unified RootFS verification failed - no files found" && \
            exit 1; \
        fi; \
    else \
        echo "❌ Unified RootFS directory not found" && \
        exit 1; \
    fi && \
    \
    # Cleanup
    echo "🧹 Cleaning up temporary unified RootFS artifacts..." && \
    rm -rf /tmp/fex-rootfs && \
    find /home/fex/.fex-emu/RootFS -name "*.sqsh" -delete 2>/dev/null || true && \
    find /home/fex/.fex-emu/RootFS -name "*.ero" -delete 2>/dev/null || true && \
    echo "✅ Unified cleanup completed successfully" && \
    echo "🚀 Ready for immediate x86 application execution in unified environment!" && \
    echo "🎯 UNIFIED RootFS + Runtime setup complete!"

# Set proper ownership and perform final Ubuntu optimization
RUN echo "📦 Final unified ownership and optimization..." && \
    sudo chown -R fex:fex /home/fex/.fex-emu && \
    sudo chmod 0640 /etc/shadow && \
    echo "✅ Unified ownership configured for Ubuntu" && \
    echo "🎉 Unified RootFS + Runtime integrated in Ubuntu image!" && \
    echo "📊 Final unified verification:" && \
    echo "  - RootFS directory: $(ls -d /home/fex/.fex-emu/RootFS/*/ | head -1)" && \
    echo "  - RootFS files: $(find /home/fex/.fex-emu/RootFS -type f | wc -l)" && \
    echo "  - RootFS size: $(du -sh /home/fex/.fex-emu/RootFS)" && \
    echo "  - Config file: $(ls -la /home/fex/.fex-emu/Config.json)" && \
    echo "🎯 Ubuntu + FEX + RootFS UNIFIED integration complete!" && \
    echo "🚀 Ready for immediate x86 application execution on unified Ubuntu!" && \
    echo "🏗️ Ultimate stability achieved: Ubuntu LTS + UNIFIED RootFS + FEX emulation!"

# Test FEX binaries in unified environment
RUN echo "🧪 Testing FEX binaries in UNIFIED environment..." && \
    echo "📋 Testing FEXBash execution in unified setup..." && \
    if /usr/local/fex/bin/FEXBash -c 'echo "Unified environment test: SUCCESS"' ; then \
        echo "✅ FEXBash working in UNIFIED environment"; \
    else \
        echo "❌ FEXBash failing in UNIFIED environment"; \
        echo "📝 This indicates unified environment issues"; \
        exit 1; \
    fi && \
    echo "✅ All FEX unified tests completed successfully"

# Ubuntu-optimized startup command with unified information
CMD ["/bin/bash", "-c", "echo '🎉 FEX-Emu UNIFIED on Ubuntu ready!' && echo '🏗️ Base: Ubuntu 24.04 LTS (UNIFIED Runtime+RootFS)' && echo '🏷️ FEX Version: ${FEX_VERSION}' && echo '🐧 RootFS: ${ROOTFS_INFO}' && echo '🔧 Ubuntu LTS UNIFIED for maximum compatibility!' && echo '📊 Native glibc: Perfect x86 emulation support' && echo '🚀 Performance: Near-native ARM64 execution with unified x86 emulation' && echo '💡 Try: FEXBash' && echo '🎯 Ready for x86 application execution in UNIFIED environment!' && /bin/bash"]
