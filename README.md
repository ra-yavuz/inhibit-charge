# inhibit-charge

**Park your Linux laptop battery at a target charge using `inhibit-charge`. No trickle cycling, no slow drift. AC powers the system, the battery sits idle.**

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

To check yours:

```
cat /sys/class/power_supply/BAT0/charge_behaviour
# expect to see: [auto] inhibit-charge ...
```

## Install

### Debian / Ubuntu (recommended: apt repository)

Add the [ra-yavuz Linux packages](https://ra-yavuz.github.io/apt/) apt repository, then install with `apt`. You get automatic updates via `apt upgrade`.

```bash
# 1. Trust the signing key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://ra-yavuz.github.io/apt/pubkey.gpg \
  | sudo tee /etc/apt/keyrings/ra-yavuz.gpg > /dev/null

# 2. Add the apt source
echo "deb [signed-by=/etc/apt/keyrings/ra-yavuz.gpg] https://ra-yavuz.github.io/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/ra-yavuz.list

# 3. Install
sudo apt update
sudo apt install inhibit-charge
sudo usermod -aG inhibit-charge $USER     # log out + back in (or run `newgrp inhibit-charge`)
inhibit-charge status
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

```
git clone https://github.com/ra-yavuz/inhibit-charge.git
cd inhibit-charge
sudo make install
sudo systemctl enable --now inhibit-charged
inhibit-charge status
```

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
