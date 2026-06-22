# Changelog

## 0.6.2

- Added automatic MQTT reconnect fallback without credentials when auth is rejected
- Added `mqtt_auto_anonymous_fallback` option for controlling this behavior
- Added clearer MQTT connection/auth failure logs

## 0.6.1

- Added MQTT binary sensor publishing and discovery for GPIO25 power supply status
- Added generated Home Assistant MQTT `binary_sensor` block for `Versorgungsspannung ReComputer`

## 0.5.0

- Replaced REST control approach with MQTT bridge control for red/green/blue LED and buzzer
- Added generated MQTT `configuration.yaml` copy block at `/data/homeassistant_config_snippet.yaml`
- Added MQTT broker, topic, and discovery options

## 0.4.2

- Added automatic repair for malformed concatenated lines like `gpu_mem=16dtoverlay=uart2,ctsrts`
- Splits embedded RS485 overlay tokens into dedicated lines before validation
- Keeps duplicate cleanup so repeated `dtoverlay=uartX,ctsrts` entries are removed

## 0.4.1

- Fixed repeated RS485 `dtoverlay=` additions on some systems with CRLF/no-newline edge cases in `config.txt`
- Added duplicate cleanup for managed RS485 config lines before validation
- Switched managed line append to safe newline-wrapped write to avoid concatenated entries

## 0.4.0

- Added `config.txt` content dump to add-on logs each verification cycle
- Added tree dump logging for `/data` and `/device-tree` (with truncation limits)
- Enabled `devicetree: true` in add-on manifest for `/device-tree` diagnostics

## 0.3.1

- Fixed profile/partition variable contamination caused by log output on stdout
- Moved runtime log output to stderr so command substitution returns clean values
- Fixes wrong branch effects like v1.1 profile falling back to v1.0 buzzer/UART behavior

## 0.3.0

- Improved boot partition selection for systems with both eMMC and NVMe
- Added root-device based boot partition derivation from `/proc/cmdline`
- Added `boot_partition_override` option for manual partition selection
- Added UI translations for `boot_partition_override`

## 0.2.0

- Added board profile dropdown in add-on UI (`v1_0`, `v1_1`, `auto`)
- Added strict profile validation switch
- Added profile-aware RS485 mapping:
  - v1.0 uses uart2/uart3/uart5
  - v1.1 uses uart2/uart3/uart4
- Added profile-aware buzzer mapping:
  - v1.0 uses GPIO21
  - v1.1 uses GPIO591
- Added configuration translations (`en`, `de`)

## 0.1.0

- Initial release
- Boot-time and periodic verify/repair loop
- RS485 overlay enforcement (uart2/uart3/uart5)
- LED availability checks for user LEDs
- Buzzer v1.1 support via GPIO591
