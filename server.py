import socket
import subprocess
import platform
import re
import os
import json
import base64
import ctypes
from ctypes import wintypes

# Configuration
HOST = '0.0.0.0'
PORT = 8080
system_os = platform.system()


if system_os == "Windows":
    import win32gui
    import win32process
    import win32api

def get_desktop_environment():
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()

    if "gnome" in desktop:
        return "gnome"

    if "kde" in desktop:
        return "kde"

    return desktop

def get_windows_windows():
    windows = []

    def enum_window(hwnd, _):
        # Only visible windows
        if not win32gui.IsWindowVisible(hwnd):
            return True

        # Ignore windows without a title
        title = win32gui.GetWindowText(hwnd).strip()

        if not title:
            return True

        try:
            _, pid = win32process.GetWindowThreadProcessId(hwnd)

            path = get_process_path_windows(pid)

            windows.append({
                "title": title,
                "path": path,
                "icon": None
            })

        except Exception as e:
            print(f"Could not inspect window {hwnd}: {e}")

        return True

    win32gui.EnumWindows(enum_window, None)

    return windows

def get_process_path_windows(pid):
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

    handle = ctypes.windll.kernel32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION,
        False,
        pid
    )

    if not handle:
        return None

    try:
        buffer = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(buffer))

        success = ctypes.windll.kernel32.QueryFullProcessImageNameW(
            handle,
            0,
            buffer,
            ctypes.byref(size)
        )

        if success:
            return buffer.value

        return None

    finally:
        ctypes.windll.kernel32.CloseHandle(handle)

def deduplicate_applications(windows):

    applications = {}

    for window in windows:

        path = window.get("path")

        if not path:
            continue

        if path not in applications:
            applications[path] = {
                "title": window.get("class") or window.get("title"),
                "path": path,
                "icon": None
            }

    return list(applications.values())

# def get_applications_hyprland():

#     windows = get_windows_hyprland()

#     applications = {}

#     for window in windows:

#         path = window.get("path")

#         if not path:
#             continue

#         if path not in applications:

#             applications[path] = {
#                 "title": window.get("class") or window.get("title"),
#                 "path": path,
#                 "icon": None
#             }

#     return list(applications.values())

def get_windows_hyprland():
    windows = []

    try:
        result = subprocess.run(
            ["hyprctl", "clients", "-j"],
            capture_output=True,
            text=True,
            check=True
        )

        clients = json.loads(result.stdout)

        for client in clients:
            pid = client.get("pid")

            if not pid:
                continue

            title = client.get("title", "")
            class_name = client.get("class", "")

            # Get executable path from PID
            path = None

            try:
                path = os.path.realpath(f"/proc/{pid}/exe")
            except Exception:
                pass

            # Ignore processes where we can't determine an executable
            if not path or not os.path.exists(path):
                path = None

            windows.append({
                "title": title,
                "class": class_name,
                "pid": pid,
                "path": path,
                "workspace": client.get("workspace", {}).get("name"),
                "address": client.get("address"),
                "icon": None,
            })

    except FileNotFoundError:
        print("hyprctl was not found. Is Hyprland running?")

    except subprocess.CalledProcessError as e:
        print(f"hyprctl failed: {e.stderr}")

    except json.JSONDecodeError as e:
        print(f"Invalid JSON returned by hyprctl: {e}")

    except Exception as e:
        print(f"Failed to get Hyprland windows: {e}")

    return windows

def get_windows_linux_wmctrl_x11():
    windows = []

    try:
        result = subprocess.run(
            ["wmctrl", "-lp"],
            capture_output=True,
            text=True,
            check=True
        )

        for line in result.stdout.splitlines():
            parts = line.split(None, 4)

            if len(parts) < 5:
                continue

            window_id = parts[0]
            desktop = parts[1]
            pid = parts[2]
            host = parts[3]
            title = parts[4].strip()

            try:
                pid_int = int(pid)

                path = os.path.realpath(
                    f"/proc/{pid_int}/exe"
                )

            except Exception:
                path = None

            windows.append({
                "id": window_id,
                "title": title,
                "path": path,
                "icon": None
            })

    except Exception as e:
        print(f"Linux window enumeration failed: {e}")

    return windows

def is_safe_command(command):
    """
    Basic security check: Only allow specific prefixes or safe characters.
    Prevents dangerous commands like 'rm -rf /' or 'shutdown' unless explicitly allowed.
    """
    # Allow list of safe prefixes
    safe_prefixes = ['open_', 'run_', 'launch_', 'volume_', 'media_', 'get_applications']

    if any(command.startswith(prefix) for prefix in safe_prefixes):
        return True

    # Optional: Block dangerous keywords explicitly
    dangerous_keywords = ['shutdown', 'rm ', 'del ', 'format', 'sudo']
    if any(keyword in command for keyword in dangerous_keywords):
        return False

    return False



