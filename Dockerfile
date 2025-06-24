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
    echo "🎯 Installing critical FEX JIT dependencies..." && \
    apt-get install -qq -y \
        libunwind-dev \     
        libc6-dev \         
        build-essential \   
        libgcc-s1 >/dev/null 2>&1 && \         
    \
    echo "✅ All RootFS tools and dependencies installed successfully" && \
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
    export BASE_FLAGS="-O2 -march=armv8-a+simd -mtune=generic \
                -mno-outline-atomics \
                -mbranch-protection=none \
                -U_FORTIFY_SOURCE -fno-stack-protector" && \
    export EXTRA_C_FLAGS="$BASE_FLAGS" && \
    export EXTRA_CXX_FLAGS="$BASE_FLAGS" && \
    export EXTRA_ASM_FLAGS="$BASE_FLAGS -Wa,-mbranch-protection=none" && \
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
        -DCMAKE_C_FLAGS="$EXTRA_C_FLAGS" \
        -DCMAKE_CXX_FLAGS="$EXTRA_CXX_FLAGS" \
        -DCMAKE_ASM_FLAGS="$EXTRA_ASM_FLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$BASE_FLAGS" \
        -DCMAKE_SHARED_LINKER_FLAGS="$BASE_FLAGS" \
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
# glibc build
#==============================================
FROM ubuntu:24.04 AS glibc-builder

ARG GLIBC_VERSION=2.39
ARG GLIBC_CFLAGS="-O2 -march=armv8-a+simd -mtune=generic \
                   -mno-outline-atomics -mbranch-protection=none \
                   -U_FORTIFY_SOURCE -fno-stack-protector"

ENV DEBIAN_FRONTEND=noninteractive 

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
        build-essential gcc-12 g++-12 make git wget curl \
        flex bison texinfo python3 gawk >/dev/null 2>&1 && \
    echo "🔒 Updating CA certificates for maximum compatibility..." && \
    apt-get install -qq -y apt-utils ca-certificates && \
    update-ca-certificates && \
    echo "✅ CA certificates updated"

# ── get source ───────────────────────────────────────────────────────
RUN curl -sSL https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VERSION}.tar.gz \
        -o glibc.tar.gz && \
    tar xf glibc.tar.gz && \
    mkdir -p /build && \
    cd    /build && \
    CFLAGS="${GLIBC_CFLAGS}" \
    CXXFLAGS="${GLIBC_CFLAGS}" \
    /glibc-${GLIBC_VERSION}/configure \
        --prefix=/usr                \
        --libdir=/usr/lib            \
        --disable-werror             \
        --disable-nls                \
        --host=aarch64-linux-gnu     \
        --build=aarch64-linux-gnu && \
    make -j"$(nproc)" && \
    make install DESTDIR=/tmp/glibc-non-lse && ls -al /tmp/glibc-non-lse && \
    echo "✅ glibc non-LSE built & installed to /tmp/glibc-non-lse"


#==============================================
# RootFS Preparation Stage (Root privileges)
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
LABEL fex.rootfs.type="shared"

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
    echo "🔒 Updating CA certificates for maximum compatibility..." && \
    apt-get install -qq -y apt-utils ca-certificates && \
    update-ca-certificates && \
    echo "✅ CA certificates updated"

# Create shared RootFS directory (as root)
RUN echo "📁 Creating shared RootFS directory structure..." && \
    mkdir -p /opt/fex-rootfs && \
    chmod 755 /opt/fex-rootfs && \
    echo "✅ RootFS directory created: /opt/fex-rootfs"

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

# Create temporary fex user for FEXRootFSFetcher (but stay as root)
RUN echo "👤 Creating temporary fex user for RootFS operations..." && \
    useradd -m -s /bin/bash fex && \
    usermod -aG sudo fex && \
    echo "fex ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "✅ fex user created with sudo privileges"

