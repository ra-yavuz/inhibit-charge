# inhibit-charge

**Park your Linux laptop battery at a target charge using `inhibit-charge`. No trickle cycling, no slow drift. AC powers the system, the battery sits idle.**

## Quick install (Debian / Ubuntu)

```bash
curl -fsSL https://raw.githubusercontent.com/ra-yavuz/inhibit-charge/main/scripts/get.sh | sudo bash
```

Adds the [signed apt repository](https://ra-yavuz.github.io/apt/), installs the package, adds you to the `inhibit-charge` group. Future upgrades: `sudo apt upgrade`. Full removal: `sudo apt purge inhibit-charge`. Other install paths (manual apt setup, single `.deb`, from source) are documented further down in the [Install](#install) section.

> ## Disclaimer / no warranty
>
> This software writes to your laptop's battery management interface (`/sys/class/power_supply/BAT*/charge_behaviour` and the charge thresholds). It is provided **as is, without warranty of any kind**, express or implied, including but not limited to merchantability, fitness for a particular purpose, and noninfringement.
>
> By installing or running this software you accept that:
>
> - You alone are responsible for any damage to your battery, hardware, data, or system.
> - The author(s) and contributors are **not liable** for any harm, data loss, hardware failure, fire, voided warranty, or other damages, however caused.
> - Battery firmware and kernel drivers vary widely between vendors, models, and firmware revisions. Behaviour on your specific device may differ from what is described here.
> - Long-term parking of a lithium-ion battery at a fixed state of charge has tradeoffs (calendar aging vs. cycle aging) that depend on your battery chemistry, temperature, and usage. Read the manufacturer's guidance for your laptop before relying on this tool.
>
> If you do not accept these terms, do not install or run this software.
>
> Full legal license: see [`LICENSE`](LICENSE) (MIT).

Most Linux battery tools (TLP, GNOME, KDE, framework-tool) cap charging with start/end thresholds. That stops the battery at, say, 60% but the cell still cycles: it self-discharges to the start threshold, the charger tops it back up, and the loop repeats every few hours. Each of those mini-cycles wears the battery.

`inhibit-charge` does something thresholds can't. It uses the kernel's `charge_behaviour=inhibit-charge` mode to **hold the battery exactly at the target indefinitely**, while the laptop runs off AC. When you unplug, it switches back to `auto` so the battery discharges normally.

## Two modes

- **`home`** (default, target 60%). Plugged in: park at 60%. Unplugged: discharge.
- **`travel`**. Charge to 100% before you leave the house.

```
$ inhibit-charge status
Mode:       home (target 60%)
Battery:    60% (plugged in)
Behaviour:  inhibit-charge
Thresholds: 54% .. 60%
Supplies:   bat=/sys/class/power_supply/BAT0 ac=/sys/class/power_supply/AC

$ inhibit-charge travel
Switched to travel mode (charge to 100%).

$ inhibit-charge home 70
Switched to home mode (park at 70%).
```

## Optional: terminal greeting

This is **UI candy for the user**: the current battery state printed at the top of every new interactive shell. Open a new terminal tab, see your battery state. It is **not** a system MOTD, not a login banner, not PAM, not headless-server territory. It is a simple snippet sourced by every interactive shell.

Disabled by default. To toggle (no sudo needed if you are in the `inhibit-charge` group):

```
$ inhibit-charge motd
Greeting enabled. The current battery state will be shown at the top
of every new interactive shell (terminal tabs, SSH, console).

$ inhibit-charge motd off
Greeting disabled.

$ inhibit-charge motd status
Greeting: enabled (every new interactive shell).
```

How it works: the package ships `/etc/profile.d/50-inhibit-charge.sh`, which is sourced by every interactive shell on Debian/Ubuntu. The script short-circuits unless `/var/lib/inhibit-charge/motd-enabled` exists, so the default install is silent. The toggle just creates or removes that flag file. Both files are owned by the package, so `apt purge inhibit-charge` removes them cleanly.

The greeting line is one line:

```
inhibit-charge: home mode, parked at 60%, currently 60% (plugged in).
```

If you want a battery line at SSH login (where PAM/MOTD applies, which is mostly relevant for headless servers), this is not the right tool. This is intentional: laptops are the target audience, and "terminal opens" is what laptop users actually do.

## Hardware support

Requires Linux **kernel ≥ 5.17** and a driver that exposes `/sys/class/power_supply/BAT*/charge_behaviour` with `inhibit-charge` listed. The daemon refuses to start on unsupported hardware with a clear error.

| Tier | Hardware | Driver | Status |
|---|---|---|---|
| 1 | ThinkPad (most models since X220-ish) | `thinkpad_acpi` | works |
| 1 | Chromebooks / ChromeOS-EC laptops | `cros_ec` | works |
| 2 | Framework laptops | `framework_laptop` | works on recent EC firmware |
| 2 | System76 laptops | `system76_acpi` | varies by model |
| 2 | Some ASUS / IdeaPad | `asus_wmi`, vendor drivers | varies |
| 3 | Most Dell, HP, MSI, Razer | (no `inhibit-charge` exposed) | not supported, use TLP for thresholds |

To check yours, after install:

```
inhibit-charge check
```

This runs the same compatibility library that the installer and daemon use. It prints OK on supported hardware, or a clear "not supported" message with a TLP recommendation otherwise. Without the package installed, the same answer comes from:

```
cat /sys/class/power_supply/BAT0/charge_behaviour
# expect to see: [auto] inhibit-charge ...
```

## Install

### Debian / Ubuntu (recommended: apt repository)

Add the [ra-yavuz Linux packages](https://ra-yavuz.github.io/apt/) apt repository and install in one shot. You get automatic updates via `apt upgrade`, signed packages, and clean removal via `apt purge`.

```bash
curl -fsSL https://raw.githubusercontent.com/ra-yavuz/inhibit-charge/main/scripts/get.sh \
  | sudo bash
```

Prefer to read the script first (advisable for any `curl | bash`)? Same end result, two commands:

```bash
curl -fsSL https://raw.githubusercontent.com/ra-yavuz/inhibit-charge/main/scripts/get.sh -o get.sh
less get.sh
sudo bash get.sh
```

What the script does, all idempotent: installs the GPG keyring at `/etc/apt/keyrings/ra-yavuz.gpg`, adds `/etc/apt/sources.list.d/ra-yavuz.list` pointing at `https://ra-yavuz.github.io/apt`, runs `apt update`, installs `inhibit-charge`, and adds the invoking user to the `inhibit-charge` group.

After install, you need a fresh shell session before the CLI works as your user (Linux freezes group lists at login, so a new terminal tab in the same session is not enough). Either run `newgrp inhibit-charge` in your terminal, log out and back in, or reboot. Then:

```bash
inhibit-charge status
```

If you'd rather wire up the apt source by hand, the equivalent steps are:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://ra-yavuz.github.io/apt/pubkey.gpg \
  | sudo tee /etc/apt/keyrings/ra-yavuz.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/ra-yavuz.gpg] https://ra-yavuz.github.io/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/ra-yavuz.list
sudo apt update
sudo apt install inhibit-charge
sudo usermod -aG inhibit-charge $USER
```

### Debian / Ubuntu (single .deb from GitHub Releases)

If you don't want to add the apt source, grab the latest `.deb` directly. No automatic updates.

```bash
wget https://github.com/ra-yavuz/inhibit-charge/releases/latest/download/inhibit-charge_0.1.0-1_all.deb
sudo apt install ./inhibit-charge_0.1.0-1_all.deb
sudo usermod -aG inhibit-charge $USER
inhibit-charge status
```

### From source (any distro with systemd + bash)

The repo includes a self-contained installer. It creates the `inhibit-charge` system group, installs the files into `/usr/`, the systemd unit into `/lib/systemd/system/`, and seeds `/var/lib/inhibit-charge/` with the default `home` mode at 60%. Idempotent, safe to re-run.

```bash
git clone https://github.com/ra-yavuz/inhibit-charge.git
cd inhibit-charge
sudo bash install.sh                  # install (or upgrade) in place
# After the install adds you to the inhibit-charge group, your existing
# login session does NOT yet have it. You need a fresh shell session: a
# new terminal tab in the same session is not enough (Linux freezes
# group lists at login). Either run `newgrp inhibit-charge` in your
# terminal, or log out and back in. Then:
inhibit-charge status
```

Other subcommands: `sudo bash install.sh uninstall` (remove files, keep state), `sudo bash install.sh purge` (remove everything including state and group), `sudo bash install.sh verify` (print install state).

## How it works

A small daemon (`/usr/lib/inhibit-charge/inhibit-charged`, ~150 lines of bash) watches the kernel `power_supply` subsystem via `udevadm monitor` and reacts to plug/unplug, capacity, and CLI events instantly. The CLI (`inhibit-charge`) writes the desired state to `/var/lib/inhibit-charge/{mode,target}` and signals the daemon over SIGHUP, so changes apply with zero polling delay. A slow 5-minute fallback timer handles slow self-discharge while parked.

The recharge band (the hysteresis below the target where the daemon tops the battery back up) scales with the target: `max(2, target/10)` percentage points. So target=60 parks in the band 54..60, target=25 parks in 23..25. Hardware-level start/end thresholds are also set to the same band as a safety net: if the daemon ever dies, firmware still holds the battery at the target.

## Versus TLP, GNOME, KDE

These all expose **start/end thresholds**, which the kernel implements as "stop charging at end, resume at start." That's a cycling band, not a hold. `inhibit-charge` is a third state above thresholds: charging is actively blocked while AC drives the system. This package layers a tiny daemon on top of that kernel feature so it switches automatically with plug state, and exposes a two-mode UX (`home` / `travel`) over it.

You can run TLP and inhibit-charge together. TLP's threshold settings still apply when inhibit-charge isn't actively parking (e.g. travel mode), and inhibit-charge takes over when it is.

## Status, logs, troubleshooting

```
sudo systemctl status inhibit-charged
sudo journalctl -u inhibit-charged -f
inhibit-charge status
```

If `inhibit-charge status` shows `Behaviour: (not supported)`, your hardware doesn't expose `inhibit-charge` and this tool can't help, sorry. TLP's thresholds will still cap charging.

## License

MIT. See `LICENSE`.

## Contributing

Issues and PRs welcome. Please run `make lint` (shellcheck) before submitting.
