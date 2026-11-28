# Troubleshooting

## Messages won't send, or no reply comes

Check the host status at the bottom of the chat list.

- **This phone**: open the engine page and check its status and **Logs**. Not installed, stopped and failed to start are different cases; follow the page. When a start fails, the failure card links to the logs and a diagnostics bundle.
- If no model is set up, **Choose model** offers to enter an API key or add a provider.

Reset and uninstall both delete data on this phone; you rarely need them to fix a problem.

<!-- nav: commonSettings,phoneEngineTitle -->
`Settings › Local engine` · [Open](dshgo://open/engine)

This edition removes the Diagnostics page, diagnostic exports and automatic failure analysis. Essential local error capture and engine logs remain; check status and logs on the engine page.

### Input-method or keyboard problems

After reproducing the problem, use **Capture recent events** under **System input-method diagnostics**, read the native prompt and confirm it yourself. It only reuses an already selected and connected Shizuku, Sui, wireless-debugging or Root channel; it does not request permissions, open a background screen or operate an editor. With no channel available, **Phone-control permissions (optional)** lets you choose whether to configure one.

A one-time bounded read of existing fixed-tag system logs retains up to 64 known show/hide requests or input-connection-closed events emitted by this app process from the last two minutes. Typed text, candidates and raw log lines are not exported. Android 12 and some vendor systems may have no matching records; zero events and failures do not prove that the keyboard is healthy. There is no continuous monitoring. Backgrounding the app, leaving Diagnostics or clearing cancels the request. Switching focus in multi-window mode while Diagnostics remains visible does not revoke the one short read already approved.

Results stay in app memory. Only **Let the AI read diagnostics** or a manual bundle export includes them; automatic snapshots do not. Manual AI reports and automatic environment snapshots each atomically replace their own fixed file; neither overwrites the other. Clear the in-memory evidence whenever you want, or restart the app. Clearing cannot retract files already generated or shared.

## The engine stops in the background, or notifications don't arrive

<!-- nav: commonSettings,phoneEngineKeepAlive -->
`Settings › Background running` · [Open](dshgo://open/background)

Android: follow the guide to turn off battery optimization, keep the "engine running" notification, and lock the app in Recents. After system reclamation of the whole app, a local engine with saved launch options requests restoration. A manual stop is not revived, and launches with temporary environment overrides do not restore automatically. This restarts the engine, not interrupted commands or phone actions. Vendor restrictions still apply.

iOS: this page offers separate audio and location protection switches, both off by default. They are used only while a local task is running in the background, and released when the task ends, the engine stops or the switch is turned off. Audio protection plays silence, uses more battery and yields to recording, calls or other audio use. Location protection needs Always location access and uses extra power and location permissions, but does not store coordinates. If access is denied, this page links to system settings.

The iOS 26 system continued task remains the default path; the system can refuse, cancel or expire it. Enhanced protection is also best-effort, not unlimited background execution or survival after force quit. Keep long tasks in the foreground or use a remote host when reliable execution matters.

For notifications, also turn on the alerts you want in the app's **Notifications** and allow Agentello notifications in system settings.

## The engine keeps failing to start

**Automatic Safe mode** on the local engine page is on by default: after two failed starts in a row, the engine starts without plugins. You can also tap **Start in Safe mode** on the same page. Your chats are safe in Safe mode; fix the configuration, then tap **Return to normal mode**. Web settings changed in Safe mode aren't kept.

Direct local engine launch is off by default; you turn it on under Developer options. Once it is on, on a phone where a direct start fails (Android 16 blocks it, for one), it switches to compatible launch on its own: that doesn't count as a failed start and doesn't lead to Safe mode. It keeps using compatible launch until an app update brings a new runtime, and **Diagnostics** shows **Direct launch failed**. To try again, stop the local engine, then turn on **Direct local engine launch** under **Developer options** on the Diagnostics page.

After an upgrade from an earlier version, the first direct start tidies your plugin files once; the engine shows **Tidying plugin files** meanwhile. If the phone is short of space or the tidy-up doesn't finish, that start uses compatible launch, **Fallback reason** on the **Diagnostics** page says why, and the next start carries on. No files are lost.

**tawcroot fast launch** is also under **Developer options**. It defaults to on for compatible Android 10+ devices if you have not picked a launch mode. Only one of it and direct launch can be on. With it on, tawcroot runs the local engine: it starts about three times faster, and package installs and apt get faster too. If it can't start, the app switches to compatible launch on its own. To try again, stop the local engine and turn it back on. The first start after you turn it off first turns the hard links it made into ordinary files, and the engine shows **Tidying plugin files**. If the phone is short on space, that start fails and says how much is missing; free up space or turn tawcroot back on. No files are lost.

## The app can chat, but headless reports MISSING_CREDENTIAL

`dsh --profile headless` starts a separate one-shot task. Its default profile disables the interactive credential store, authorization and DeepSeek account services, so it does not automatically use API keys or account sign-ins saved in the app. A working chat in the app does not mean this command has credentials configured.

The default DeepSeek official API route needs `DEEPSEEK_API_KEY`. Supply it in the process environment that launches the command, or set your own API key as `DEEPSEEK_API_KEY=...` in the launch directory's `.env` or `$DSH_HOME/.env`. These are read in order: process environment, launch directory's `.env`, then `$DSH_HOME/.env`. An exported empty variable also shadows the `.env` fallback; unset that empty variable before using a file instead. Keep real keys out of chats, issue reports and source control.

DeepSeek account sign-in and an official API key are different credentials. An account sign-in token cannot be used as `DEEPSEEK_API_KEY`. You can keep using the account in the app, or configure an API key separately for headless.

Adding the app's sign-in patch alone does not enable the services that headless disables by default. Custom profiles may use different configurations; follow the actual configuration.

## Phone control doesn't work

The top of the phone control page says what's missing:

- The switch is off, or the engine hasn't started.
- DSH isn't installed on this phone: install it first.
- Safe mode is on: return to normal mode.
- Accessibility is off: tap **Turn on**. For a sideloaded app, allow restricted settings first.

If a task stopped midway: turning the screen off, locking the phone, or DSH making no new move for 3 minutes ends it. See [Phone control](04-phone-control.md).

## The floating bar is in the way

Hold and drag the bar out of the way (left, middle or right, at any height), or drag it off the screen's edge to shrink it to a ball; tapping the dot at its left end (or **Shrink to a ball** in its card) does that too. **Collapse when idle** is on by default, so an idle capsule shrinks to a ball by itself; an idle ball fades and slides half out of sight over the edge. Lower **Idle opacity** to fade it more.

## A plugin is installed but doesn't show up

Check that the plugin is enabled, and restart the engine if asked. A plugin's native UI needs the dsh-go bridge on the host: this phone's engine has it built in. A display place may also be turned off in the plugin's details. Plugin panels without a native UI appear in the Plugins group of All features, opening in the app or as Web entries. See [Plugins](08-plugins.md).

## What the app sends

<!-- nav: commonSettings,hubPrivacy -->
`Settings › Privacy and sharing`

This fork removes the app’s own anonymous usage statistics. It no longer collects or reports feature counts, random installation IDs or device information for those statistics. The switch, upgrade notice and first-run welcome page are removed; first run goes straight to installing the local runtime. The bundled engine also removes the contributor that attaches complete session logs to DeepSeek requests, together with its native and web settings.

Model requests, explicit sharing and third-party SDK data handling follow their respective feature descriptions.

This fork hides in-app update controls and disables launch-time update checks; install new locally built APKs manually.

## Local text recognition and Google ML Kit

<!-- nav: commonSettings,hubSettingsPhoneControl -->
`Settings › Phone control`

Phone control uses bundled Google ML Kit Chinese text recognition (`com.google.mlkit:text-recognition-chinese:16.0.1`), enabled by default; expand **More settings** on that page and turn it off separately with **Text recognition**. Recognition runs on this device; screenshots and recognized text are not sent to Google. Google’s SDK collects usage statistics such as device model, app version and processing time. This SDK’s statistics are separate from the removed app usage reporting.

Screenshots and recognized text may be sent to your configured model as part of phone control. While off, recognition requests do not trigger SDK loading or initialization. Turning local recognition off prevents new recognition; work already started may still finish. It does not uninstall the SDK, clear previously accumulated SDK statistics, or guarantee that old SDK statistics stop being sent. A device that has never initialized the SDK and a device previously used with recognition enabled have different histories.

See [Google ML Kit terms](https://developers.google.com/ml-kit/terms) and [Android SDK data disclosure](https://developers.google.com/ml-kit/android-data-disclosure). These SDK terms are distinct from the Apache 2.0 license attached to example code in the documentation.

## The guide doesn't match what I see

Check the app version under **Version** in Settings and compare it with the version in the [guide index](../README.md). The app is always right.
