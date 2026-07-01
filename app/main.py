# main.py
import asyncio
import os
import threading

import asyncssh
from kivy.app import App
from kivy.clock import Clock
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.scrollview import ScrollView
from android.permissions import request_permissions, Permission
from jnius import autoclass, PythonJavaClass, java_method

# PoC: hartcodiertes Login, kein echtes Produktionssystem.
SSH_USER = "poc"
SSH_PASSWORD = "poc1234"
SSH_PORT = 8022

BluetoothAdapter = autoclass('android.bluetooth.BluetoothAdapter')

scan_results = []


class _SSHServer(asyncssh.SSHServer):
    def password_auth_supported(self):
        return True

    def validate_password(self, username, password):
        return username == SSH_USER and password == SSH_PASSWORD


async def _handle_client(process):
    # Bis zu 10 Sekunden warten bis der BLE-Scan erste Ergebnisse liefert
    for _ in range(10):
        if scan_results:
            break
        await asyncio.sleep(1)

    process.stdout.write("Gefundene BLE-Geraete:\n\n")
    if scan_results:
        process.stdout.write("\n".join(scan_results) + "\n")
    else:
        process.stdout.write("(noch keine Ergebnisse)\n")
    process.exit(0)


async def _run_ssh_server():
    # Host-Key einmalig generieren und im App-Datenverzeichnis speichern.
    key_path = os.path.join(
        os.environ.get('ANDROID_APP_PATH', '.'), 'ssh_host_key'
    )
    if os.path.exists(key_path):
        host_key = asyncssh.read_private_key(key_path)
    else:
        host_key = asyncssh.generate_private_key('ssh-ed25519')
        host_key.write_private_key(key_path)
        os.chmod(key_path, 0o600)

    async with await asyncssh.create_server(
        _SSHServer,
        '',
        SSH_PORT,
        server_host_keys=[host_key],
        process_factory=_handle_client,
    ):
        await asyncio.get_event_loop().create_future()  # läuft bis zum App-Ende


def run_ssh_server():
    asyncio.run(_run_ssh_server())


class MyScanCallback(PythonJavaClass):
    __javainterfaces__ = ['android/bluetooth/BluetoothAdapter$LeScanCallback']

    @java_method('(Landroid/bluetooth/BluetoothDevice;I[B)V')
    def onLeScan(self, device, rssi, scan_record):
        name = device.getName() or "Unbekannt"
        addr = device.getAddress()
        entry = f"{name} | {addr} | RSSI: {rssi}"
        if entry not in scan_results:
            scan_results.append(entry)


class BLEPocApp(App):
    def build(self):
        request_permissions([
            Permission.BLUETOOTH,
            Permission.BLUETOOTH_ADMIN,
            Permission.BLUETOOTH_SCAN,
            Permission.BLUETOOTH_CONNECT,
            Permission.ACCESS_FINE_LOCATION,
        ])

        self.layout = BoxLayout(orientation='vertical')
        self.label = Label(
            text=f'Starte BLE-Scan...\nSSH-Server: Port {SSH_PORT}\n',
            size_hint_y=None,
        )
        self.label.bind(texture_size=self.label.setter('size'))

        scroll = ScrollView()
        scroll.add_widget(self.label)
        self.layout.add_widget(scroll)

        Clock.schedule_once(self.start_ble_scan, 2)
        threading.Thread(target=run_ssh_server, daemon=True).start()
        Clock.schedule_interval(self.update_display, 2)

        return self.layout

    def start_ble_scan(self, dt):
        try:
            adapter = BluetoothAdapter.getDefaultAdapter()
            if not adapter.isEnabled():
                self.label.text += "Bluetooth ist aus!\n"
                return
            self.callback = MyScanCallback()
            adapter.startLeScan(self.callback)
            self.label.text += "Scan laeuft...\n"
        except Exception as e:
            self.label.text += f"Fehler: {e}\n"

    def update_display(self, dt):
        if scan_results:
            self.label.text = (
                f"SSH-Server: Port {SSH_PORT}\n\n"
                "Gefundene Geraete:\n\n" + "\n".join(scan_results)
            )


if __name__ == '__main__':
    BLEPocApp().run()
