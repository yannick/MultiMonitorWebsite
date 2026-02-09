# Multi Monitor Website Screensaver

! beware, this is a Vibe coding exercise !

A macOS screensaver that displays configurable websites on multiple monitors.

vibe code modified version of https://github.com/davenicoll/swiss-railway-clock-screensaver.git


## Features

- Display different websites on each monitor
- Configurable URLs and zoom levels per screen
- Supports both Intel and Apple Silicon Macs

## Installation

1. Download the appropriate DMG for your Mac from the [Releases](https://github.com/yannick/MultiMonitorWebsite/releases) page:
   - `MultiMonitorWebsite-1.0-AppleSilicon.dmg` for M1/M2/M3 Macs
   - `MultiMonitorWebsite-1.0-Intel.dmg` for Intel Macs

2. Open the DMG and copy `MultiMonitorWebsite.saver` to `~/Library/Screen Savers/`

3. Open **System Settings > Screen Saver** and select "Multi Monitor Website"


## Building from Source

```bash
git clone https://github.com/yannick/MultiMonitorWebsite/releases 
cd MultiMonitorWebsite
xcodebuild -project MultiMonitorWebsite.xcodeproj -scheme MultiMonitorWebsite -configuration Release build
```

The built screensaver will be in `~/Library/Developer/Xcode/DerivedData/MultiMonitorWebsite-*/Build/Products/Release/`

## License

MIT
