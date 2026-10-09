<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="artwork/droiddeck-banner-dark.svg">
    <img alt="DroidDeck" src="artwork/droiddeck-banner-light.svg" width="100%">
  </picture>
</p>

DroidDeck brings the SteamOS experience to Android: Valve's Steam client in Big Picture on your Adreno handheld, with Windows games through Valve's ARM64 Proton.

<p align="center"><a href="https://discord.gg/JRGAvawjsm"><img src="https://img.shields.io/badge/Discord-Join%20the%20community-5865F2?logo=discord&logoColor=white" alt="Join the DroidDeck Discord"></a></p>

<p align="center"><img src="docs/releases/media/0.2.0/launch-into-steam.gif" width="80%" alt="Tapping DroidDeck on the Android home screen and landing in Steam Big Picture"></p>

> Note: DroidDeck does not have a stand-alone website. Do not click on any download links from websites claiming to be the DroidDeck team. 

## Requirements and install

Use Android 9 or newer on a supported Adreno device (730 or newer, or 8xx). Adreno 6xx is experimental: DirectX 11 uses DXVK 2 and may run, and DirectX 12 games can still crash. Mali, Xclipse, PowerVR, and Adreno 710 are unsupported. No root is required. Allow about 3 GB for the runtime and 1.1 GB more for the desktop and emulators. Install the APK from [Releases](https://github.com/Droid-Deck/DroidDeck/releases), install the Linux runtime, then press **Play** and sign in. Steam downloads on first launch. Install **Desktop & apps** to use the desktop and emulators. The **Store** installs Linux apps and games from Flathub (ARM64 builds) with Flatpak; with additional options to install Appimages and set up scripts.

Before Steam launches, you must turn off **Restrict child processes** in Developer options. If this option is not available in developer settings (Android 12 and 13 devices), first launch of Steam will present a "Fix it for me" button, which will help automate the setup process.

## Community

Join the [DroidDeck Discord](https://discord.gg/JRGAvawjsm) for help, Preview builds, and device reports. Bug reports go in its **#bug-reports** forum; attach the session folder from `Download/DroidDeck/` so the logs come with it.

## Build

Run `tools/build_nerdctl.sh` with nerdctl/BuildKit; a host Android SDK is not required. The `tools/local-cross.Dockerfile` is based on Gradle 8.10.2/JDK 17 and downloads Google's pinned command-line tools during image build, verifies their SHA-256, accepts SDK licenses, and installs platform 34, build-tools 34.0.0, CMake 3.22.1, and NDK 27.3.13750724. The image also contains cross compilers, QEMU/PRoot, and the pinned Turnip build toolchain. `tools/build_local.sh` uses nerdctl to check out pinned Banners-Turnip and winlator-contents revisions, compile and verify the Linux Turnip driver from pinned Mesa source (using a SHA-256-verified original developer release only if the source build fails), build/audit the Linux runtime, stage its archive, manifest, package list and filesystem inventory under `app/build/generated/linuxfsRuntime`, and assemble/sign the APK. The resulting APK is copied to `DroidDeck-release.apk` in the project root. Runtime sources/build intermediates are cached under `~/.cache/droiddeck-build/linuxfs-runtime` by default; override this with `DROIDDECK_BUILD_CACHE`. Set `DROIDDECK_BUILD_VARIANT=debug` for a debug APK. GitHub Actions no longer builds or transfers the runtime archive; APKs built there without generated runtime assets continue to use the runtime catalog at install time.

The runtime's base rootfs and dependency closure remain official Arch Linux ARM, Debian, and Ubuntu binary packages rather than being rebuilt package-by-package from source. The package inventory records versions, licenses, project URLs and installed file hashes. The upstream builders still download the Arch base image and live package repositories over HTTP without pinned digests or signature verification, so these inputs are not independently authenticated or reproducible; an inventory is not a malware verdict. The runtime is roughly 600–800 MB compressed, substantially increasing the APK size. `tools/build_local.sh` defaults to nerdctl and uses the SDK/NDK in its build image; to use Docker instead, set `DROIDDECK_CONTAINER_ENGINE=docker` and provide a host Java 17 and Android SDK/NDK. Set `DROIDDECK_PA13_SOURCE_DIR` to existing PulseAudio 13.0 sources to skip fetching them. To install an APK on an attached device, run `tools/deploy_local.sh`.

## Limits

Compatibility and performance vary by device; hardware validation is limited. Desktop compositing uses software rendering. Firefox sandboxing is reduced under proot. See the session logs in `Download/DroidDeck/` when diagnosing problems.

## Credits and licence

GPL-3.0. Runtime, shim, input, and controller work build on WinNative and Bannerlator (maxjivi05). LSFG frame generation is from the work of Camille LaVey and the [Eden](https://eden-emu.dev) emulator project, following [lsfg-vk](https://github.com/PancakeTAS/lsfg-vk), ported to WinNative and DroidDeck by [@maxjivi05](https://github.com/maxjivi05); it needs your own copy of [Lossless Scaling](https://store.steampowered.com/app/993090/) and ships none of its shaders. x86 AppImages, and any whose own runtime cannot unpack them, are unpacked with [uruntime](https://github.com/VHSgunzo/uruntime) by VHSgunzo (MIT), shipped unmodified with its licence. See [LICENSE](LICENSE). Steam and Proton belong to Valve Corporation; this project is not affiliated with Valve.
