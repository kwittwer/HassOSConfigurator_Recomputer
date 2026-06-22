# reComputer R1000 Configurator

This add-on verifies and repairs reComputer R1000 specific settings at startup.

Focus areas:

- RS485 UART overlays and availability checks
- LED availability checks for led-red/led-green/led-blue
- Buzzer v1.1 readiness on GPIO591

The add-on remains running in an idle loop after startup checks.

## Home Assistant Copy Block (ohne MQTT)

Den folgenden Block kannst du direkt in deine Home Assistant Konfiguration uebernehmen (z. B. per packages oder in configuration.yaml mit den passenden Includes).

```yaml
shell_command:
  recomputer_sysfs_init: >
    sh -c '
    mount -o remount,rw /sys 2>/dev/null || true;
    [ -w /sys/class/leds/led-red/trigger ] && echo none > /sys/class/leds/led-red/trigger || true;
    [ -w /sys/class/leds/led-green/trigger ] && echo none > /sys/class/leds/led-green/trigger || true;
    [ -w /sys/class/leds/led-blue/trigger ] && echo none > /sys/class/leds/led-blue/trigger || true;
    [ -d /sys/class/gpio/gpio591 ] || echo 591 > /sys/class/gpio/export 2>/dev/null || true;
    [ -w /sys/class/gpio/gpio591/direction ] && echo out > /sys/class/gpio/gpio591/direction || true;
    [ -w /sys/class/gpio/gpio591/value ] && echo 0 > /sys/class/gpio/gpio591/value || true
    '

automation:
  - alias: reComputer Sysfs Init
    trigger:
      - platform: homeassistant
        event: start
    action:
      - action: shell_command.recomputer_sysfs_init

command_line:
  - switch:
      name: Gruene LED
      unique_id: green_led_switch
      command_on: "sh -c 'echo none > /sys/class/leds/led-green/trigger 2>/dev/null; echo 1 > /sys/class/leds/led-green/brightness'"
      command_off: "sh -c 'echo none > /sys/class/leds/led-green/trigger 2>/dev/null; echo 0 > /sys/class/leds/led-green/brightness'"
      command_state: "cat /sys/class/leds/led-green/brightness"
      value_template: "{{ value | trim == '1' }}"
      icon: mdi:led-on

  - switch:
      name: Rote LED
      unique_id: red_led_switch
      command_on: "sh -c 'echo none > /sys/class/leds/led-red/trigger 2>/dev/null; echo 1 > /sys/class/leds/led-red/brightness'"
      command_off: "sh -c 'echo none > /sys/class/leds/led-red/trigger 2>/dev/null; echo 0 > /sys/class/leds/led-red/brightness'"
      command_state: "cat /sys/class/leds/led-red/brightness"
      value_template: "{{ value | trim == '1' }}"
      icon: mdi:led-on

  - switch:
      name: Blaue LED
      unique_id: blue_led_switch
      command_on: "sh -c 'echo none > /sys/class/leds/led-blue/trigger 2>/dev/null; echo 1 > /sys/class/leds/led-blue/brightness'"
      command_off: "sh -c 'echo none > /sys/class/leds/led-blue/trigger 2>/dev/null; echo 0 > /sys/class/leds/led-blue/brightness'"
      command_state: "cat /sys/class/leds/led-blue/brightness"
      value_template: "{{ value | trim == '1' }}"
      icon: mdi:led-on

  - switch:
      name: Buzzer
      unique_id: recomputer_buzzer_switch
      command_on: "sh -c 'echo 1 > /sys/class/gpio/gpio591/value'"
      command_off: "sh -c 'echo 0 > /sys/class/gpio/gpio591/value'"
      command_state: "cat /sys/class/gpio/gpio591/value"
      value_template: "{{ value | trim == '1' }}"
      icon: mdi:bullhorn-outline
```

Hinweis: Der Buzzer-Pfad oben ist fuer v1.1 (GPIO591). Bei v1.0 stattdessen GPIO21 verwenden.
