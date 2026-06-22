# reComputer R1000 Configurator

## What this add-on does
This add-on runs automatically at host boot and periodically checks if required reComputer R1000 settings still exist. If not, it restores them.

### Managed areas
- RS485 boot configuration in `/mnt/boot/config.txt`
- RS485 UART device availability (`/dev/ttyAMA2`, `/dev/ttyAMA3`, `/dev/ttyAMA5`)
- USER LED interfaces (`/sys/class/leds/led-red`, `led-green`, `led-blue`)
- Buzzer interface for reComputer R1000 v1.1 (`/sys/class/gpio/gpio591`)

## Configuration options
- `enable_rs485` (bool): Enable RS485 checks and config repair
- `enable_rs485_de_control` (bool): Set DE/RE GPIOs (6,17,24) to low output each cycle
- `enable_led_check` (bool): Check LED sysfs availability
- `led_self_test` (bool): Toggle RGB LEDs briefly each cycle
- `enable_buzzer_check` (bool): Check/configure buzzer GPIO591
- `buzzer_self_test` (bool): Emit a short beep each cycle
- `check_interval_sec` (int 15..3600): Verification interval

## Notes
- This add-on targets reComputer R1000 with CM4, especially v1.1 buzzer wiring.
- UART overlay changes require a host reboot to become active.
- RS485 120R termination resistors are hardware-level and are not managed by this add-on.

## Rollback
1. Stop the add-on.
2. Remove the lines added to `/mnt/boot/config.txt` if you no longer need RS485 overlays.
3. Uninstall the add-on.
