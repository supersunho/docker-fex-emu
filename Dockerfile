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


# Install RootFS extraction tools, aria2, and dependencies for Ubuntu
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo "📦 Installing RootFS extraction tools and dependencies..." && \
    echo "🐧 Using Ubuntu for RootFS preparation (maximum compatibility)" && \
    echo "🔧 Setting up extraction toolchain with aria2 accelerator..." && \
    apt-get update -qq >/dev/null 2>&1 && \
    apt-get install -qq -y --no-install-recommends \
        curl \
        aria2 \
        jq \
        bc \
        sudo \
        coreutils \
        squashfs-tools \
        erofs-utils \
        e2fsprogs \
        util-linux >/dev/null 2>&1 && \   
    echo "🔒 Updating CA certificates for maximum compatibility..." && \
    apt-get install -qq -y apt-utils ca-certificates && \
    update-ca-certificates && \
    echo "✅ CA certificates updated" && \
    echo "✅ aria2 download accelerator installed"


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


# RootFS setup with aria2c mirror acceleration
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "🚀 Starting intelligent RootFS setup with mirror speed test..." && \
    echo "📊 RootFS configuration summary:" && \
    echo "  - Target OS: ${ROOTFS_OS}" && \
    echo "  - Target Version: ${ROOTFS_VERSION}" && \
    echo "  - RootFS Type: ${ROOTFS_TYPE}" && \
    echo "  - Strategy: aria2c multi-mirror with speed test" && \
    echo "  - Location: /opt/fex-rootfs/" && \
    echo "  - Running as: root (for proper permissions)" && \
    \
    # Prepare fex user home for RootFS operations
    mkdir -p /home/fex/.fex-emu/RootFS && \
    chown -R fex:fex /home/fex && \
    \
    # Define dynamic paths based on execution user
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
    # Fallback to aria2c accelerated download with mirror selection
    if [ "$FEXROOTFS_SUCCESS" = "false" ]; then \
        echo "🔄 FEXRootFSFetcher failed - activating aria2c accelerated fallback..." && \
        echo "⚡ Using intelligent mirror selection with speed testing..." && \
        \
        mkdir -p /tmp/fex-rootfs && \
        \
        # Fetch mirror list from FEX RootFS server
        MIRROR_JSON_URL="https://rootfs.fex-emu.gg/RootFS_links.json" && \
        ROOTFS_KEY="${ROOTFS_OS}_$(echo ${ROOTFS_VERSION} | sed 's/\./_/g')" && \
        echo "📥 Fetching mirror list for $ROOTFS_KEY..." && \
        \
        MIRROR_LIST=$(curl -L -k -m 30 -s "$MIRROR_JSON_URL" 2>/dev/null) && \
        \
        if [ -n "$MIRROR_LIST" ]; then \
            echo "✅ Mirror list fetched successfully" && \
            MIRROR_URLS=$(echo "$MIRROR_LIST" | jq -r ".\"$ROOTFS_KEY\"[]?" 2>/dev/null | grep -E '^https?://') && \
            \
            if [ -n "$MIRROR_URLS" ]; then \
                echo "✅ Found $(echo "$MIRROR_URLS" | wc -l) mirrors for $ROOTFS_KEY" && \
                echo "⚡ Testing mirror speeds (1MB sample from each)..." && \
                \
                # Parallel speed test (max 5 concurrent tests)
                echo "$MIRROR_URLS" | xargs -P 5 -I {} bash -c ' \
                    url="{}"; \
                    speed=$(curl -r 0-1048576 -L -k -m 10 -w "%{speed_download}" -o /dev/null -s "$url" 2>/dev/null || echo "0"); \
                    speed_kb=$(echo "scale=2; $speed / 1024" | bc -q 2>/dev/null || echo "0"); \
                    echo "$speed_kb|$url"' > /tmp/mirror_results.txt && \
                \
                if [ -s /tmp/mirror_results.txt ]; then \
                    # Display top 3 mirrors
                    echo "🏆 Top 3 fastest mirrors:" && \
                    sort -t'|' -k1 -rn /tmp/mirror_results.txt | head -3 | \
                        awk -F'|' '{printf "  %.2f KB/s - %s\n", $1, $2}' && \
                    \
                    # Extract top 3 mirror URLs for aria2c
                    TOP_MIRRORS=$(sort -t'|' -k1 -rn /tmp/mirror_results.txt | head -3 | cut -d'|' -f2) && \
                    \
                    # Get filename from first mirror
                    ROOTFS_FILE=$(basename $(echo "$TOP_MIRRORS" | head -1)) && \
                    ROOTFS_LOCAL_PATH="/tmp/fex-rootfs/$ROOTFS_FILE" && \
                    \
                    # Create aria2c input file (TAB-separated URLs on single line)
                    echo "$TOP_MIRRORS" | tr '\n' '\t' | sed 's/\t$//' > /tmp/aria2_input.txt && \
                    echo "" >> /tmp/aria2_input.txt && \
                    \
                    echo "🚀 Starting aria2c multi-mirror download..." && \
                    ARIA2_SUCCESS=false && \
                    if aria2c \
                        --uri-selector=feedback \
                        --max-connection-per-server=4 \
                        --split=3 \
                        --min-split-size=1M \
                        --max-tries=5 \
                        --retry-wait=3 \
                        --connect-timeout=15 \
                        --timeout=60 \
                        --check-certificate=false \
                        --allow-overwrite=true \
                        --auto-file-renaming=false \
                        --continue=true \
                        --out="$ROOTFS_FILE" \
                        --dir=/tmp/fex-rootfs \
                        --input-file=/tmp/aria2_input.txt; then \
                        ARIA2_SUCCESS=true && \
                        echo "✅ aria2c download completed successfully"; \
                    else \
                        echo "❌ aria2c download failed"; \
                    fi && \
                    \
                    # Fallback to curl if aria2c fails
                    if [ "$ARIA2_SUCCESS" = "false" ]; then \
                        echo "🔄 aria2c failed, falling back to curl..." && \
                        BEST_MIRROR=$(echo "$TOP_MIRRORS" | head -1) && \
                        echo "📥 Using fastest mirror: $BEST_MIRROR" && \
                        \
                        for download_attempt in 1 2 3; do \
                            echo "⏳ curl download attempt $download_attempt/3..." && \
                            if curl -L -k -C - -S \
                                    --connect-timeout 30 \
                                    --max-time 600 \
                                    --retry 3 \
                                    --retry-delay 5 \
                                    -o "$ROOTFS_LOCAL_PATH" \
                                    "$BEST_MIRROR"; then \
                                echo "✅ curl download completed (attempt $download_attempt)" && \
                                break; \
                            else \
                                echo "❌ curl download failed (attempt $download_attempt)"; \
                                if [ $download_attempt -lt 3 ]; then \
                                    sleep 10; \
                                fi; \
                            fi; \
                        done; \
                    fi && \
                    \
                    rm -f /tmp/mirror_results.txt /tmp/aria2_input.txt; \
                else \
                    echo "❌ Mirror speed test failed"; \
                fi; \
            else \
                echo "❌ No valid mirrors found in JSON for $ROOTFS_KEY"; \
            fi; \
        else \
            echo "❌ Failed to fetch mirror list"; \
        fi && \
        \
        # Verify downloaded file
        if [ ! -f "$ROOTFS_LOCAL_PATH" ] || [ ! -s "$ROOTFS_LOCAL_PATH" ]; then \
            echo "❌ RootFS file not downloaded or empty" && \
            if [ -n "$ROOTFS_URL" ]; then \
                echo "🔄 Final fallback: using provided ROOTFS_URL" && \
                ROOTFS_FILE=$(basename "$ROOTFS_URL") && \
                ROOTFS_LOCAL_PATH="/tmp/fex-rootfs/$ROOTFS_FILE" && \
                curl -L -k -C - -o "$ROOTFS_LOCAL_PATH" "$ROOTFS_URL" || exit 1; \
            else \
                echo "❌ No ROOTFS_URL provided for final fallback" && \
                exit 1; \
            fi; \
        fi && \
        \
        echo "✅ RootFS file verified: $ROOTFS_FILE" && \
        echo "📊 File size: $(du -h "$ROOTFS_LOCAL_PATH" | cut -f1)" && \
        \
        # Extract RootFS
        ROOTFS_DIRNAME="$(echo ${ROOTFS_OS} | sed 's/^./\U&/')_$(echo ${ROOTFS_VERSION} | sed 's/\./_/g')" && \
        EXTRACT_DIR="$FEX_ROOTFS_DIR/${ROOTFS_DIRNAME}" && \
        echo "📁 RootFS directory name: $ROOTFS_DIRNAME" && \
        echo "📁 Extraction directory: $EXTRACT_DIR" && \
        \
        if [ -d "$EXTRACT_DIR" ]; then \
            echo "🗑️ Removing existing RootFS directory..." && \
            rm -rf "$EXTRACT_DIR"; \
        fi && \
        mkdir -p "$EXTRACT_DIR" && \
        \
        if echo "$ROOTFS_FILE" | grep -q '\.sqsh$\|\.squashfs$'; then \
            echo "🔧 Extracting SquashFS file..." && \
            unsquashfs -f -d "$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" >/dev/null 2>&1 && \
            echo "✅ SquashFS extraction completed"; \
        elif echo "$ROOTFS_FILE" | grep -q '\.ero$\|\.erofs$'; then \
            echo "🔧 Extracting EROFS file..." && \
            dump.erofs --extract="$EXTRACT_DIR" "$ROOTFS_LOCAL_PATH" >/dev/null 2>&1 && \
            echo "✅ EROFS extraction completed"; \
        else \
            echo "❌ Unknown RootFS file format: $ROOTFS_FILE" && \
            exit 1; \
        fi && \
        \
        echo "⚙️ Writing FEX configuration..." && \
        printf '{"Config":{"RootFS":"%s"},"ThunksDB":{}}' "$ROOTFS_DIRNAME" > "$FEX_CONFIG_PATH" && \
        chown -R $FEX_USER:$FEX_USER $FEX_USER_HOME/.fex-emu && \
        \
        echo "🔍 Verifying manual RootFS installation..." && \
        ROOTFS_CONTENT_COUNT=$(find "$EXTRACT_DIR" -type f | wc -l) && \
        echo "📊 RootFS verification: $ROOTFS_CONTENT_COUNT files extracted" && \
        if [ "$ROOTFS_CONTENT_COUNT" -gt 100 ]; then \
            echo "✅ Manual RootFS setup completed successfully"; \
        else \
            echo "❌ RootFS may be incomplete (too few files)" && \
            exit 1; \
        fi; \
    else \
        echo "🎉 FEXRootFSFetcher setup completed successfully!" && \
        chown -R $FEX_USER:$FEX_USER $FEX_USER_HOME/.fex-emu; \
    fi && \
    \
    # Move user-specific RootFS to shared directory
    echo "📁 Moving RootFS to shared directory: /opt/fex-rootfs/..." && \
    if [ -d "$FEX_ROOTFS_DIR" ] && [ "$(ls -A "$FEX_ROOTFS_DIR" 2>/dev/null)" ]; then \
        cp -r "$FEX_ROOTFS_DIR"/* /opt/fex-rootfs/ && \
        chown -R root:root /opt/fex-rootfs && \
        chmod -R 755 /opt/fex-rootfs && \
        echo "✅ RootFS successfully moved to shared directory"; \
    else \
        echo "❌ No RootFS found to move" && \
        exit 1; \
    fi && \
    \
    # Final verification
    echo "🔍 Final RootFS verification..." && \
    ROOTFS_FILES=$(find /opt/fex-rootfs -type f | wc -l) && \
    echo "📊 Final RootFS summary:" && \
    echo "  - Files: $ROOTFS_FILES" && \
    echo "  - Size: $(du -sh /opt/fex-rootfs 2>/dev/null || echo 'Unknown')" && \
    echo "  - Method: $( [ "$FEXROOTFS_SUCCESS" = "true" ] && echo "FEXRootFSFetcher" || echo "aria2c accelerated fallback" )" && \
    if [ "$ROOTFS_FILES" -gt 0 ]; then \
        echo "✅ Final RootFS verification passed"; \
    else \
        echo "❌ Final RootFS verification failed" && \
        exit 1; \
    fi && \
    \
    # Cleanup
    echo "🧹 Cleaning up temporary files..." && \
    rm -rf /tmp/fex-rootfs && \
    find /opt/fex-rootfs -name "*.sqsh" -delete 2>/dev/null || true && \
    find /opt/fex-rootfs -name "*.ero" -delete 2>/dev/null || true && \
    echo "✅ Cleanup completed" && \
    echo "🎉 RootFS preparation complete with aria2c acceleration!"


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
    apt-get update -qq >/dev/null 2>&1 && \
    apt-get install -qq -y --no-install-recommends  \
        sudo curl wget jq \
        libc6 \
        libstdc++6 \
        libssl3 \
        libzstd1 \
        squashfs-tools \
        erofs-utils \
        binfmt-support >/dev/null 2>&1 && \
    apt-get install -qq -y apt-utils ca-certificates && \
    update-ca-certificates && \
    echo "✅ Ubuntu runtime packages installed" && \
    rm -rf /var/tmp/* && \
    echo "✅ Ubuntu runtime setup completed"


# Copy optimized FEX binaries from Ubuntu builder
COPY --from=fex-builder /usr/local/fex /usr/local/fex
RUN echo "📦 Copying FEX binaries to Ubuntu runtime..." && \
    strip /usr/local/fex/bin/* 2>/dev/null || true && \
    find /usr/local/fex -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    echo "✅ FEX binary optimization completed"


ENV PATH="/usr/local/fex/bin:$PATH"


# Copy RootFS and configuration (as root)
COPY --from=rootfs-preparer /opt/fex-rootfs /opt/fex-rootfs


# Set up RootFS configuration (as root)
RUN echo "📦 Installing RootFS in Ubuntu runtime..." && \
    chown -R root:root /opt/fex-rootfs && \
    chmod -R 755 /opt/fex-rootfs && \
    \
    echo "📋 Creating template configuration for new users..." && \
    mkdir -p /etc/skel/.fex-emu && \
    ROOTFS_DIRNAME=$(ls /opt/fex-rootfs/ | head -1) && \
    if [ -n "$ROOTFS_DIRNAME" ]; then \
        echo "{\"Config\":{\"RootFS\":\"/opt/fex-rootfs/$ROOTFS_DIRNAME\"}}" > /etc/skel/.fex-emu/Config.json && \
        echo "✅ Template configuration created: /opt/fex-rootfs/$ROOTFS_DIRNAME"; \
    else \
        echo "❌ No RootFS directory found" && \
        exit 1; \
    fi && \
    \
    echo "🎉 RootFS pre-installed in Ubuntu image!" && \
    echo "📊 RootFS verification:" && \
    echo "  - RootFS directory: /opt/fex-rootfs/$ROOTFS_DIRNAME" && \
    echo "  - RootFS files: $(find /opt/fex-rootfs -type f | wc -l)" && \
    echo "  - RootFS size: $(du -sh /opt/fex-rootfs)" && \
    echo "🎯 Ubuntu + FEX + RootFS integration complete!"


# Create default fex user
RUN echo "👤 Creating default fex user for Ubuntu runtime..." && \
    useradd -m -s /bin/bash fex && \
    usermod -aG sudo fex && \
    echo "fex ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/fex && \
    echo "✅ User 'fex' ready for x86 emulation with RootFS!"


# Switch to fex user
USER fex
WORKDIR /home/fex 


# Verify RootFS configuration for fex user
RUN echo "🔍 Verifying RootFS configuration for user..." && \
    if [ -f "/home/fex/.fex-emu/Config.json" ]; then \
        echo "✅ User configuration found: $(cat /home/fex/.fex-emu/Config.json)"; \
    else \
        echo "❌ User configuration not found" && \
        exit 1; \
    fi && \
    if [ -d "/opt/fex-rootfs" ]; then \
        echo "✅ RootFS directory accessible"; \
    else \
        echo "❌ RootFS directory not accessible" && \
        exit 1; \
    fi && \
    echo "🎉 RootFS verification completed successfully!"


# Ubuntu-optimized startup command
CMD ["/bin/bash", "-c", "echo '🎉 FEX-Emu on Ubuntu with aria2c-accelerated RootFS ready!' && echo '🏗️ Base: Ubuntu 24.04 LTS' && echo '🏷️ FEX Version: ${FEX_VERSION}' && echo '🐧 RootFS: ${ROOTFS_INFO}' && echo '⚡ Download: aria2c multi-mirror acceleration' && echo '💡 Try: FEXBash' && /bin/bash"]
