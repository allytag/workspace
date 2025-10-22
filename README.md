# APK Editing Toolkit

All scripts auto-detect the workspace by looking at their own location, so you can rename or move the base folder at any time without breaking anything.

> Every script supports `--help` to list its options and defaults.
> All generated artifacts, caches, and backups live under `work/`, so nothing touches the rest of your Mac.

## Setup

```bash
cd /path/to/your/workspace   # e.g. ~/Downloads/mywork
[ -f work/env.sh ] && source work/env.sh  # optional overrides; scripts auto-detect bundled JDKs
```

If you bundle tools (apktool, uber-apk-signer, platform-tools, etc.) place them inside the `tools/` directory within the workspace. Apktool framework files are cached under `work/apkfw`, so nothing leaks outside the folder.

## Bundle Tools

```bash
./scripts/tools_install.sh
```

- Downloads the latest releases of apktool, uber-apk-signer, JADX, Android platform-tools, and the Temurin LTS JDK straight into `tools/`.
- Updates `work/env.sh` automatically so `JAVA_HOME` points at the freshly installed JDK (kept relative to the workspace).
- Accepts `--only NAME` to install a specific tool, `--force` to refresh an existing bundle, and `--list` to show supported names.
- Set `APKTOOL_VERSION`, `UBER_APK_SIGNER_VERSION`, `JADX_VERSION`, `JDK_VERSION`, or `JDK_FEATURE_VERSION` to pin versions; leave them unset to track the current LTS releases.

## Run Commands with Workspace Env

```bash
./scripts/with_env.sh java -version
./scripts/with_env.sh --shell          # open an interactive shell using the bundled JDK
```

- Wrap any command to inherit the workspace environment (useful for one-off tools).
- `--shell` drops you into an interactive shell with all variables set; exit to return to your original session.

## Decode / Edit Resources

```bash
./scripts/decode.sh --apk /path/to/App.apk
```

- Decodes into `work/decoded`.
- Creates `work/backups/decoded_*.tar.gz` snapshots before overwriting existing output (disable via `--no-backup`).
- Pass `--open` if you want the decoded folder opened in VS Code after completion.

## Rebuild & Sign

```bash
./scripts/rebuild_and_sign.sh
```

- Rebuilds from `work/decoded`, generates `work/unsigned.apk`, and produces signed APKs under `work/out/`.
- Accepts flags for custom keystore paths/passwords and `--fresh` to clear previous signed builds.
- Verifies signatures by default (`--skip-verify` to opt out).
- Prints an `adb install` command when `adb` is available in `tools/platform-tools` or on `PATH`.

## Decompile (Read-Only) with JADX

```bash
./scripts/jadx_readonly.sh --apk /path/to/App.apk
```

- Exports sources to `work/jadx_out` (pass `--out-dir` to customize).
- Tries Gradle project export first, gracefully falls back if JADX cannot generate it.
- Use `--keep` to reuse the existing output folder.

## Wireless adb Helper

```bash
./scripts/wireless_adb.sh --install
```

- Guides you through pairing and connecting to a device over Wi‑Fi.
- Installs the most recent signed APK from `work/out` when `--install` is specified.
- Run `--add` to get interactive prompts for pairing/connecting when you don’t want to type the addresses manually.
- If multiple devices are online, you’ll get a numbered prompt; pass `--device SERIAL` to skip the prompt next time.
- Use `--list-only` to simply list connected devices.
- Pair and connect in one go by copying the values from Android’s Wireless Debugging screens:

  ```bash
  ./scripts/wireless_adb.sh --pair 192.168.1.50:37099 --code 123456 --connect 192.168.1.50:5555
  ```

  `--pair` uses the short-lived IP:PORT from *Pair device with pairing code*, `--code` is the six-digit pairing code, and `--connect` uses the persistent IP:PORT shown on the main Wireless Debugging screen.

## Reset Between Projects

```bash
./scripts/reset_work.sh
```

- Clears `work/decoded`, `work/out`, `work/unsigned.apk`, `work/backups`, and `work/jadx_out`.
- Keep backups or JADX exports with `--keep-backups` / `--keep-jadx`.
- Add `--reset-framework` if you also want to drop `work/apkfw` (apktool framework cache).
- Use `--dry-run` to preview pending removals.

## Cleanup

```bash
./scripts/cleanup_all.sh --yes
```

- Deletes the entire workspace directory. The script must live inside the workspace, so this wipes everything created by the toolkit.
- Use `--dry-run` to preview what would be removed.

## Useful Grep Helpers

After decoding, search smali quickly:

```bash
rg "Lcom/example/your/TargetClass;" work/decoded/smali*
rg "methodName(.*)" work/decoded/smali*
```

Because the workspace is self-contained, you can back it up or delete it safely—just restore the folder later and the scripts will continue to work from their new location.