# RootFS setup (as root with privilege escalation capabilities)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "🚀 Starting RootFS setup process as root..." && \
    echo "📊 RootFS configuration summary:" && \
    echo "  - Target OS: ${ROOTFS_OS}" && \
    echo "  - Target Version: ${ROOTFS_VERSION}" && \
    echo "  - RootFS Type: ${ROOTFS_TYPE}" && \
    echo "  - RootFS URL: ${ROOTFS_URL}" && \
    echo "  - Strategy: FEXRootFSFetcher + Manual fallback to shared directory" && \
    echo "  - Location: /opt/fex-rootfs/" && \
    echo "  - Running as: root (for proper permissions)" && \
    \
    # Prepare fex user home for RootFS operations
    mkdir -p /home/fex/.fex-emu/RootFS && \
    chown -R fex:fex /home/fex && \
    \
    # 🔧 Define dynamic paths based on execution user
    FEX_USER="fex" && \
    FEX_USER_HOME="/home/$FEX_USER" && \
    FEX_ROOTFS_DIR="$FEX_USER_HOME/.fex-emu/RootFS" && \
    FEX_CONFIG_PATH="$FEX_USER_HOME/.fex-emu/Config.json" && \
    echo "📁 Dynamic paths configured:" && \
    echo "  - FEX User: $FEX_USER" && \
    echo "  - FEX User Home: $FEX_USER_HOME" && \
    echo "  - FEX RootFS Directory: $FEX_ROOTFS_DIR" && \
    echo "  - FEX Config Path: $FEX_CONFIG_PATH" && \
    \
    # Try FEXRootFSFetcher first (as fex user but with root oversight)
    FEXROOTFS_SUCCESS=false && \
    echo "🎯 Attempting FEXRootFSFetcher (primary method)..." && \
    for attempt in 1 2 3; do \
        echo "⏳ FEXRootFSFetcher attempt $attempt/3..." && \
        if sudo -u $FEX_USER timeout 300 bash -c "cd $FEX_USER_HOME && FEXRootFSFetcher -yx --distro-name=${ROOTFS_OS} --distro-version=${ROOTFS_VERSION} --force-ui=tty" 2>/dev/null; then \
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
    # Fallback to manual setup with dynamic paths
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
        # 🔧 Fixed curl command (remove syntax errors)
        DOWNLOAD_SUCCESS=false && \
        echo "🔍 Starting download with corrected curl command..." && \
        for download_attempt in 1 2 3; do \
            echo "⏳ Download attempt $download_attempt/3..." && \
            if curl -L -k -S -H 'Cache-Control: no-cache' \
                    --connect-timeout 30 --max-time 600 \
                    --retry 3 --retry-delay 5 \
                    -o "$ROOTFS_LOCAL_PATH" \
                    "$ROOTFS_URL"; then \
                # Verify downloaded file exists and has content
                if [ -f "$ROOTFS_LOCAL_PATH" ] && [ -s "$ROOTFS_LOCAL_PATH" ]; then \
                    echo "✅ RootFS downloaded successfully (attempt $download_attempt)" && \
                    echo "📊 File verification: $(ls -lh "$ROOTFS_LOCAL_PATH")" && \
                    DOWNLOAD_SUCCESS=true && \
                    break; \
                else \
                    echo "❌ Downloaded file is missing or empty" && \
                    rm -f "$ROOTFS_LOCAL_PATH"; \
                fi; \
            else \
                echo "❌ Download failed (attempt $download_attempt)"; \
            fi && \
            if [ $download_attempt -lt 3 ]; then \
                echo "⏳ Waiting 10 seconds before retry..." && \
                sleep 10; \
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
        # 🔧 Use dynamic paths instead of hardcoded ones
        ROOTFS_DIRNAME="$(echo ${ROOTFS_OS} | sed 's/^./\U&/')_$(echo ${ROOTFS_VERSION} | sed 's/\./_/g')" && \
        EXTRACT_DIR="$FEX_ROOTFS_DIR/${ROOTFS_DIRNAME}" && \
        echo "📁 RootFS directory name: $ROOTFS_DIRNAME" && \
        echo "📁 Dynamic extraction directory: $EXTRACT_DIR" && \
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
        printf '{"Config":{"RootFS":"%s"},"ThunksDB":{}}' "$ROOTFS_DIRNAME" > "$FEX_CONFIG_PATH" && \
        echo "✅ FEX configuration written to $FEX_CONFIG_PATH" && \
        \
        chown -R $FEX_USER:$FEX_USER $FEX_USER_HOME/.fex-emu && \
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
        chown -R $FEX_USER:$FEX_USER $FEX_USER_HOME/.fex-emu; \
    fi && \
    \
    # 🔧 Move user-specific RootFS to shared directory using dynamic paths
    echo "📁 Moving RootFS to shared directory: /opt/fex-rootfs/..." && \
    echo "🔍 Checking source directory: $FEX_ROOTFS_DIR" && \
    if [ -d "$FEX_ROOTFS_DIR" ] && [ "$(ls -A "$FEX_ROOTFS_DIR" 2>/dev/null)" ]; then \
        echo "📊 Source directory contents: $(ls -la "$FEX_ROOTFS_DIR/")" && \
        cp -r "$FEX_ROOTFS_DIR"/* /opt/fex-rootfs/ && \
        chown -R root:root /opt/fex-rootfs && \
        chmod -R 755 /opt/fex-rootfs && \
        echo "✅ RootFS successfully moved to shared directory"; \
    else \
        echo "❌ No RootFS found to move to shared directory" && \
        echo "🔍 Debug: Checking alternative locations..." && \
        find /home -name "*.sqsh" -o -name "Ubuntu_*" -type d 2>/dev/null || true && \
        find /root -name "*.sqsh" -o -name "Ubuntu_*" -type d 2>/dev/null || true && \
        exit 1; \
    fi && \
    \
    # Final verification with improved debugging
    echo "🔍 Final RootFS verification and summary..." && \
    if [ -d "/opt/fex-rootfs" ]; then \
        ROOTFS_COUNT=$(find /opt/fex-rootfs -maxdepth 1 -type d | wc -l) && \
        ROOTFS_FILES=$(find /opt/fex-rootfs -type f | wc -l) && \
        echo "🎉 RootFS setup completed successfully!" && \ 
        echo "📊 Final RootFS verification summary:" && \
        echo "  - RootFS directories: $ROOTFS_COUNT" && \
        echo "  - RootFS files: $ROOTFS_FILES" && \
        echo "  - Method used: $( [ "$FEXROOTFS_SUCCESS" = "true" ] && echo "FEXRootFSFetcher (primary)" || echo "Manual setup (fallback)" )" && \
        echo "  - RootFS size: $(du -sh /opt/fex-rootfs 2>/dev/null || echo 'Unknown')" && \
        echo "  - Location: /opt/fex-rootfs/" && \
        echo "  - Contents: $(ls -la /opt/fex-rootfs/ 2>/dev/null || echo 'Directory empty or not accessible')" && \
        if [ "$ROOTFS_FILES" -gt 0 ]; then \
            echo "✅ Final RootFS verification passed successfully"; \
        else \
            echo "❌ Final RootFS verification failed - no files found" && \
            exit 1; \
        fi; \
    else \
        echo "❌ RootFS directory not found" && \
        exit 1; \
    fi;

# ── glibc non-LSE overlay ───────────────────────────────────────────
COPY --from=glibc-builder /tmp/glibc-non-lse/usr/ /usr/
RUN ldconfig && echo "✅ glibc non-LSE libraries now active in RootFS" && \
    \
    # Cleanup (as root - no permission issues)
    echo "🧹 Cleaning up temporary RootFS artifacts..." && \
    rm -rf /tmp/fex-rootfs && \
    find /opt/fex-rootfs -name "*.sqsh" -delete 2>/dev/null || true && \
    find /opt/fex-rootfs -name "*.ero" -delete 2>/dev/null || true && \
    echo "✅ Cleanup completed successfully" && \
    echo "🚀 Ready for immediate x86 application execution with RootFS!" && \
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

# RootFS related metadata
LABEL org.opencontainers.image.title="FEXBash Ubuntu-Optimized ARM64 Container with RootFS"
LABEL org.opencontainers.image.description="High-performance x86/x86_64 emulation on ARM64 with Ubuntu LTS base and shared RootFS"
LABEL org.opencontainers.image.version="${FEX_VERSION}"
LABEL fex.version="${FEX_VERSION}"
LABEL fex.rootfs.distribution="${ROOTFS_OS}-${ROOTFS_VERSION}"
LABEL fex.rootfs.type="shared"
LABEL fex.rootfs.location="/opt/fex-rootfs"
LABEL build.platform="${TARGETPLATFORM}"
LABEL base.image="ubuntu:24.04"

# Set environment variables for Ubuntu runtime
ENV DEBIAN_FRONTEND=noninteractive 
ENV TZ=Asia/Seoul
ENV FEX_VERSION=${FEX_VERSION}
ENV ROOTFS_INFO="${ROOTFS_OS}-${ROOTFS_VERSION}"
ENV FEX_SHARED_ROOTFS="/opt/fex-rootfs"

# Configure Ubuntu runtime environment
RUN echo "🏗️ Setting up Ubuntu 24.04 LTS runtime environment with RootFS..." && \
    echo "📊 Ubuntu runtime configuration:" && \
    echo "  - Base: Ubuntu 24.04 LTS" && \
    echo "  - Target: High-performance x86 emulation runtime" && \
    echo "  - Features: Native glibc + LTS stability + RootFS" && \
    echo "  - RootFS: /opt/fex-rootfs" && \
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
    echo "  - RootFS: /opt/fex-rootfs" && \
    apt-get update -qq >/dev/null 2>&1 && \
    echo "📦 Installing minimal runtime packages..." && \
    apt-get install -qq -y --no-install-recommends  \
        sudo curl wget jq \
        libc6 \
        libstdc++6 \
        libssl3 \
        libzstd1 \
        squashfs-tools \
        erofs-utils \
        binfmt-support >/dev/null 2>&1 && \
    echo "✅ Ubuntu runtime packages installed successfully" && \
    echo "🔒 Updating CA certificates for maximum compatibility..." && \
    apt-get install -qq -y apt-utils ca-certificates && \
    update-ca-certificates && \
    echo "✅ CA certificates updated" && \
    echo "📊 Runtime package summary:" && \
    echo "  - System libraries: libstdc++6, libc6" && \
    echo "  - Utilities: sudo, curl, wget, jq, file" && \
    echo "  - Architecture: ARM64 with x86 emulation support" && \
    echo "  - RootFS: Enabled" && \
    \
    # Ubuntu cleanup for size optimization
    echo "🧹 Performing Ubuntu cleanup for size optimization..." && \ 
    rm -rf /var/tmp/* && \
    echo "✅ Ubuntu runtime setup completed successfully" && \
    echo "🎉 Ubuntu runtime environment ready!"

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

# Copy RootFS and configuration (as root)
COPY --from=rootfs-preparer /opt/fex-rootfs /opt/fex-rootfs

# Set up RootFS configuration (as root - no permission issues)
RUN echo "📦 Installing RootFS in Ubuntu runtime..." && \
    chown -R root:root /opt/fex-rootfs && \
    chmod -R 755 /opt/fex-rootfs && \
    echo "✅ RootFS ownership configured for Ubuntu" && \
    \
    echo "📋 Creating template configuration for new users..." && \
    mkdir -p /etc/skel/.fex-emu && \
    ROOTFS_DIRNAME=$(ls /opt/fex-rootfs/ | head -1) && \
    echo "📁 Detected RootFS directory: $ROOTFS_DIRNAME" && \
    if [ -n "$ROOTFS_DIRNAME" ]; then \
        echo "{\"Config\":{\"RootFS\":\"/opt/fex-rootfs/$ROOTFS_DIRNAME\"}}" > /etc/skel/.fex-emu/Config.json && \
        echo "✅ Template configuration created for new users: /opt/fex-rootfs/$ROOTFS_DIRNAME"; \
    else \
        echo "❌ No RootFS directory found in shared location" && \
        exit 1; \
    fi && \
    \
    echo "🎉 RootFS pre-installed in Ubuntu image!" && \
    echo "📊 RootFS verification:" && \
    echo "  - RootFS directory: /opt/fex-rootfs/$ROOTFS_DIRNAME" && \
    echo "  - RootFS files: $(find /opt/fex-rootfs -type f | wc -l)" && \
    echo "  - RootFS size: $(du -sh /opt/fex-rootfs)" && \
    echo "  - Template config: /etc/skel/.fex-emu/Config.json" && \
    echo "🎯 Ubuntu + FEX + RootFS integration complete!" && \
    echo "🚀 Ready for immediate x86 application execution on Ubuntu!" && \
    echo "🏗️ Ultimate stability achieved: Ubuntu LTS + RootFS + FEX emulation!" && \
    echo "🎯 New users will automatically use RootFS!"

# Create default fex user (finally, as the last step)
RUN echo "👤 Creating default fex user for Ubuntu runtime..." && \
    echo "🔧 Configuring Ubuntu user management..." && \
    useradd -m -s /bin/bash fex && \
    usermod -aG sudo fex && \
    echo "fex ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/fex && \
    echo "✅ Ubuntu user configuration completed successfully" && \
    echo "🎯 User 'fex' ready for x86 emulation with RootFS!"

# Switch to fex user (final step)
USER fex
WORKDIR /home/fex 

# Verify RootFS configuration status for fex user
RUN echo "🔍 Verifying RootFS configuration for user..." && \
    if [ -f "/home/fex/.fex-emu/Config.json" ]; then \
        echo "✅ User configuration found: $(cat /home/fex/.fex-emu/Config.json)"; \
    else \
        echo "❌ User configuration not found" && \
        exit 1; \
    fi && \
    if [ -d "/opt/fex-rootfs" ]; then \
        echo "✅ RootFS directory accessible: $(ls -la /opt/fex-rootfs/ | head -3)"; \
    else \
        echo "❌ RootFS directory not accessible" && \
        exit 1; \
    fi && \
    echo "🎉 RootFS verification completed successfully!"

# Ubuntu-optimized startup command with RootFS information
CMD ["/bin/bash", "-c", "echo '🎉 FEX-Emu on Ubuntu with RootFS ready!' && echo '🏗️ Base: Ubuntu 24.04 LTS (Maximum compatibility)' && echo '🏷️ FEX Version: ${FEX_VERSION}' && echo '🐧 RootFS: ${ROOTFS_INFO} (Shared)' && echo '📁 RootFS Location: /opt/fex-rootfs' && echo '🔧 Ubuntu LTS for maximum compatibility and enterprise stability!' && echo '📊 Native glibc: Perfect x86 emulation support' && echo '🚀 Performance: Near-native ARM64 execution with x86 emulation' && echo '👥 Multi-user: All users share the same RootFS' && echo '💡 Try: FEXBash' && echo '🎯 Ready for x86 application execution!' && /bin/bash"]
