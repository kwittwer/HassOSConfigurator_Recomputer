#!/usr/bin/env python3
import json
import signal
import sys
import time
import threading
from pathlib import Path

import paho.mqtt.client as mqtt

DATA_DIR = Path('/data')
OPTIONS_FILE = DATA_DIR / 'options.json'
ACTIVE_PROFILE_FILE = DATA_DIR / 'active_profile'

RUNNING = True


def read_options() -> dict:
    defaults = {
        'mqtt_host': 'core-mosquitto',
        'mqtt_port': 1883,
        'mqtt_username': '',
        'mqtt_password': '',
        'mqtt_topic_prefix': 'recomputer_r1000',
        'mqtt_discovery_prefix': 'homeassistant',
        'mqtt_enable_discovery': True,
        'mqtt_auto_anonymous_fallback': True,
    }
    try:
        loaded = json.loads(OPTIONS_FILE.read_text(encoding='utf-8'))
    except FileNotFoundError:
        loaded = {}
    except json.JSONDecodeError:
        loaded = {}

    defaults.update(loaded)
    return defaults


def read_active_profile() -> str:
    try:
        profile = ACTIVE_PROFILE_FILE.read_text(encoding='utf-8').strip()
        if profile in {'v1_0', 'v1_1'}:
            return profile
    except FileNotFoundError:
        pass
    return 'v1_1'


def device_path(device_kind: str, device_name: str) -> Path:
    if device_kind == 'led':
        return Path(f'/sys/class/leds/led-{device_name}/brightness')
    if device_kind == 'buzzer':
        if read_active_profile() == 'v1_0':
            return Path('/sys/class/gpio/gpio21/value')
        return Path('/sys/class/gpio/gpio591/value')
    if device_kind == 'sensor' and device_name == 'power_supply':
        gpio_path = Path('/sys/class/gpio/gpio25')
        if not gpio_path.exists():
            try:
                Path('/sys/class/gpio/export').write_text('25', encoding='utf-8')
            except OSError:
                pass
        direction_path = gpio_path / 'direction'
        if direction_path.exists():
            try:
                direction_path.write_text('in', encoding='utf-8')
            except OSError:
                pass
        return gpio_path / 'value'
    raise KeyError(device_kind)


def read_state(path: Path) -> tuple[bool, str]:
    if not path.exists():
        return False, 'unavailable'
    try:
        value = path.read_text(encoding='utf-8').strip()
    except OSError:
        return False, 'unavailable'
    return True, 'on' if value == '1' else 'off'


def write_state(path: Path, state: str) -> tuple[bool, str]:
    if not path.exists():
        return False, 'path_missing'
    try:
        path.write_text('1' if state == 'on' else '0', encoding='utf-8')
    except OSError as exc:
        return False, f'write_failed: {exc}'
    return True, state


def discovery_payload(topic_prefix: str, device_kind: str, device_name: str) -> tuple[str, dict]:
    base = f'{topic_prefix}/{device_kind}/{device_name}'
    object_ids = {
        ('led', 'red'): 'red_led_switch',
        ('led', 'green'): 'green_led_switch',
        ('led', 'blue'): 'blue_led_switch',
        ('buzzer', 'main'): 'recomputer_buzzer_switch',
        ('sensor', 'power_supply'): 'PS_Recomputer',
    }
    object_id = object_ids[(device_kind, device_name)]
    names = {
        ('led', 'red'): 'Rote LED',
        ('led', 'green'): 'Gruene LED',
        ('led', 'blue'): 'Blaue LED',
        ('buzzer', 'main'): 'Buzzer',
        ('sensor', 'power_supply'): 'Versorgungsspannung ReComputer',
    }
    icons = {
        ('led', 'red'): 'mdi:led-on',
        ('led', 'green'): 'mdi:led-on',
        ('led', 'blue'): 'mdi:led-on',
        ('buzzer', 'main'): 'mdi:bullhorn-outline',
        ('sensor', 'power_supply'): 'mdi:power-plug',
    }
    component = 'switch'
    if (device_kind, device_name) == ('sensor', 'power_supply'):
        component = 'binary_sensor'
    payload = {
        'name': names[(device_kind, device_name)],
        'uniq_id': object_id,
        'stat_t': f'{base}/state',
        'avty_t': f'{topic_prefix}/status',
        'stat_on': 'on',
        'stat_off': 'off',
        'pl_avail': 'online',
        'pl_not_avail': 'offline',
        'icon': icons[(device_kind, device_name)],
        'device': {
            'identifiers': ['recomputer_r1000_configurator'],
            'name': 'reComputer R1000 Configurator',
            'manufacturer': 'Seeed Studio',
            'model': 'reComputer R1000',
        },
    }
    if component == 'switch':
        payload['cmd_t'] = f'{base}/set'
        payload['pl_on'] = 'on'
        payload['pl_off'] = 'off'
    else:
        payload['dev_cla'] = 'power'
    return object_id, payload


