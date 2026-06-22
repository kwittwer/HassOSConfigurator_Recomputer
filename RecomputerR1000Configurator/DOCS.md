# reComputer R1000 Configurator

## What this add-on does

This add-on runs automatically at host boot, checks and repairs the required reComputer R1000 settings once, and then stays active in a lightweight idle loop.

This version adds a board profile selector in the add-on UI so you can choose between reComputer R1000 v1.0 and v1.1 behavior.

Additionally, the startup verification logs:

- the current content of `config.txt` (with truncation)
- a tree dump of `/data`
- a tree dump of `/device-tree` (if present)

### Managed areas

- RS485 boot configuration in `/mnt/boot/config.txt`
- RS485 UART device availability (`/dev/ttyAMA2`, `/dev/ttyAMA3`, `/dev/ttyAMA5`)
- USER LED sysfs paths when available (`/sys/class/leds/led-red`, `led-green`, `led-blue`)
- USER LED GPIOs for v1.0 (`GPIO20`, `GPIO26`, `GPIO27`)
- USER LED GPIOs for v1.1 (`GPIO581`, `GPIO582`, `GPIO583`)
- Buzzer GPIOs (`GPIO21` for v1.0, `GPIO591` for v1.1)

## Configuration options

- `board_version` (list: v1_0|v1_1|auto): Select the board profile for pin/UART mapping
- `strict_profile_validation` (bool): Treat missing profile UART devices as errors in logs
- `boot_partition_override` (str): Optional manual boot partition path, for example `/dev/nvme0n1p1` or `/dev/mmcblk0p1`
- `enable_rs485` (bool): Enable RS485 checks and config repair
- `enable_recomputer_r100x_overlay` (bool): Download/compile/install and activate `reComputer-R100x` overlay automatically
- `enable_rs485_de_control` (bool): Set DE/RE GPIOs (6,17,24) to low output each cycle
- `enable_led_check` (bool): Check LED sysfs availability
- `led_self_test` (bool): Toggle RGB LEDs briefly each cycle
- `enable_buzzer_check` (bool): Check/configure buzzer GPIO591
- `buzzer_self_test` (bool): Emit a short beep each cycle
- `check_interval_sec` (int 15..3600): Legacy option, ignored by the current one-time boot repair phase

## Board profile mapping

- `v1_0`:
  - RS485 UART checks: `/dev/ttyAMA2`, `/dev/ttyAMA3`, `/dev/ttyAMA5`
  - RS485 boot overlays: `uart2`, `uart3`, `uart5`
  - Optional DE/RE control: GPIO6/GPIO17/GPIO24
  - Buzzer: GPIO21
- `v1_1`:
  - RS485 UART checks: `/dev/ttyAMA2`, `/dev/ttyAMA3`, `/dev/ttyAMA4`
  - RS485 boot overlays: `uart2`, `uart3`, `uart4`
  - DE/RE control is not auto-applied due to mapping differences
  - Buzzer: GPIO591
- `auto`:
  - Tries to detect profile from available UART/GPIO signals
  - Falls back to `v1_1` if detection is inconclusive

## v1.1 pin table

If your board revision is the v1.1 layout, the following signal names are the expected ones from the board side:

| Board label | Function |
| --- | --- |
| USER_LED_R | P05 |
| USER_LED_G | P06 |
| USER_LED_B | P07 |
| IO_Buzzer_EN | P15 |
| CM4_UART2_TXD | GPIO0 / ID_SD |
| CM4_UART2_RXD | GPIO1 / ID_SC |
| CM4_UART2_CTS | GPIO2 |
| CM4_UART2_RTS | GPIO3 |
| CM4_UART3_TXD | GPIO4 |
| CM4_UART3_RXD | GPIO5 |
| CM4_UART3_CTS | GPIO6 |
| CM4_UART3_RTS | GPIO7 |
| CM4_UART4_TXD | GPIO8 |
| CM4_UART4_RXD | GPIO9 |
| CM4_UART4_CTS | GPIO10 |
| CM4_UART4_RTS | GPIO11 |

For software, the important part is the real GPIO signal behind the label. If the label is correct but the electrical net is different, the add-on will still show the entity as unavailable.

## Notes

- This add-on targets reComputer R1000 with CM4 and supports both v1.0 and v1.1 profiles.
- UART overlay changes require a host reboot to become active.
- If `enable_recomputer_r100x_overlay` is enabled, the add-on installs `reComputer-R100x.dtbo` to `/boot/overlays` and enables the corresponding `dtoverlay=` line in `config.txt`.
- With `enable_recomputer_r100x_overlay=true`, the add-on removes standalone `dtoverlay=uartX,ctsrts` lines to avoid pin conflicts with the overlay-managed I2C/GPIO expander.
- The add-on uses a vendored copy of Seeed's `reComputer-R100x-overlay.dts` shipped in the image, so overlay installation no longer depends on external download access.
- The image also ships a precompiled `reComputer-R100x.dtbo`, so normal runtime operation does not require `dtc`.
- RS485 120R termination resistors are hardware-level and are not managed by this add-on.
- `devicetree: true` is enabled so `/device-tree` can be logged for diagnostics.
- LED runtime control first tries the legacy sysfs LED paths and only falls back to GPIO control if those paths are missing.

## Home Assistant integration

- This add-on no longer includes MQTT runtime publishing.
- It focuses on boot configuration repair and hardware readiness checks for RS485, LEDs, and buzzer.

## How to verify

1. Set `board_version` to `v1_1` and restart the add-on.
2. Open the add-on log and check for `Active board profile: v1_1`.
3. Verify that LEDs and buzzer are reported as available in the add-on log.
4. If a hardware check fails, inspect the add-on log for missing GPIO or sysfs access warnings.

## Troubleshooting boot partition selection

- If both eMMC and NVMe are present, automatic partition detection can select the wrong `config.txt`.
- Set `boot_partition_override` to the active boot partition explicitly.
- Typical values on your hardware are `/dev/nvme0n1p1` or `/dev/mmcblk0p1`.

## Rollback

1. Stop the add-on.
2. Remove the lines added to `/mnt/boot/config.txt` if you no longer need RS485 overlays.
3. Uninstall the add-on.
