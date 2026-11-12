# StickyShot

The screenshot preview in the corner of a Mac disappears after about five seconds, and macOS has no setting to change that. StickyShot keeps it on screen until you close it.

## What it does

- Every screenshot or screen recording shows a preview in the lower-right corner of the screen you're on, and it stays until you close it.
- Several screenshots stack up, newest at the bottom, up to five at a time.
- **Click** a preview to open it. **Drag** it into Mail, Slack, Messages or any app. The preview stays up afterwards, so you can use it again. Hover over it to show the **×**, or **right-click** for Copy, Show in Finder and Move to Trash.
- The menu bar icon (a camera viewfinder) has these options:
  - Turn it on or off.
  - Have previews close after 10 seconds, 30 seconds, 1 minute or 5 minutes instead of staying up.
  - Close all previews.
  - Open your screenshots folder.
  - Start at login.
- It replaces the built-in macOS preview so you never see two. Quitting StickyShot brings the built-in one back.
- Screenshots still save where macOS normally puts them. StickyShot never moves or edits them.
- It never connects to the internet and collects no data.

Requires macOS 13 Ventura or later and runs on both Apple silicon and Intel Macs.

## Install

1. Download `StickyShot.zip` and double-click it to unzip.
2. Drag **StickyShot** into your **Applications** folder.
3. Open StickyShot. The first time, macOS may say it can't verify the developer, because the app isn't registered with Apple:
   - **macOS 15 or later:** click **Done**, open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to StickyShot.
   - **macOS 13 or 14:** right-click StickyShot in Applications, choose **Open**, then click **Open** again.

   You only have to do this once.
4. A camera viewfinder icon appears in the menu bar. Take a screenshot (⌘⇧3, ⌘⇧4 or ⌘⇧5) to try it out.

To have it start every time you log in, click the menu bar icon and choose **Start at Login**.

## Uninstall

Click the menu bar icon and choose **Quit StickyShot**, then drag the app from Applications to the Trash. Quitting puts the built-in macOS preview back.

## Build it yourself

You need the Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

This creates `dist/StickyShot.app` and `dist/StickyShot.zip`. All the code is in `Sources/main.swift`.

## License

MIT. Free to use, change and share.