class Bridge:
    def __init__(self, options: dict, use_auth: bool):
        self.options = options
        self.use_auth = use_auth
        self.topic_prefix = self.options['mqtt_topic_prefix']
        self.discovery_prefix = self.options['mqtt_discovery_prefix']
        self.discovery_enabled = bool(self.options['mqtt_enable_discovery'])
        self.connect_event = threading.Event()
        self.connect_rc = None
        self.client = mqtt.Client(client_id='recomputer-r1000-configurator', clean_session=True)
        username = (self.options.get('mqtt_username', '') or '').strip()
        password = self.options.get('mqtt_password', '') or ''
        if self.use_auth and username:
            self.client.username_pw_set(username, password)
        self.client.will_set(f'{self.topic_prefix}/status', payload='offline', retain=True)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message

    def connect(self):
        self.connect_event.clear()
        self.connect_rc = None
        self.client.connect(self.options['mqtt_host'], int(self.options['mqtt_port']), 60)
        self.client.loop_start()

    def wait_for_connect(self, timeout_sec: float = 8.0) -> int:
        self.connect_event.wait(timeout=timeout_sec)
        if self.connect_rc is None:
            return -1
        return int(self.connect_rc)

    def stop(self):
        self.client.publish(f'{self.topic_prefix}/status', 'offline', retain=True)
        self.client.loop_stop()
        self.client.disconnect()

    def on_connect(self, client, userdata, flags, rc):
        self.connect_rc = rc
        self.connect_event.set()
        print(f'[MQTT] Connected with rc={rc}')
        if rc != 0:
            return
        client.publish(f'{self.topic_prefix}/status', 'online', retain=True)
        self.publish_discovery()
        self.subscribe_commands()
        self.publish_all_states()

    def subscribe_commands(self):
        for device_kind, device_name in [('led', 'red'), ('led', 'green'), ('led', 'blue'), ('buzzer', 'main')]:
            command_topic = f'{self.topic_prefix}/{device_kind}/{device_name}/set'
            self.client.subscribe(command_topic)
            print(f'[MQTT] Subscribed {command_topic}')

    def publish_discovery(self):
        if not self.discovery_enabled:
            return
        for device_kind, device_name in [('led', 'red'), ('led', 'green'), ('led', 'blue'), ('buzzer', 'main'), ('sensor', 'power_supply')]:
            object_id, payload = discovery_payload(self.topic_prefix, device_kind, device_name)
            component = 'binary_sensor' if device_kind == 'sensor' else 'switch'
            discovery_topic = f'{self.discovery_prefix}/{component}/{object_id}/config'
            self.client.publish(discovery_topic, json.dumps(payload), retain=True)
            print(f'[MQTT] Discovery published {discovery_topic}')

    def publish_state(self, device_kind: str, device_name: str):
        try:
            path = device_path(device_kind, device_name)
        except KeyError:
            return
        available, state = read_state(path)
        payload = state if available else 'unavailable'
        topic = f'{self.topic_prefix}/{device_kind}/{device_name}/state'
        self.client.publish(topic, payload, retain=True)

    def publish_all_states(self):
        for device_kind, device_name in [('led', 'red'), ('led', 'green'), ('led', 'blue'), ('buzzer', 'main'), ('sensor', 'power_supply')]:
            self.publish_state(device_kind, device_name)
        self.client.publish(f'{self.topic_prefix}/profile/state', read_active_profile(), retain=True)

    def on_message(self, client, userdata, msg):
        topic_parts = msg.topic.split('/')
        if len(topic_parts) < 4:
            return
        _, device_kind, device_name, action = topic_parts[-4:]
        if action != 'set':
            return
        state = msg.payload.decode('utf-8').strip().lower()
        if state not in {'on', 'off'}:
            print(f'[MQTT] Ignoring invalid state {state!r} for {msg.topic}')
            return
        try:
            path = device_path(device_kind, device_name)
        except KeyError:
            return
        ok, result = write_state(path, state)
        if not ok:
            print(f'[MQTT] Write failed for {msg.topic}: {result}')
        self.publish_state(device_kind, device_name)


def handle_signal(signum, frame):
    global RUNNING
    RUNNING = False


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    options = read_options()
    username = (options.get('mqtt_username', '') or '').strip()
    use_auth_first = bool(username)
    auto_fallback = bool(options.get('mqtt_auto_anonymous_fallback', True))

    bridge = Bridge(options, use_auth=use_auth_first)
    bridge.connect()
    rc = bridge.wait_for_connect()

    if rc != 0:
        if rc == 5:
            print('[MQTT] Broker rejected credentials (rc=5).')
        elif rc == -1:
            print('[MQTT] Connection timeout while waiting for CONNACK.')
        else:
            print(f'[MQTT] Initial connect failed rc={rc}.')

        if use_auth_first and auto_fallback:
            print('[MQTT] Retrying once without credentials (anonymous fallback enabled).')
            bridge.stop()
            bridge = Bridge(options, use_auth=False)
            bridge.connect()
            rc = bridge.wait_for_connect()

    if rc != 0:
        print('[MQTT] Could not establish MQTT session. Please verify host/port and credentials in add-on options.')
        sys.exit(2)

    print('[MQTT] Bridge started')
    try:
        while RUNNING:
            bridge.publish_all_states()
            time.sleep(10)
    finally:
        bridge.stop()
        print('[MQTT] Bridge stopped')
        sys.exit(0)
