#!/usr/bin/with-contenv bashio

set -u

PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

readonly WORK_DIR="/tmp/recomputer-r1000"
readonly MOUNT_POINT="${WORK_DIR}/boot"
readonly OPTIONS_FILE="/data/options.json"

REBOOT_REQUIRED=0

log() {
  local level="$1"
  shift
  echo "[${level}] $*" >&2
}

opt_bool() {
  local key="$1"
  local default_value="$2"
  if [ -f "${OPTIONS_FILE}" ]; then
    jq -r ".${key} // ${default_value}" "${OPTIONS_FILE}" 2>/dev/null
  else
    echo "${default_value}"
  fi
}

opt_int() {
  local key="$1"
  local default_value="$2"
  if [ -f "${OPTIONS_FILE}" ]; then
    jq -r ".${key} // ${default_value}" "${OPTIONS_FILE}" 2>/dev/null
  else
    echo "${default_value}"
  fi
}

opt_str() {
  local key="$1"
  local default_value="$2"
  if [ -f "${OPTIONS_FILE}" ]; then
    jq -r ".${key} // \"${default_value}\"" "${OPTIONS_FILE}" 2>/dev/null
  else
    echo "${default_value}"
  fi
}

dump_file_to_log() {
  local file_path="$1"
  local max_lines="$2"

  if [ ! -f "$file_path" ]; then
    log WARN "File dump skipped, file not found: ${file_path}"
    return 0
  fi

  log INFO "----- BEGIN FILE DUMP: ${file_path} -----"
  awk -v max_lines="$max_lines" '
    NR <= max_lines {
      print "[FILE] " $0
    }
    NR == (max_lines + 1) {
      print "[FILE] ... output truncated ..."
    }
  ' "$file_path" >&2
  log INFO "----- END FILE DUMP: ${file_path} -----"
}

dump_tree_to_log() {
  local dir_path="$1"
  local max_depth="$2"
  local max_lines="$3"

  if [ ! -e "$dir_path" ]; then
    log WARN "Tree dump skipped, path not found: ${dir_path}"
    return 0
  fi

  log INFO "----- BEGIN TREE DUMP: ${dir_path} (depth=${max_depth}) -----"
  find "$dir_path" -maxdepth "$max_depth" 2>/dev/null | sort | awk -v max_lines="$max_lines" '
    NR <= max_lines {
      print "[TREE] " $0
    }
    NR == (max_lines + 1) {
      print "[TREE] ... output truncated ..."
    }
  ' >&2
  log INFO "----- END TREE DUMP: ${dir_path} -----"
}

emit_debug_dumps() {
  local config_file="$1"

  dump_file_to_log "$config_file" 300
  dump_tree_to_log /data 4 400
  dump_tree_to_log /device-tree 4 400
}

cleanup_mount() {
  if mountpoint -q "${MOUNT_POINT}"; then
    umount "${MOUNT_POINT}" >/dev/null 2>&1 || true
  fi
}

