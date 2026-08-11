import socket
import subprocess
import platform
import re

# Configuration
HOST = '0.0.0.0'
PORT = 8080
system_os = platform.system()

def is_safe_command(command):
    """
    Basic security check: Only allow specific prefixes or safe characters.
    Prevents dangerous commands like 'rm -rf /' or 'shutdown' unless explicitly allowed.
    """
    # Allow list of safe prefixes
    safe_prefixes = ['open_', 'run_', 'launch_', 'volume_', 'media_']

    if any(command.startswith(prefix) for prefix in safe_prefixes):
        return True

    # Optional: Block dangerous keywords explicitly
    dangerous_keywords = ['shutdown', 'rm ', 'del ', 'format', 'sudo']
    if any(keyword in command for keyword in dangerous_keywords):
        return False

    return False

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
