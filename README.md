# Remote SSH to macOS (Apple Silicon / Intel) Fix for Antigravity IDE

A workaround script to resolve Remote SSH connection failures when connecting to a macOS host (`darwin-arm64` / `darwin-x64`) from the Antigravity IDE.

---

## The Problem

When attempting to connect to a remote Mac (e.g., Mac mini or MacBook) via the **Remote - SSH** extension, the connection setup fails. 

In the remote agent logs, you will see errors like:
```text
An error occurred while starting the server, with exit code: 1
/Users/username/.antigravity-ide-server/bin/.../bin/antigravity-ide-server: line 25: /node: No such file or directory
```
or `404 Not Found` errors in the IDE console while downloading the server package. This happens because the Antigravity IDE release servers do not distribute a `darwin-arm64` or `darwin-x64` package for the remote server component.

---

## The Solution

This script builds a **hybrid macOS IDE server** directly on your remote Mac:
1. **Skeleton Extraction**: Downloads the platform-agnostic JS structure from the `linux-arm` package release.
2. **Interpreter Replacement**: Swaps the Linux `node` binary with a native macOS `node` binary (automatically detecting if the host is Apple Silicon `arm64` or Intel `x86_64`).
3. **Native Compilation**: Compiles the native modules (`@vscode/spdlog`, `@parcel/watcher`, `node-pty`, `native-watchdog`, `kerberos`, and `@vscode/ripgrep`) natively in a temporary folder using the remote Mac's Xcode/CommandLineTools (`clang`).
4. **Startup Configuration**: Patches the startup script (`antigravity-ide-server`) to export `DYLD_LIBRARY_PATH` (including Homebrew library paths like `/opt/homebrew/lib`).
5. **Code Signing**: Clears macOS Gatekeeper quarantine tags and dynamically signs the compiled binaries and `.node` bundles with local ad-hoc signatures (`codesign`) to prevent launch failures.
6. **Language Server Setup**: Locates the native macOS language server binary from your local IDE installation (automatically checking standard paths like `/Applications/Antigravity IDE.app`) and copies it to the server's extension directory so that agentic features function correctly.

---

## How to Use

Run the setup script directly on your remote Apple Silicon Mac target via SSH or terminal:

### Option A: One-liner execution (Recommended)
You can run the script directly from this repository:
```bash
curl -fsSL https://raw.githubusercontent.com/ryeruva/antigravity-remote-ssh-mac-fix/main/patch_remote_server.sh | bash
```

### Option B: Manual execution
1. Clone this repository or download `patch_remote_server.sh`:
   ```bash
   git clone https://github.com/ryeruva/antigravity-remote-ssh-mac-fix.git
   cd antigravity-remote-ssh-mac-fix
   ```
2. Open `patch_remote_server.sh` and make sure the `COMMIT_ID` variable matches your IDE's version:
   * You can find the **Commit ID** in your IDE under **Help** -> **About** (or **Antigravity IDE** -> **About** on macOS clients).
3. Run the script:
   ```bash
   chmod +x patch_remote_server.sh
   ./patch_remote_server.sh
   ```

After running the script, try connecting to your remote Mac mini/MacBook in the IDE. The connection will automatically discover the pre-built server version and connect successfully!

---

## Requirements on Remote Mac
* macOS with Xcode Command Line Tools installed (run `xcode-select --install` if you don't have them).
* An active internet connection on the remote Mac (to download the skeleton and Node).

---

## License
MIT
