# Privacy policy

*Last updated November 27, 2026*

I-5 Express for Mac doesn't collect, store or share any personal information. It has no accounts, ads, analytics or tracking.

## What the app does on the network

The app downloads the express lanes schedule from Andrew's server at `i5.andrewmacheret.com`, which runs on Amazon Web Services. That server reads [WSDOT's express lanes page](https://wsdot.wa.gov/travel/roads-bridges/express-lanes) and highway alerts. The app no longer contacts WSDOT's page itself.

Like any web request, a download tells the server your IP address and that the request came from this app. The server keeps no record of these requests. It has no access logs.

If you open the Cameras section, the app loads the camera pictures straight from WSDOT at `images.wsdot.wa.gov`. WSDOT's [privacy notice](https://wsdot.wa.gov/about/policies/web-privacy-notice) covers what it does with those requests.

Links in the app, such as the WSDOT travel map or WSDOT Traffic on Bluesky, open in your browser. Those sites have their own privacy policies.

The app checks GitHub for a new version every 6 hours, using [Sparkle](https://sparkle-project.org). It downloads the release's update feed, and the update itself when there is one. GitHub's [privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement) covers those requests. Turn off **Install updates automatically** in the gear menu to stop automatic checks.

## What stays on your Mac

- The last copy of the server's data, so the app can show the status right away when it starts, and keep working offline.
- Your settings, such as the countdown, notifications and automatic updates.
- When Sparkle last checked for an update.

None of this leaves your Mac. Deleting the app and its folder in `~/Library/Caches/com.andrewmacheret.i5` removes the saved copy. The settings are in `~/Library/Preferences/com.andrewmacheret.i5.plist`.

## Permissions

- **Notifications:** only if you turn on **Notify when lanes change**. Alerts are created on your Mac.
- **Launch at login:** only if you turn it on. macOS lists it under System Settings → General → Login Items.

## Children

The app doesn't collect information from anyone, including children under 13.

## Changes

If this policy changes, the new version will be posted here with a new date.

## Contact

Questions? Open an issue at [github.com/andrewmacheret/i5-macos-menubar/issues](https://github.com/andrewmacheret/i5-macos-menubar/issues).
