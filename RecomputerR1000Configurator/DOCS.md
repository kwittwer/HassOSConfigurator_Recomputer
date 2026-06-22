# reComputer R1000 Configurator

## What this add-on does

This add-on runs automatically at host boot and periodically checks if required reComputer R1000 settings still exist. If not, it restores them.

This version adds a board profile selector in the add-on UI so you can choose between reComputer R1000 v1.0 and v1.1 behavior.

Additionally, each verification cycle now logs:

- the current content of `config.txt` (with truncation)
- a tree dump of `/data`
- a tree dump of `/device-tree` (if present)

### Managed areas

- RS485 boot configuration in `/mnt/boot/config.txt`
- RS485 UART device availability (`/dev/ttyAMA2`, `/dev/ttyAMA3`, `/dev/ttyAMA5`)
- USER LED interfaces (`/sys/class/leds/led-red`, `led-green`, `led-blue`)
- Buzzer interface for reComputer R1000 v1.1 (`/sys/class/gpio/gpio591`)

## Configuration options

- `board_version` (list: v1_0|v1_1|auto): Select the board profile for pin/UART mapping
- `strict_profile_validation` (bool): Treat missing profile UART devices as errors in logs
- `boot_partition_override` (str): Optional manual boot partition path, for example `/dev/nvme0n1p1` or `/dev/mmcblk0p1`
- `enable_rs485` (bool): Enable RS485 checks and config repair
- `enable_rs485_de_control` (bool): Set DE/RE GPIOs (6,17,24) to low output each cycle
- `enable_led_check` (bool): Check LED sysfs availability
- `led_self_test` (bool): Toggle RGB LEDs briefly each cycle
- `enable_buzzer_check` (bool): Check/configure buzzer GPIO591
- `buzzer_self_test` (bool): Emit a short beep each cycle
- `check_interval_sec` (int 15..3600): Verification interval

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

## Notes

- This add-on targets reComputer R1000 with CM4 and supports both v1.0 and v1.1 profiles.
- UART overlay changes require a host reboot to become active.
- RS485 120R termination resistors are hardware-level and are not managed by this add-on.
- `devicetree: true` is enabled so `/device-tree` can be logged for diagnostics.

## Troubleshooting boot partition selection

- If both eMMC and NVMe are present, automatic partition detection can select the wrong `config.txt`.
- Set `boot_partition_override` to the active boot partition explicitly.
- Typical values on your hardware are `/dev/nvme0n1p1` or `/dev/mmcblk0p1`.

## Rollback

1. Stop the add-on.
2. Remove the lines added to `/mnt/boot/config.txt` if you no longer need RS485 overlays.
3. Uninstall the add-on.
