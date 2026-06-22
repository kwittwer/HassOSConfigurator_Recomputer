# Changelog

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
