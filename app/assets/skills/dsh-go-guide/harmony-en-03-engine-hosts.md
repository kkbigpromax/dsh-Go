# This phone's engine

DSH runs on this phone (this phone's engine); chats, workspaces and plugins are kept on it. This build has no remote hosts.

## This phone's engine

<!-- nav: commonSettings,hubSettingsEngine -->
`Settings › Local engine` · [Open](dshgo://open/engine)

- **Start**, **Stop**, **Restart**: stopping asks first; both stopping and restarting interrupt active chats.
- If the engine fails to start, the page shows the cause and ways to fix it, such as retrying, **Enter Safe mode**, **Restore configuration** or viewing logs.
- **Start when Agentello opens**: on by default. As long as DSH is installed on this phone, opening the app starts it, even while you use a remote host. Turn it off if you don't need that.
- **Start in Safe mode**: enter Safe mode by hand. It starts with the default configuration that comes with the app, without the plugins you installed. Your chats stay and your own configuration isn't changed, though a global patch or `.env` can still affect the start. Once fixed, tap **Return to normal mode**. If the engine has already started since the app opened, entering and leaving both reopen the app; the dialog says so.
- Safe mode never starts by itself. After several unclean exits in a row the engine won't start on its own, and the failure card offers **Restore configuration**, **Enter Safe mode** and **Retry**.
- **Logs**: the engine's live output.
- **Background running** and **Diagnostics**: see [FAQ](11-faq.md).

## Linux environment

<!-- nav: commonSettings,linuxTitle -->
`Settings › Linux environment`

Runs command-line tools such as gh and Python on this phone. This row exists only on HarmonyOS, in the Capabilities group of the settings home; it can be turned on only while the local engine runs.

- Turn on **Turn on Linux**. The first time downloads a 3.5 MB base system and installs it, which takes a minute or two; the switch shows the step it is on: downloading the base system, preparing disks, starting, installing tools. After that it starts in seconds.
- The switch is remembered: left on, Linux comes back on by itself each time the local engine starts.
- While Linux is on, the app uses roughly 100 MB more memory. Turning it off gives that back; turning it on again then needs the app reopened.
- When the page asks you to reopen the app (after you turned the switch off, including while it was getting ready), tap **Reopen app** or quit and open it yourself; then Linux can be turned on again.
- When the page says the existing Linux data can't be used any more (usually after an app update), tap **Reinstall Linux**. It deletes everything inside Linux: installed software and Python packages, files that exist only inside Linux, and accounts signed in there (such as gh); files in your chat workspaces aren't touched. It works while the switch is off or turning on failed; if Linux already started in this run of the app, turn the switch off and reopen the app first. Afterwards the switch stays off, and turning it on downloads and installs Linux again.

While it's on, `gh`, `python3`, `python`, `pip` and `pip3` run by the AI in chats on this phone's engine go to this Linux, and so do Python processes that plugins start; run anything else with `linux <command>`, for example `linux sh -c '…'`. `bash`, `git`, `rg` and `node` still run in the app's own command environment. While it's off, those commands report that the Linux environment is off; nothing is installed for you.

Commands in Linux see the chat's workspace at the same paths; when the chat's permission is **Read only**, the workspace is read-only in Linux too. Linux runs one command at a time, and `pip` is slow to start: it can take tens of seconds. Chats on remote hosts don't use this Linux.

**Network proxy** applies only to commands inside Linux. Choose a **Mode**:

- **Same as app** (default): uses the local engine's proxy when it has one, otherwise connects directly.
- **No proxy**: connects directly.
- **Manual**: enter an **HTTP proxy**, an **HTTPS proxy** (**Same as HTTP** when left empty) and **Bypass for** (NO_PROXY, comma-separated, such as `example.com,10.0.0.0/8`). Proxy addresses start with `http://` or `https://`, such as `http://127.0.0.1:7890`; `127.0.0.1` means this phone, not your computer, and a proxy app on the phone needs `http://`. Clearing both proxies goes back to **No proxy**.

Gitee, Huawei Cloud and other mirrors in China always connect directly. The proxy is saved only on this phone, and a change applies to the commands that follow.

Resetting or uninstalling the runtime doesn't delete what is installed in Linux; **Reinstall Linux** or uninstalling the app does. If it won't turn on, see [FAQ](11-faq.md).

## Reset the runtime

<!-- nav: commonSettings,hubSettingsEngine,phoneEngineReset -->
`Settings › Local engine › Reset runtime`

Deletes data on this phone and reinstalls the runtime, to fix a runtime that won't start. In the dialog:

- **Keep interface settings and skills**: on by default.
- **Keep installed plugins and settings**: off by default.

With the defaults, chats, workspaces, plugins and settings are deleted, including custom model providers. Anything else in the home folder goes too, including files in your workspaces, `AGENTS.md` and data that plugins store themselves, such as memories. Your host list, app settings and saved keys aren't affected. The dialog spells out what will go; tap **Delete and reset** and the app reopens and finishes the reset as it opens. If it still needs reopening, the engine page says so: tap **Reopen**. The local engine won't start until then. A reset can't be undone, so export chats you need first with `/export` or **Export chat log** in All features.

## Uninstall the runtime

<!-- nav: commonSettings,hubSettingsEngine,localEnvUninstall -->
`Settings › Local engine › Uninstall runtime`

Deletes the unpacked runtime and local data. Chats, workspaces, plugins, settings, interface settings and skills on this phone are all deleted, the app reopens, and nothing is reinstalled. The copy of the runtime inside the app package stays; only uninstalling the app frees it. To use this phone's engine again, tap **Install runtime** on the same page. If you only need a break, stop the engine and turn off **Start when Agentello opens**.