resolve_root_device_from_cmdline() {
  local root_spec
  root_spec="$(sed -n 's/.*\broot=\([^ ]*\).*/\1/p' /proc/cmdline 2>/dev/null)"

  if [ -z "$root_spec" ]; then
    return 1
  fi

  case "$root_spec" in
    /dev/*)
      echo "$root_spec"
      return 0
      ;;
    PARTUUID=*)
      local partuuid
      partuuid="${root_spec#PARTUUID=}"
      if [ -e "/dev/disk/by-partuuid/${partuuid}" ]; then
        readlink -f "/dev/disk/by-partuuid/${partuuid}"
        return 0
      fi
      ;;
    UUID=*)
      local uuid
      uuid="${root_spec#UUID=}"
      if [ -e "/dev/disk/by-uuid/${uuid}" ]; then
        readlink -f "/dev/disk/by-uuid/${uuid}"
        return 0
      fi
      ;;
  esac

  return 1
}

derive_boot_partition_from_root_device() {
  local root_dev="$1"

  case "$root_dev" in
    /dev/nvme*n*p*)
      local base
      base="${root_dev%p*}"
      echo "${base}p1"
      return 0
      ;;
    /dev/mmcblk*p*)
      local base
      base="${root_dev%p*}"
      echo "${base}p1"
      return 0
      ;;
    /dev/sd[a-z][0-9]*|/dev/vd[a-z][0-9]*|/dev/xvd[a-z][0-9]*)
      local base
      base="${root_dev%%[0-9]*}"
      echo "${base}1"
      return 0
      ;;
  esac

  return 1
}

can_mount_boot_partition() {
  local dev="$1"

  [ -b "$dev" ] || return 1

  cleanup_mount
  if ! mount "$dev" "${MOUNT_POINT}" >/dev/null 2>&1; then
    return 1
  fi

  if [ -f "${MOUNT_POINT}/config.txt" ]; then
    return 0
  fi

  cleanup_mount
  return 1
}

find_boot_partition() {
  local override_partition="$1"

  local candidates=(
    /dev/nvme0n1p1
    /dev/mmcblk0p1
    /dev/mmcblk1p1
    /dev/sda1
    /dev/sdb1
    /dev/vda1
    /dev/xvda1
    /dev/xvda8
  )

  mkdir -p "${MOUNT_POINT}"

  if [ -n "$override_partition" ]; then
    log INFO "Boot partition override requested: ${override_partition}"
    if can_mount_boot_partition "$override_partition"; then
      echo "$override_partition"
      return 0
    fi
    log ERROR "Override partition is invalid or has no config.txt: ${override_partition}"
  fi

  local root_dev
  if root_dev="$(resolve_root_device_from_cmdline)"; then
    log INFO "Detected root device from /proc/cmdline: ${root_dev}"
    local derived_boot
    if derived_boot="$(derive_boot_partition_from_root_device "$root_dev")"; then
      if can_mount_boot_partition "$derived_boot"; then
        echo "$derived_boot"
        return 0
      fi
      log WARN "Derived boot partition from root device is not usable: ${derived_boot}"
    fi
  else
    log WARN "Could not resolve root device from /proc/cmdline"
  fi

  local dev
  for dev in "${candidates[@]}"; do
    if can_mount_boot_partition "$dev"; then
      echo "${dev}"
      return 0
    fi
  done

  return 1
}

line_exists_uncommented() {
  local file="$1"
  local expected="$2"
  awk -v needle="$expected" '
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^#/) {
        next
      }
      sub(/[[:space:]]+$/, "", line)
      if (line == needle) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

dedupe_uncommented_line() {
  local file="$1"
  local expected="$2"
  local tmp_file
  tmp_file="${file}.tmp.$$"

  awk -v needle="$expected" '
    {
      raw = $0
      line = $0
      sub(/\r$/, "", line)

      trimmed = line
      sub(/^[[:space:]]+/, "", trimmed)
      sub(/[[:space:]]+$/, "", trimmed)

      if (trimmed ~ /^#/) {
        print raw
        next
      }

      if (trimmed == needle) {
        seen++
        if (seen > 1) {
          changed = 1
          next
        }
      }

      print raw
    }
    END {
      if (changed == 1) {
        exit 10
      }
      exit 0
    }
  ' "$file" > "$tmp_file"

  local rc=$?
  if [ "$rc" -eq 10 ]; then
    mv "$tmp_file" "$file"
    log WARN "removed duplicate entries for: ${expected}"
    return 0
  fi

  rm -f "$tmp_file"
  return 0
}

ensure_config_line() {
  local file="$1"
  local expected="$2"

  dedupe_uncommented_line "$file" "$expected"

  if line_exists_uncommented "$file" "$expected"; then
    log INFO "already correct: ${expected}"
    return 0
  fi

  # Write with leading and trailing newline to avoid line concatenation
  # when config.txt has no trailing newline at EOF.
  printf '\n%s\n' "$expected" >> "$file"
  log WARN "repaired: added '${expected}' to $(basename "$file")"
  REBOOT_REQUIRED=1
}

check_rs485_devices() {
  local strict_validation="$1"
  shift

  local missing=0
  local dev
  for dev in "$@"; do
    if [ -e "$dev" ]; then
      log INFO "RS485 UART available: ${dev}"
    else
      log WARN "RS485 UART missing: ${dev}"
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ] && [ "$strict_validation" = "true" ]; then
    log ERROR "Strict profile validation is enabled and at least one RS485 UART is missing."
    return 1
  fi

  return 0
}

ensure_gpio_out_low() {
  local gpio_num="$1"

  if [ ! -d "/sys/class/gpio/gpio${gpio_num}" ]; then
    if [ -w /sys/class/gpio/export ]; then
      echo "$gpio_num" > /sys/class/gpio/export 2>/dev/null || true
      sleep 0.1
    fi
  fi

  if [ -d "/sys/class/gpio/gpio${gpio_num}" ]; then
    echo out > "/sys/class/gpio/gpio${gpio_num}/direction" 2>/dev/null || true
    echo 0 > "/sys/class/gpio/gpio${gpio_num}/value" 2>/dev/null || true
    log INFO "GPIO${gpio_num} set to output low"
    return 0
  fi

  log WARN "GPIO${gpio_num} is not accessible"
  return 1
}

check_leds() {
  local self_test="$1"
  local leds=(led-red led-green led-blue)
  local led

  for led in "${leds[@]}"; do
    if [ -e "/sys/class/leds/${led}/brightness" ]; then
      log INFO "LED available: ${led}"
    else
      log WARN "LED missing: ${led}"
    fi
  done

  if [ "$self_test" != "true" ]; then
    return 0
  fi

  log INFO "LED self-test enabled"
  for led in "${leds[@]}"; do
    if [ -w "/sys/class/leds/${led}/brightness" ]; then
      echo 1 > "/sys/class/leds/${led}/brightness"
      sleep 0.15
      echo 0 > "/sys/class/leds/${led}/brightness"
      sleep 0.05
    fi
  done
}

check_buzzer_v11() {
  local self_test="$1"

  if ! ensure_gpio_out_low 591; then
    log WARN "Buzzer GPIO591 not ready"
    return 1
  fi

  if [ "$self_test" = "true" ] && [ -w /sys/class/gpio/gpio591/value ]; then
    log INFO "Buzzer self-test enabled"
    echo 1 > /sys/class/gpio/gpio591/value
    sleep 0.2
    echo 0 > /sys/class/gpio/gpio591/value
  fi

  return 0
}

check_buzzer_v10() {
  local self_test="$1"

  if ! ensure_gpio_out_low 21; then
    log WARN "Buzzer GPIO21 not ready"
    return 1
  fi

  if [ "$self_test" = "true" ] && [ -w /sys/class/gpio/gpio21/value ]; then
    log INFO "Buzzer self-test enabled"
    echo 1 > /sys/class/gpio/gpio21/value
    sleep 0.2
    echo 0 > /sys/class/gpio/gpio21/value
  fi

  return 0
}

resolve_board_profile() {
  local configured_profile="$1"

  case "$configured_profile" in
    v1_0|v1_1)
      echo "$configured_profile"
      return 0
      ;;
    auto)
      if [ -e /dev/ttyAMA4 ] && [ ! -e /dev/ttyAMA5 ]; then
        log INFO "Auto profile detection: selecting v1_1 (ttyAMA4 present, ttyAMA5 missing)"
        echo "v1_1"
        return 0
      fi

      if [ -e /dev/ttyAMA5 ] && [ ! -e /dev/ttyAMA4 ]; then
        log INFO "Auto profile detection: selecting v1_0 (ttyAMA5 present, ttyAMA4 missing)"
        echo "v1_0"
        return 0
      fi

      if [ -d /sys/class/gpio/gpio591 ]; then
        log INFO "Auto profile detection: selecting v1_1 (GPIO591 present)"
        echo "v1_1"
        return 0
      fi

      log WARN "Auto profile detection is inconclusive; defaulting to v1_1"
      echo "v1_1"
      return 0
      ;;
    *)
      log WARN "Invalid board_version '${configured_profile}', defaulting to v1_1"
      echo "v1_1"
      return 0
      ;;
  esac
}

configure_rs485() {
  local config_file="$1"
  local enable_de_control="$2"
  local board_profile="$3"
  local strict_validation="$4"

  log INFO "RS485: verify boot configuration"

  ensure_config_line "$config_file" "enable_uart=1"
  ensure_config_line "$config_file" "dtoverlay=uart2,ctsrts"
  ensure_config_line "$config_file" "dtoverlay=uart3,ctsrts"

  if [ "$board_profile" = "v1_1" ]; then
    ensure_config_line "$config_file" "dtoverlay=uart4,ctsrts"
  else
    ensure_config_line "$config_file" "dtoverlay=uart5,ctsrts"
  fi

  if [ "$enable_de_control" = "true" ]; then
    if [ "$board_profile" = "v1_0" ]; then
      log INFO "RS485: DE/RE control enabled for v1.0 (GPIO6/GPIO17/GPIO24 -> low)"
      ensure_gpio_out_low 6
      ensure_gpio_out_low 17
      ensure_gpio_out_low 24
    else
      log WARN "RS485 DE/RE control for v1.1 is not applied automatically due to mapping differences."
    fi
  fi

  if [ "$board_profile" = "v1_1" ]; then
    check_rs485_devices "$strict_validation" /dev/ttyAMA2 /dev/ttyAMA3 /dev/ttyAMA4 || true
  else
    check_rs485_devices "$strict_validation" /dev/ttyAMA2 /dev/ttyAMA3 /dev/ttyAMA5 || true
  fi
}

run_cycle() {
  REBOOT_REQUIRED=0

  local enable_rs485
  enable_rs485="$(opt_bool enable_rs485 true)"
  local board_version
  board_version="$(opt_str board_version v1_1)"
  local strict_profile_validation
  strict_profile_validation="$(opt_bool strict_profile_validation false)"
  local boot_partition_override
  boot_partition_override="$(opt_str boot_partition_override "")"
  local enable_rs485_de_control
  enable_rs485_de_control="$(opt_bool enable_rs485_de_control false)"
  local enable_led_check
  enable_led_check="$(opt_bool enable_led_check true)"
  local led_self_test
  led_self_test="$(opt_bool led_self_test false)"
  local enable_buzzer_check
  enable_buzzer_check="$(opt_bool enable_buzzer_check true)"
  local buzzer_self_test
  buzzer_self_test="$(opt_bool buzzer_self_test false)"

  mkdir -p "${WORK_DIR}" "${MOUNT_POINT}"

  local boot_partition
  if ! boot_partition="$(find_boot_partition "$boot_partition_override")"; then
    log ERROR "No boot partition with config.txt found. Check protection mode and SYS_ADMIN/full_access permissions."
    return 1
  fi

  log INFO "Using boot partition: ${boot_partition}"

  local active_profile
  active_profile="$(resolve_board_profile "$board_version")"
  log INFO "Active board profile: ${active_profile}"

  local config_file="${MOUNT_POINT}/config.txt"

  if [ "$enable_rs485" = "true" ]; then
    configure_rs485 "$config_file" "$enable_rs485_de_control" "$active_profile" "$strict_profile_validation"
  else
    log INFO "RS485 check disabled by option"
  fi

  emit_debug_dumps "$config_file"

  cleanup_mount

  if [ "$enable_led_check" = "true" ]; then
    log INFO "LED: verify availability"
    check_leds "$led_self_test"
  else
    log INFO "LED check disabled by option"
  fi

  if [ "$enable_buzzer_check" = "true" ]; then
    if [ "$active_profile" = "v1_1" ]; then
      log INFO "Buzzer: verify v1.1 mapping via GPIO591"
      check_buzzer_v11 "$buzzer_self_test" || true
    else
      log INFO "Buzzer: verify v1.0 mapping via GPIO21"
      check_buzzer_v10 "$buzzer_self_test" || true
    fi
  else
    log INFO "Buzzer check disabled by option"
  fi

  if [ "$REBOOT_REQUIRED" -eq 1 ]; then
    log WARN "Boot config was repaired. A host reboot is required for UART overlay changes."
  else
    log INFO "No boot config changes needed."
  fi

  return 0
}

main() {
  if [ ! -f "${OPTIONS_FILE}" ]; then
    log WARN "options.json not found yet, using defaults"
  fi

  while true; do
    run_cycle || true

    local check_interval
    check_interval="$(opt_int check_interval_sec 60)"

    if ! echo "$check_interval" | grep -Eq '^[0-9]+$'; then
      check_interval=60
    fi

    if [ "$check_interval" -lt 15 ]; then
      check_interval=15
    fi

    log INFO "Next verification in ${check_interval}s"
    sleep "$check_interval"
  done
}

trap cleanup_mount EXIT
main
