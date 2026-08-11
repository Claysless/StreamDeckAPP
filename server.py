import socket
import subprocess
import platform
import re

# Configuration
HOST = '0.0.0.0'
PORT = 8080

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

def execute_dynamic_command(command):
    system_os = platform.system()
    
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
        s.bind((HOST, PORT))
        s.listen()
        print(f"Server listening on {HOST}:{PORT} (Dynamic Mode)")
        
        while True:
            conn, addr = s.accept()
            with conn:
                print(f"Connected by {addr}")
                while True:
                    data = conn.recv(1024)
                    if not data:
                        break
                    
                    command = data.decode('utf-8').strip()
                    print(f"Received dynamic command: {command}")
                    
                    response = execute_dynamic_command(command)
                    print(response)
                    conn.sendall(response.encode('utf-8'))

if __name__ == "__main__":
    start_server()   
