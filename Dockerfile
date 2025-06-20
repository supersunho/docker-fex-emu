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
        curl wget \
        software-properties-common openssl libssl-dev \
        squashfs-tools squashfuse erofs-utils \
        qtbase5-dev qttools5-dev qtdeclarative5-dev \
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
        -DBUILD_THUNKS=FALSE \
        -DBUILD_TOOLS=FALSE \
        -DCMAKE_C_COMPILER="$CC_COMPILER" \
        -DCMAKE_CXX_COMPILER="$CXX_COMPILER" \
        $CCACHE_CMAKE_ARGS \
        -DCMAKE_AR="$AR_TOOL" \
        -DCMAKE_RANLIB="$RANLIB_TOOL" \
        -DCMAKE_C_COMPILER_AR="$AR_TOOL" \
        -DCMAKE_CXX_COMPILER_AR="$AR_TOOL" \
        -DCMAKE_EXE_LINKER_FLAGS="-static-libgcc -static-libstdc++" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++" \
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
# RootFS Preparation Stage (Ubuntu-based for compatibility)
#==============================================
FROM ubuntu:24.04 AS rootfs-preparer

ARG FEX_VERSION
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs
ARG ROOTFS_URL=""

LABEL fex.version="${FEX_VERSION}"
LABEL fex.rootfs.os="${ROOTFS_OS}"
LABEL fex.rootfs.version="${ROOTFS_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive 

# Install RootFS extraction tools and dependencies for Ubuntu
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo "📦 Installing RootFS extraction tools and dependencies..." && \
    echo "🐧 Using Ubuntu for RootFS preparation (maximum compatibility)" && \
    echo "🔧 Setting up extraction toolchain..." && \
    apt-get update -qq >/dev/null 2>&1 && \
    apt-get install -qq -y --no-install-recommends \
        curl \
        sudo \
        coreutils \
        squashfs-tools \
        erofs-utils \
        e2fsprogs \
        util-linux >/dev/null 2>&1 && \   
    echo "✅ All RootFS tools and dependencies installed successfully" && \
    echo "🎯 Ubuntu RootFS preparer ready!" && \
    echo "🔒 Updating CA certificates for maximum compatibility..." && \
    apt-get update -qq >/dev/null 2>&1 && \
    apt-get install -y apt-utils ca-certificates && \
    update-ca-certificates && \
    echo "✅ CA certificates updated"

# Create fex user for FEXRootFSFetcher
RUN echo "👤 Creating fex user for RootFS operations..." && \
    useradd -m -s /bin/bash fex && \
    usermod -aG sudo fex && \
    echo "fex ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "✅ fex user created with sudo privileges" && \
    echo "🎯 Ready for RootFS setup operations"
    