def get_active_windows():
    if system_os == "Windows":
        return get_windows_windows()

    elif system_os == "Linux":


        desktop = get_desktop_environment()

        if desktop == "gnome":
            return get_windows_gnome()

        if desktop == "kde":
            return get_windows_kde()

        if "hyprland" in desktop:
            return get_windows_hyprland()

        print(f"Unsupported Linux desktop: {desktop}")

        return []
        #return get_windows_linux()

    return []



def get_local_ip():
    """Get the local/LAN IP address used for network connections."""
    try:
        # Doesn't actually send data; it lets the OS determine
        # which interface/IP it would use to reach the internet.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
    except Exception:
        # Fallback
        try:
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return "127.0.0.1"

def execute_dynamic_command(command):


    if not is_safe_command(command):
        return f"Error: Command '{command}' is not allowed for security reasons."

    try:

        if not is_safe_command(command):
            return json.dumps({
            "type": "error",
            "message": f"Command '{command}' is not allowed."
            })
        if command == "get_applications":

            # applications = get_applications_hyprland()
            windows = get_active_windows()
            applications = deduplicate_applications(windows)

            return json.dumps({
            "type": "applications",
            "applications": applications
            })


        # if command == "get_windows":

        #     windows = get_active_windows()
        #     windows = deduplicate_applications(windows)

        #     return json.dumps({
        #         "type": "windows",
        #         "windows": windows
        #     })

        # Windows often needs shell=True for commands like 'start'
        # Linux/macOS can often run directly, but shell=True helps with dynamic strings
        if system_os == "Windows":
            # Example: "open_chrome" -> you might need to map this to 'start chrome' on the fly
            # OR expect the app to send the full command like "start chrome"
            # For this dynamic approach, we assume the app sends a valid executable or alias
            # To make 'open_notepad' work dynamically without a map, you need a mapping logic here
            # OR instruct the app to send the actual executable name.

            # STRATEGY: Map common generic names to executables dynamically
            if command.startswith("open_"):
                app = command.replace("open_", "")
                # Simple mapping for common apps
                mapping = {
                    "notepad": "notepad.exe",
                    "calculator": "calc.exe",
                    "chrome": "start chrome",
                    "edge": "start msedge"
                }
                final_cmd = mapping.get(app, app) # Default to app name if not found
                subprocess.Popen(final_cmd, shell=True)
            else:
                subprocess.Popen(command, shell=True)

        elif system_os == "Linux":
            print(f"Executing: '{command}' on Linux")
            if command.startswith("open_"):
                app = command.replace("open_", "")
                # Common Linux mappings
                mapping = {
                    "notepad": "gedit",
                    "calculator": "gnome-calculator",
                    "browser": "brave-origin-beta"
                }
                final_cmd = mapping.get(app, app)
                subprocess.Popen(final_cmd, shell=True)
            else:
                print(f"Executed command without special char {command}")
                subprocess.Popen(command, shell=True)

        return f"Success: Executed '{command}'"

    except Exception as e:
        print(f"Error: {str(e)}")
        return f"Error: {str(e)}"


def start_server():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        # Allows the server to restart/rebind quickly after closing
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        s.bind((HOST, PORT))
        s.listen()

        local_ip = get_local_ip()

        print("=" * 50)
        print("Server started")
        print("=" * 50)
        print(f"Listening on: 0.0.0.0:{PORT}")
        print(f"Connect using: {local_ip}:{PORT}")
        print("=" * 50)

        while True:
            # Wait for a new client
            conn, addr = s.accept()

            print(f"Client connected: {addr}")

            try:
                with conn:
                    while True:
                        data = conn.recv(1024)

                        # Client disconnected
                        if not data:
                            print(f"Client disconnected: {addr}")
                            break

                        command = data.decode("utf-8").strip()

                        print(f"Received command: {command}")

                        response = execute_dynamic_command(command)

                        print(response)

                        conn.sendall(response.encode("utf-8"))

            except ConnectionResetError:
                print(f"Client forcibly disconnected: {addr}")

            except BrokenPipeError:
                print(f"Connection lost while sending to: {addr}")

            except Exception as e:
                print(f"Client error ({addr}): {e}")

            finally:
                print("Waiting for next client...")



if __name__ == "__main__":
    start_server()
