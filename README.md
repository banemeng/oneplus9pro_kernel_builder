# OnePlus 9 Pro (SM8350) Kernel Builder

Automated CI/CD build system for OnePlus 9 / 9 Pro (SM8350 - lemonadep / lemonade) Linux 5.4 kernel with latest **SukiSU-Ultra** and **SUSFS**.

## Features
- **Target Platform**: Snapdragon 888 (Lahaina / SM8350)
- **Base Kernel**: `dev-sm8350/kernel_oneplus_sm8350` (Branch 15)
- **Root Implementation**: SukiSU-Ultra (Latest)
- **SUSFS**: Supported (`kernel-5.4` branch)
- **Compiler**: Google AOSP Clang `r416183b` (LLVM 12.0.5) matching the ROM baseline
- **Config**: Extracted directly from live OnePlus 9 Pro Android 16 device (`phone_extracted.config`)
- **Packaging**: Automatically outputs AnyKernel3 `.zip` flasher

## How to Flash
1. Download the AnyKernel3 `.zip` from **Releases** or **Actions Artifacts**.
2. Open **Kernel Flasher** app on your phone.
3. Backup your current `boot` partition (safety first).
4. Select the downloaded `.zip` file and flash.
5. Reboot your device.
