# This phone's engine

DSH runs on this phone (this phone's engine); chats, workspaces and plugins are kept on it. This build has no remote hosts.

## Running in the background on iPhone

The local engine continues after leaving the app only while the system actually allows background execution. A playing, unsuspended picture-in-picture pet and an accepted continued-processing task are independent sources; ending one must not clear the other. An enabled switch, downloaded assets or a previously visible PiP does not prove current execution permission.

Pet PiP is off by default and is not a prerequisite for phone control or pet selection; native phone tasks request system continued execution directly. If you explicitly enable PiP on the phone-control page and choose to keep it after tasks, it can also support ordinary local chats. Start a real PiP from the foreground before switching apps. If PiP closes, pauses, the device locks or audio is interrupted, and no other system execution grant remains, the engine pauses at its next tool boundary. iOS can still suspend or terminate the app; permanent uptime is not promised.

PiP does not approve tools, disable safe mode or resume a phone task you manually paused. Return to the app for confirmations; restoring PiP does not approve a previous request. An engine on a remote host does not depend on the iPhone's PiP.

## Linux and Python on iPhone

<!-- nav: commonSettings,hubSettingsEngine -->
`Settings › Local engine` · [Open](dshgo://open/engine)

On iPhone, find the **Linux environment** section on that page.

Install the optional environment, then restart the local engine. It uses Alpine. Installing the environment does not also install Python, git or rg. Commands have a different available set when Linux is missing or paused; check its actual status first.

You can explicitly ask a local chat to install Python and pip:

```sh
apk add python3 py3-pip
python3 --version
python3 -m pip --version
```

Installing packages changes the Linux system and needs approval for that system write. Workspace-write permission does not replace it. Inspect the actual download, installation or execution error; do not reset, uninstall or change pairing settings to address a missing package. The Linux environment does not grant arbitrary access to other iOS apps.

## This phone's engine

<!-- nav: commonSettings,hubSettingsEngine -->
`Settings › Local engine` · [Open](dshgo://open/engine)

- **Start**, **Stop**, **Restart**: stopping asks first; both stopping and restarting interrupt active chats.
- If the engine fails to start, the page shows the cause and ways to fix it, such as retrying, **Start in Safe mode** or viewing logs.
- **Start when DSH Go opens**: on by default. As long as DSH is installed on this phone, opening the app starts it. Turn it off if you don't need that.
- **Automatic Safe mode**: on by default. After two failed starts in a row, starts without plugins.
- **Start in Safe mode**: enter Safe mode by hand. Once fixed, tap **Return to normal mode**. Entering and leaving both restart the engine.
- **Logs**: the engine's live output.
- **Background running** and **Diagnostics**: see [FAQ](11-faq.md).

## Updates and installed tools

Normal engine updates replace only app-managed engine components, without rebuilding your Linux system. Apt tools such as gh, npm global packages in their default location, Python/pip packages, settings and workspaces stay. Bundled DSH, Node, pnpm, the bridge and their dedicated directories remain app-managed; do not install your own software there. A Node version change may still require rebuilding third-party native extensions: preserving files does not guarantee extension compatibility.

Older runtimes are adopted after checking the architecture, Ubuntu version and Python. If compatibility cannot be confirmed, the update manifest is invalid, or a leftover process has not stopped, the update stops with an explanation. It never automatically wipes or rebuilds the environment. Retry an interrupted installation; do not delete recovery directories by hand.

Before changing the base system, make a full backup. Diagnostics bundles and exported chat logs are not environment backups. A complete backup must be taken with the engine stopped, include Linux files, permissions, symlinks, package databases and the home directory, be stored outside the runtime, and have a checked read/restore procedure. The app does not currently offer one-click full environment backup/restore. On a compatibility warning, keep the environment intact and contact the maintainer for help with offline export; do not reset or uninstall the app. Keeping the original environment is not an independent backup: clearing app data or uninstalling still loses it.

## Reset the runtime

<!-- nav: commonSettings,hubSettingsEngine,phoneEngineReset -->
`Settings › Local engine › Reset runtime`

Deletes data on this phone and reinstalls the runtime, to fix a runtime that won't start. In the dialog:

- **Keep interface settings and skills**: on by default.
- **Keep installed plugins and settings**: off by default.

With the defaults, chats, workspaces, plugins and settings are deleted, including custom model providers; the DeepSeek key saved in the app is filled back in. Anything else in the home folder (`/root`) goes too, including files in your workspaces, `AGENTS.md` and data that plugins store themselves, such as memories. The dialog spells out what will go; tap **Delete and reset** and the app reinstalls the runtime. A reset can't be undone, so export chats you need first with `/export` or **Export chat log** in All features.

## Uninstall the runtime

<!-- nav: commonSettings,hubSettingsEngine,localEnvUninstall -->
`Settings › Local engine › Uninstall runtime`

Frees up storage. Chats, workspaces, plugins, settings, interface settings and skills on this phone are all deleted, and nothing is reinstalled. To use this phone's engine again, tap **Install runtime** on the same page. If you only need a break, stop the engine and turn off **Start when DSH Go opens**.
