<img src="docs/app-icon.png" width="96" align="right" alt="App icon">

# I-5 Express

A macOS menu bar app that shows which way Seattle's I-5 express lanes are running right now, and whether they're open at all.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/icons-dark.png">
  <img src="docs/icons-light.png" alt="Menu bar icons: green N for northbound, blue S for southbound, red X for closed, an orange dot when switching soon, an amber warning triangle when the status can't be confirmed, and a gray question mark while checking">
</picture>

Click the icon for details: today's and tomorrow's schedule, upcoming changes, planned closures, and links to WSDOT's live sources.

<p>
  <img src="docs/popover-confirmed.png" width="370" alt="Popover showing the lanes confirmed southbound">
  &nbsp;
  <img src="docs/popover-cant-confirm.png" width="370" alt="Popover on Thanksgiving showing a warning that the status can't be confirmed">
</p>

## When to trust it

WSDOT doesn't publish a live feed for the express lanes. This app reads [WSDOT's express lanes page](https://wsdot.wa.gov/travel/roads-bridges/express-lanes) and works out the status from the posted schedule, early closures and planned closures.

It only shows **N**, **S** or **✕** when all of these are true:

- It read WSDOT's page in the last 2 hours. It checks every 15 minutes and again when your Mac wakes up.
- Every part of the page made sense. A new section or a line it can't read counts as a problem.
- The schedule itself looks sane, with no overlapping or backwards time ranges.
- Nothing on the page suggests today is different. That includes notices dated today, undated notices, and planned closures today without exact times.
- If today closes early, the page gives the closing time.
- Today isn't a holiday. WSDOT doesn't post holiday hours.

Otherwise it shows an amber **⚠**, explains why, and links to the [travel map](https://wsdot.com/travel/real-time/map/) and [@wsdot_traffic](https://x.com/wsdot_traffic) so you can check a live source.

It can't know about a closure WSDOT hasn't posted yet, like an emergency repair announced only on social media.

## Install

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't required.

```bash
git clone https://github.com/andrewmacheret/i5-macos-menubar.git
cd i5-macos-menubar
make install
```

This builds `I-5 Express.app`, copies it to `~/Applications` and opens it. Use the gear menu in the popover to turn on launch at login, change notifications, or show a countdown next to the icon.

The app is signed locally, not with a developer certificate. So macOS may ask you to approve notifications or launch at login again after each rebuild.

## Terminal

The same logic also runs as a terminal tool:

```bash
make status
```

```
I-5 express lanes: SOUTHBOUND
  Closed at 11:00 AM (59m)
  Checked WSDOT at 10:00 AM
  Source: https://wsdot.wa.gov/travel/roads-bridges/express-lanes
```

It exits with code `0` when the status is confirmed and `2` when it isn't, so scripts can check the result.

## Development

| Command | What it does |
| --- | --- |
| `make app` | Build `build/I-5 Express.app` |
| `make run` | Build and open the app from `build/` |
| `make install` | Build, copy to `~/Applications` and open |
| `make uninstall` | Quit the app and remove it |
| `make test` | Run the parser, schedule and trust tests |
| `make status` | Print the current status in the terminal |
| `make screenshots` | Regenerate the images in `docs/` |

The code is split into three parts:

- `Sources/I5Core` reads WSDOT's page (`Parser`), works out the status at any moment (`Engine`), and decides whether the status can be trusted (`Trust`). It has no UI code.
- `Sources/I5Express` is the menu bar app, built with AppKit and SwiftUI.
- `Sources/i5` is the terminal tool.

Tests run against a saved copy of WSDOT's page in `Tests/I5CoreTests/Fixtures`.

## Not affiliated with WSDOT

This is a personal project. Schedule data comes from the Washington State Department of Transportation. Always follow posted signs on the road.

## License

[MIT](LICENSE)