# Copy FEX binaries from Ubuntu builder
COPY --from=fex-builder /usr/local/fex /usr/local/fex
RUN echo "📦 Copying FEX binaries from Ubuntu builder..." && \
    echo "✅ FEX binaries copied successfully" && \
    echo "📊 FEX installation summary:" && \
    ls -la /usr/local/fex/bin/ && \
    echo "🔧 Optimizing FEX binaries for production..." && \
    strip /usr/local/fex/bin/* 2>/dev/null || true && \
    find /usr/local/fex -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    echo "✅ FEX binary optimization completed" && \
    echo "🎉 Ubuntu-built FEX ready for RootFS operations!"

ENV PATH="/usr/local/fex/bin:$PATH"

# Switch to fex user for RootFS setup
USER fex
WORKDIR /home/fex

# Setup RootFS using FEXRootFSFetcher with manual fallback
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "🚀 Starting RootFS setup process..." && \
    echo "📊 RootFS configuration summary:" && \
    echo "  - Target OS: ${ROOTFS_OS}" && \
    echo "  - Target Version: ${ROOTFS_VERSION}" && \
    echo "  - RootFS Type: ${ROOTFS_TYPE}" && \
    echo "  - RootFS URL: ${ROOTFS_URL}" && \
    echo "  - Strategy: FEXRootFSFetcher + Manual fallback" && \
    \
    # Try FEXRootFSFetcher first
    FEXROOTFS_SUCCESS=false && \
    mkdir -p /home/fex/.fex-emu/RootFS && \
    echo "🎯 Attempting FEXRootFSFetcher (primary method)..." && \
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
        echo "🔄 FEXRootFSFetcher failed - activating manual setup fallback..." && \
        echo "📥 Switching to direct URL download method..." && \
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
        echo "🔍 Starting download with retry mechanism..." && \
        for download_attempt in 1 2 3; do \
            echo "⏳ Download attempt $download_attempt/3..." && \
            if curl -S -s -o -k -H 'Cache-Control: no-cache' -L --connect-timeout 30 --max-time 600 \
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
        echo "📁 RootFS directory name: $ROOTFS_DIRNAME" && \
        \
        if [ -d "$EXTRACT_DIR" ]; then \
            echo "🗑️ Removing existing RootFS directory..." && \
            rm -rf "$EXTRACT_DIR"; \
        fi && \
        mkdir -p "$EXTRACT_DIR" && \
        echo "📁 Created extraction directory: $EXTRACT_DIR" && \
        \
        if echo "$ROOTFS_FILE" | grep -q '\.sqsh$\|\.squashfs$'; then \
            echo "🔧 Extracting SquashFS file using unsquashfs..." && \
            if command -v unsquashfs >/dev/null 2>&1; then \
                unsquashfs -f -d "$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" >/dev/null 2>&1 && \
                echo "✅ SquashFS extraction completed successfully"; \
            else \
                echo "📦 unsquashfs not found. Installing squashfs-tools..." && \
                apt-get update && apt-get install -y squashfs-tools && \
                unsquashfs -f -d "$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" && \
                echo "✅ SquashFS extraction completed with tools installation"; \
            fi; \
        elif echo "$ROOTFS_FILE" | grep -q '\.ero$\|\.erofs$'; then \
            echo "🔧 Extracting EROFS file..." && \
            if ! command -v dump.erofs >/dev/null 2>&1; then \
                echo "📦 Installing erofs-utils..." && \
                apt-get update && apt-get install -y erofs-utils; \
            fi && \
            dump.erofs --extract="$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" >/dev/null 2>&1 && \
            echo "✅ EROFS extraction completed successfully"; \
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
    echo "🔍 Final RootFS verification and summary..." && \
    if [ -d "/home/fex/.fex-emu/RootFS" ]; then \
        ROOTFS_COUNT=$(find /home/fex/.fex-emu/RootFS -maxdepth 1 -type d | wc -l) && \
        ROOTFS_FILES=$(find /home/fex/.fex-emu/RootFS -type f | wc -l) && \
        echo "🎉 RootFS setup completed successfully!" && \ 
        echo "📊 Final RootFS verification summary:" && \
        echo "  - RootFS directories: $ROOTFS_COUNT" && \
        echo "  - RootFS files: $ROOTFS_FILES" && \
        echo "  - Method used: $( [ "$FEXROOTFS_SUCCESS" = "true" ] && echo "FEXRootFSFetcher (primary)" || echo "Manual setup (fallback)" )" && \
        echo "  - RootFS size: $(du -sh /home/fex/.fex-emu/RootFS)" && \
        echo "  - Config file: $(ls -la /home/fex/.fex-emu/Config.json)" && \
        if [ "$ROOTFS_FILES" -gt 0 ]; then \
            echo "✅ Final RootFS verification passed successfully"; \
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
    echo "✅ Cleanup completed successfully" && \
    echo "🚀 Ready for immediate x86 application execution!" && \
    echo "🎯 RootFS preparation stage complete!"

#==============================================
# Runtime Stage with Ubuntu LTS Base
#==============================================
FROM ubuntu:24.04 AS runtime

ARG FEX_VERSION
ARG TARGETPLATFORM 
ARG ROOTFS_OS=ubuntu
ARG ROOTFS_VERSION="24.04"
ARG ROOTFS_TYPE=squashfs

# Ubuntu runtime metadata
LABEL org.opencontainers.image.title="FEXBash Ubuntu-Optimized ARM64 Container"
LABEL org.opencontainers.image.description="High-performance x86/x86_64 emulation on ARM64 with Ubuntu LTS base"
LABEL org.opencontainers.image.version="${FEX_VERSION}"
LABEL fex.version="${FEX_VERSION}"
LABEL fex.rootfs.distribution="${ROOTFS_OS}-${ROOTFS_VERSION}"
LABEL build.platform="${TARGETPLATFORM}"
LABEL base.image="ubuntu:24.04"

# Set environment variables for Ubuntu runtime
ENV DEBIAN_FRONTEND=noninteractive 
ENV TZ=Asia/Seoul
ENV FEX_VERSION=${FEX_VERSION}
ENV ROOTFS_INFO="${ROOTFS_OS}-${ROOTFS_VERSION}"

# Configure Ubuntu runtime environment
RUN echo "🏗️ Setting up Ubuntu 24.04 LTS runtime environment..." && \
    echo "📊 Ubuntu runtime configuration:" && \
    echo "  - Base: Ubuntu 24.04 LTS" && \
    echo "  - Target: High-performance x86 emulation runtime" && \
    echo "  - Features: Native glibc + LTS stability" && \
    export DEBIAN_FRONTEND=noninteractive && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    echo "⚙️ Configuring APT cache for Ubuntu runtime..." && \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo "✅ Ubuntu runtime environment configured"

# Install minimal Ubuntu runtime dependencies 
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "📦 Installing minimal Ubuntu runtime packages..." && \
    echo "🔍 Selecting only essential runtime components..." && \
    echo "📊 Runtime build parameters:" && \
    echo "  - ROOTFS_OS: ${ROOTFS_OS}" && \
    echo "  - ROOTFS_VERSION: ${ROOTFS_VERSION}" && \
    echo "  - ROOTFS_TYPE: ${ROOTFS_TYPE}" && \
    apt-get update -qq >/dev/null 2>&1 && \
    echo "📦 Installing minimal runtime packages..." && \
    apt-get install -qq -y --no-install-recommends  \
        sudo curl wget jq \
        libstdc++6 libc6 file >/dev/null 2>&1 && \
    echo "✅ Ubuntu runtime packages installed successfully" && \
    echo "📊 Runtime package summary:" && \
    echo "  - System libraries: libstdc++6, libc6" && \
    echo "  - Utilities: sudo, curl, wget, jq, file" && \
    echo "  - Architecture: ARM64 with x86 emulation support" && \
    \
    # Ubuntu cleanup for size optimization
    echo "🧹 Performing Ubuntu cleanup for size optimization..." && \ 
    rm -rf /var/tmp/* && \
    echo "✅ Ubuntu runtime setup completed successfully" && \
    echo "🎉 Ubuntu runtime environment ready!"

# Create Ubuntu user with proper configuration
RUN echo "👤 Creating fex user for Ubuntu runtime..." && \
    echo "🔧 Configuring Ubuntu user management..." && \
    useradd -m -s /bin/bash fex && \
    usermod -aG sudo fex && \
    echo "fex ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/fex && \
    echo "✅ Ubuntu user configuration completed successfully" && \
    echo "🎯 User 'fex' ready for x86 emulation!"

# Copy optimized FEX binaries from Ubuntu builder
COPY --from=fex-builder /usr/local/fex /usr/local/fex
RUN echo "📦 Copying FEX binaries to Ubuntu runtime..." && \
    echo "✅ FEX binaries copied to Ubuntu runtime successfully" && \
    echo "📊 FEX installation summary:" && \
    ls -la /usr/local/fex/bin/ && \
    echo "🔧 Final FEX binary optimization for Ubuntu..." && \
    strip /usr/local/fex/bin/* 2>/dev/null || true && \
    find /usr/local/fex -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    echo "✅ FEX binary optimization completed for Ubuntu runtime" && \
    echo "🚀 Ubuntu-optimized FEX ready!"

ENV PATH="/usr/local/fex/bin:$PATH"

# Copy pre-extracted RootFS from Ubuntu preparer
COPY --from=rootfs-preparer /home/fex/.fex-emu/ /home/fex/.fex-emu/ 

# Set proper ownership and perform final Ubuntu optimization
RUN echo "📦 Installing pre-extracted RootFS in Ubuntu runtime..." && \
    chown -R fex:fex /home/fex/.fex-emu && \
    chmod 0640 /etc/shadow && \
    echo "✅ RootFS ownership configured for Ubuntu" && \
    echo "🎉 RootFS pre-installed in Ubuntu image!" && \
    echo "📊 Pre-installed RootFS verification:" && \
    echo "  - RootFS directory: $(ls -d /home/fex/.fex-emu/RootFS/*/ | head -1)" && \
    echo "  - RootFS files: $(find /home/fex/.fex-emu/RootFS -type f | wc -l)" && \
    echo "  - RootFS size: $(du -sh /home/fex/.fex-emu/RootFS)" && \
    echo "  - Config file: $(ls -la /home/fex/.fex-emu/Config.json)" && \
    echo "🎯 Ubuntu + FEX + RootFS integration complete!" && \
    echo "🚀 Ready for immediate x86 application execution on Ubuntu!" && \
    echo "🏗️ Ultimate stability achieved: Ubuntu LTS base + Multi-RootFS + FEX emulation!"

# Switch to fex user
USER fex
WORKDIR /home/fex 

# Ubuntu-optimized startup command with detailed information
CMD ["/bin/bash", "-c", "echo '🎉 FEX-Emu on Ubuntu ready!' && echo '🏗️ Base: Ubuntu 24.04 LTS (Maximum compatibility)' && echo '🏷️ FEX Version: ${FEX_VERSION}' && echo '🐧 RootFS: ${ROOTFS_INFO}' && echo '🔧 Ubuntu LTS for maximum compatibility and enterprise stability!' && echo '📊 Native glibc: Perfect x86 emulation support' && echo '🚀 Performance: Near-native ARM64 execution with x86 emulation' && echo '💡 Try: FEXBash' && echo '🎯 Ready for x86 application execution!' && /bin/bash"]
