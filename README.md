# 🚀 FEXBash Base Images for ARM64

<p>
  <img src="https://img.shields.io/github/stars/supersunho/docker-fex-emu?style=for-the-badge&logo=github&color=gold" alt="GitHub Stars"/>
  <img src="https://img.shields.io/github/forks/supersunho/docker-fex-emu?style=for-the-badge&logo=github&color=blue" alt="GitHub Forks"/>
  <img src="https://img.shields.io/github/actions/workflow/status/supersunho/docker-fex-emu/builder.yml?style=for-the-badge&logo=github&color=green" alt="Build Status"/>  
  
</p>

This repository provides ARM64-optimized container images built from the original **[FEX-Emu project](https://github.com/FEX-Emu/FEX)**. These images enable running x86 and x86_64 applications on ARM64 platforms through FEX's high-performance emulation.

## 🐳 Docker Images

Container images are hosted on

| Host      | URL                                                                           |
| :-------- | :---------------------------------------------------------------------------- |
| DockerHub | **[supersunho/fex-emu](https://hub.docker.com/r/supersunho/fex-emu)**         |
| Github    | **[supersunho/docker-fex-emu](https://github.com/supersunho/docker-fex-emu)** |

## 🚀 Quick Start

### Pull and Run

```bash
# Pull the latest Ubuntu 24.04 image
docker pull supersunho/fex-emu:ubuntu-24.04

# Run interactive container
docker run -it --rm supersunho/fex-emu:ubuntu-24.04

# Execute x86 command directly
docker run --rm supersunho/fex-emu:ubuntu-24.04 FEXBash -c "uname -a"
```

### 💡 **Summary Of Image Tags**

| Tag Category              | Example                        | Description                       |
| :------------------------ | :----------------------------- | :-------------------------------- |
| **Latest Multi-Platform** | `latest`                       | Auto-selects optimal distribution |
| **LTS Recommended**       | `ubuntu-24.04`, `ubuntu-22.04` | Long-term support versions        |
| **Current Stable**        | `fedora-40`                    | Latest stable Fedora              |
| **Version-Specific**      | `ubuntu-24.04-2506`            | Pinned FEX version 2506           |

### 📦 **Available Image Tags**

| Tag                 | Description                              |
| :------------------ | :--------------------------------------- |
| `latest`            | Multi-platform auto-selection            |
| `ubuntu-24.04`      | Ubuntu 24.04 LTS                         |
| `ubuntu-22.04`      | Ubuntu 22.04 LTS                         |
| `ubuntu-24.04-2506` | Ubuntu 24.04 LTS (FEX Version: FEX-2506) |
| `ubuntu-22.04-2506` | Ubuntu 22.04 LTS (FEX Version: FEX-2506) |
| `fedora-40`         | Fedora 40                                |
| `fedora-38`         | Fedora 38                                |
| `fedora-40-2506`    | Fedora 40 (FEX Version: FEX-2506)        |
| `fedora-38-2506`    | Fedora 38 (FEX Version: FEX-2506)        |

### 🏷️ Image Naming Convention

Each image tag follows a structured naming pattern composed of three components:

```bash
supersunho/fex-emu:<rootfs-os>-<rootfs-version>-<fex-version>
```

**Components Explained:**

1. **RootFS OS** (`<rootfs-os>`): The Linux distribution used as the root filesystem

    - `ubuntu` - Ubuntu Linux distribution
    - `fedora` - Fedora Linux distribution

2. **RootFS Version** (`<rootfs-version>`): The specific version of the root filesystem

    - For Ubuntu: `22.04`, `24.04` (LTS versions)
    - For Fedora: `38`, `40` (recent releases)

3. **FEX Version** (`<fex-version>`): The FEX-Emu project version used for the build
    - Format: `YYMM` (e.g., `2506` for June 2025 release)
    - Corresponds to official FEX-Emu release tags

**Example Tags:**

```bash
supersunho/fex-emu:ubuntu-24.04-2506   # Ubuntu 24.04 + FEX version 2506
supersunho/fex-emu:fedora-40-2506      # Fedora 40 + FEX version 2506
supersunho/fex-emu:ubuntu-22.04-2505   # Ubuntu 22.04 + FEX version 2505
supersunho/fex-emu:fedora-38-2505      # Fedora 38 + FEX version 2505
```

### Available Images

```bash
# Ubuntu-based images

docker pull supersunho/fex-emu:ubuntu-24.04    # Ubuntu 24.04 LTS
docker pull supersunho/fex-emu:ubuntu-22.04    # Ubuntu 22.04 LTS

# Fedora-based images

docker pull supersunho/fex-emu:fedora-40       # Fedora 40
docker pull supersunho/fex-emu:fedora-38       # Fedora 38
```

## 💻 Usage Examples

### Interactive x86 Shell

```bash
docker run -it --rm supersunho/fex-emu:ubuntu-24.04

# Inside container: now you can run x86 applications
```

### Run x86 Applications

```bash
# Run x86 applications through FEXBash

docker run --rm supersunho/fex-emu:ubuntu-24.04 \
FEXBash -c "ls /usr/bin | head -10"
```

## 🏗️ Architecture & Build Information

-   **Source**: Built from official [FEX-Emu project](https://github.com/FEX-Emu/FEX)
-   **Base Architecture**: ARM64 (AArch64) optimized
-   **Target Emulation**: x86 and x86_64 applications
-   **Build Platform**: Ubuntu 24.04 LTS base for maximum compatibility
-   **Supported Platforms**: `linux/arm64`

## 📋 Supported RootFS Distributions

| Distribution | Versions     | Status             |
| ------------ | ------------ | ------------------ |
| **Ubuntu**   | 22.04, 24.04 | ✅ LTS Support     |
| **Fedora**   | 38, 40       | ✅ Latest Releases |

## 🔧 Technical Details

### Container Features

-   **Multi-RootFS Support**: Choose between Ubuntu and Fedora environments
-   **Pre-configured FEX**: Ready-to-use x86 emulation environment
-   **ARM64 Optimized**: Native ARM64 builds for maximum performance
-   **LTS Stability**: Ubuntu 24.04 base ensures long-term support

### Image Size

-   **Typical Size**: ~800MB - 1.2GB per image
-   **Optimization**: Multi-stage builds with aggressive cleanup
-   **Efficiency**: Shared layers between similar images

## 📚 Documentation & Support

-   **FEX-Emu Project**: [GitHub Repository](https://github.com/FEX-Emu/FEX)
-   **FEX Documentation**: [Official Wiki](https://wiki.fex-emu.com)

## ⚠️ Requirements

-   **Host Architecture**: ARM64/AArch64 system required
-   **Docker Version**: Docker 20.10+ recommended
-   **Platform**: Linux with ARM64 support

## 🤝 Contributing

This project builds container images from the upstream FEX-Emu project. For FEX-related issues or contributions, please visit the [official FEX repository](https://github.com/FEX-Emu/FEX).

---
