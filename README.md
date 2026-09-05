# thistle

A Mac app that talks to [Gotenberg](https://gotenberg.dev). It can boot the full Gotenberg image on Apple silicon without Docker, or send requests to a Gotenberg API you already run.

The window is a client. A per-user LaunchAgent owns the VM. Launch does not boot the guest. **Start Engine** (or the first convert) registers the agent, pulls `linux/arm64` if needed, boots the container, and waits for `/health`. Quitting the window leaves the engine running. **Stop Engine** tears the VM down. After 15 minutes idle the agent stops the guest and deletes the writable layer.

One GUI instance. One CPU guest. A second launch brings the existing window forward.

## Requirements

- Mac with Apple silicon
- macOS 26
- Xcode 26 / Swift 6.2

## Build and run

```bash
make run
```

That builds `bin/Thistle.app` with `ThistleEngine` inside, signs the helper with `com.apple.security.virtualization`, and opens the GUI. Enable **Thistle Engine** in System Settings > General > Login Items if macOS asks.

Notarized GitHub binaries follow the eucaly release flow. See `MAINTAINERS.md`. The app checks GitHub for a newer notarized zip and can replace itself from **Thistle > Check for Updates...**.

## First start

The first **Start Engine** downloads a Kata arm64 kernel, Apple's `vminit`, and `gotenberg/gotenberg:8` (Chromium, LibreOffice, and PDF engines). Later starts reuse `~/Library/Application Support/thistle/`. Chromium and LibreOffice auto-start so the first conversion is not a cold launch.

The VM uses 1 CPU and 2 GiB of memory. The guest still listens on port 3000. The host address is the vmnet IPv4. Copy it from the toolbar if another client should call the same engine.

The **Start Engine** control is a split button. The menu has **Restart**, **Refresh Image** (pull a new digest and rebuild the rootfs), and **Reset** (delete downloaded engine data, temporary jobs, and logs while keeping settings). Those actions open the engine banner so the log stays visible.

The inspector has a **Built-in VM** toggle. Off uses a custom Gotenberg URL (for example `http://127.0.0.1:3000`) and stops the guest if it is running. Connect the URL, then conversions go to that API. Turning **Built-in VM** on again returns to the local engine; **Start Engine** then boots the guest.

## Actions

Pick an action in the sidebar, then run it in the same window:

- **Chromium:** URL, HTML, or Markdown to PDF. URL, HTML, or Markdown screenshots.
- **LibreOffice:** Office documents to PDF.
- **PDF engines:** merge, split, flatten, optimize, PDF/A, encrypt, rotate, watermark, stamp, metadata, bookmarks, embed, Factur-X.

JSON routes (read metadata, read bookmarks) show the result in the window. Binary routes keep the converted file and show a preview with **Open**, **Show in Finder**, and **Save As**. Save As starts in the source file's folder when there is one, otherwise the last folder you used.

## Notes

- Intel Macs and Rosetta are not supported.
- No App Store sandbox. Developer ID plus the virtualization entitlement on the helper is enough to distribute.
- The guest cannot bind port 0. The VM IPv4 is the ephemeral part.
- A previous LibreOffice-only rootfs in Application Support is unused. The full image unpacks to its own cache file.

## License

[MIT](LICENSE)
