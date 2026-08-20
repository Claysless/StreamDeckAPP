import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:streamdeckapp/theme/dark_mode.dart';
import 'package:streamdeckapp/theme/theme_provider.dart';

class PcProfile {
  final String id;
  String name;
  String ip;
  int port;
  int gridColumns;
  List<PcCommand> commands;

  PcProfile({
    required this.id,
    required this.name,
    required this.ip,
    this.port = 8080,
    this.gridColumns = 2,
    required this.commands,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    'port': port,
    'gridColumns': gridColumns,
    'commands': commands.map((c) => c.toJson()).toList(),
  };

  factory PcProfile.fromJson(Map<String, dynamic> json) {
    return PcProfile(
      id: json['id'],
      name: json['name'],
      ip: json['ip'],
      port: json['port'] ?? 8080,
      gridColumns: json['gridColumns'] ?? 2,
      commands: (json['commands'] as List)
          .map((e) => PcCommand.fromJson(e))
          .toList(),
    );
  }
}




class PcApplication {
  final String title;
  final String? path;
  final String? iconBase64;

  PcApplication({
    required this.title,
    this.path,
    this.iconBase64,
  });

  factory PcApplication.fromJson(Map<String, dynamic> json) {
    return PcApplication(
      title: json['title'] ?? '',
      path: json['path'],
      iconBase64: json['icon'],
    );
  }
}


// --- Model (Same as before) ---
class PcCommand {
  final String id;
  final String label;
  final String commandString;
  final String? imageBase64;

  PcCommand({required this.id, required this.label, required this.commandString, this.imageBase64});

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'commandString': commandString, 'imageBase64': imageBase64};
  factory PcCommand.fromJson(Map<String, dynamic> json) => PcCommand(
      id: json['id'], label: json['label'], commandString: json['commandString'], imageBase64: json['imageBase64']);
}

// --- Helpers (Same as before) ---
Future<String?> _convertImageToBase64(File? imageFile) async {
  if (imageFile == null) return null;
  return base64Encode(await imageFile.readAsBytes());
}
Uint8List? _convertBase64ToImage(String? base64Str) {
  if (base64Str == null) return null;
  return base64Decode(base64Str);
}

class PcControlPage extends StatefulWidget {
  @override
  _PcControlPageState createState() => _PcControlPageState();
}

class _PcControlPageState extends State<PcControlPage> {
  Completer<List<PcApplication>>? _applicationsCompleter;
  // final String pcIpAddress = '192.168.1.201';
  // final int pcPort = 8080;
  Socket? _socket;
  String _status = "Disconnected";
  // List<PcCommand> _commands = [];
  // int _crossAxisCount = 2;
  // String _savedIp = "192.168.1.15"; // Default
  List<PcProfile> _profiles = [];
  int _currentProfile = 0;
  PcProfile get currentProfile {
    if (_profiles.isEmpty) {
      throw StateError("No profiles available");
    }

    if (_currentProfile < 0 ||
        _currentProfile >= _profiles.length) {
      _currentProfile = 0;
    }

    return _profiles[_currentProfile];
  }
  final _ipController = TextEditingController();
  int _navIndex = 0;
  bool isLandscape = false;

  final _labelController = TextEditingController();
  final _cmdController = TextEditingController();
  final _picker = ImagePicker();
  File? _tempImageFile;
  String? _tempImageBase64;

  List<PcApplication> _applications = [];
  bool _loadingApplications = false;



  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

     isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );
    }
  }

  // --- Persistence & Logic (Same as before) ---
  // Future<void> _loadData() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   // Load IP
  //   currentProfile.ip = prefs.getString('pc_ip') ?? "192.168.1.15";
  //   _ipController.text = currentProfile.ip;
  //   final String? data = prefs.getString('pc_commands');
  //
  //   if (data != null) {
  //     // 1. Decode to List<dynamic>
  //     final List<dynamic> jsonList = jsonDecode(data);
  //
  //     // 2. Explicitly map to List<PcCommand>
  //     setState(() {
  //       currentProfile.commands = jsonList.map((item) => PcCommand.fromJson(item as Map<String, dynamic>)).toList();
  //     });
  //   } else {
  //     // Default commands
  //     setState(() {
  //       currentProfile.commands = [
  //         PcCommand(id: '1', label: 'Notepad', commandString: 'open_notepad'),
  //         PcCommand(id: '2', label: 'Calculator', commandString: 'open_calculator'),
  //       ];
  //     });
  //   }
  //
  //   // Load grid count
  //   currentProfile.gridColumns = prefs.getInt('grid_columns') ?? 2;
  // }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = prefs.getString('pc_profiles');

    if (jsonString != null) {
      final list = jsonDecode(jsonString) as List;

      _profiles = list
          .map((e) => PcProfile.fromJson(e))
          .toList();
    } else {
      _profiles = [
        PcProfile(
          id: "1",
          name: "My PC",
          ip: "192.168.1.15",
          commands: [
            PcCommand(
              id: "1",
              label: "Notepad",
              commandString: "open_notepad",
            ),
          ],
        ),
      ];
    }

    _currentProfile =
        prefs.getInt('selected_profile') ?? 0;

    if (_currentProfile >= _profiles.length) {
      _currentProfile = 0;
    }

    _ipController.text = currentProfile.ip;

    setState(() {});
  }

  // Future<void> _saveData() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.setString('pc_ip', currentProfile.ip); // Save IP
  //   await prefs.setString('pc_commands', jsonEncode(currentProfile.commands.map((c) => c.toJson()).toList()));
  //   await prefs.setInt('grid_columns', currentProfile.gridColumns);
  // }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'pc_profiles',
      jsonEncode(_profiles.map((p) => p.toJson()).toList()),
    );

    await prefs.setInt(
      'selected_profile',
      _currentProfile,
    );
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _tempImageFile = File(pickedFile.path));
      _tempImageBase64 = await _convertImageToBase64(_tempImageFile);
    }
  }

  void _sendCommand(String command) {
    if (_socket != null) {
      try { _socket!.write("$command\n"); } catch (e) { setState(() => _status = "Error: $e"); }
    }
  }

  void _handleServerResponse(Map<String, dynamic> json) {
    print("Handling response: $json");

    if (json['type'] == 'applications') {
      final List<dynamic> data = json['applications'] ?? [];

      final applications = data
          .map((item) => PcApplication.fromJson(
        item as Map<String, dynamic>,
      ))
          .toList();

      print("Received ${applications.length} applications");

      _applicationsCompleter?.complete(applications);
      _applicationsCompleter = null;

      return;
    }

    if (json['type'] == 'error') {
      _applicationsCompleter?.completeError(
        Exception(json['message'] ?? 'Server error'),
      );

      _applicationsCompleter = null;

      return;
    }
  }

  Future<void> _connect() async {
    try {
      _socket = await Socket.connect(currentProfile.ip, currentProfile.port);
      setState(() => _status = "Connected");
      _socket!.listen(
            (event) {
          final response = utf8.decode(event);

          print("Server response: $response");

          try {
            final json = jsonDecode(response);

            _handleServerResponse(json);
          } catch (e) {
            print("Invalid server response: $e");
          }
        },
        onDone: () {
          setState(() => _status = "Disconnected");
        },
      );
    } catch (e) {
      setState(() => _status = "Failed: $e");
    }
  }

  // --- Dialogs (Same as before, omitted for brevity) ---
  void _showAddDialog() {
    _labelController.clear(); _cmdController.clear(); _tempImageFile = null; _tempImageBase64 = null;
    showDialog(context: context, builder: (ctx) => _buildDialog(ctx, isNew: true));
  }

  void _showEditDialog(PcCommand cmd) {
    _labelController.text = cmd.label; _cmdController.text = cmd.commandString;
    _tempImageFile = null; _tempImageBase64 = cmd.imageBase64;
    showDialog(context: context, builder: (ctx) => _buildDialog(ctx, isNew: false, existingCmd: cmd));
  }

  Future<List<PcApplication>> _requestApplications() {
    _applicationsCompleter = Completer<List<PcApplication>>();

    _sendCommand("get_applications");

    return _applicationsCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _applicationsCompleter = null;
        throw Exception("Timed out waiting for applications");
      },
    );
  }
  Future<void> _selectApplication() async {
    try {
      final applications = await _requestApplications();

      if (!mounted) return;

      final selected = await showDialog<PcApplication>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text("Select Application"),

            content: SizedBox(
              width: 600,
              height: 500,

              child: applications.isEmpty
                  ? const Center(
                child: Text("No applications found"),
              )
                  : ListView.builder(
                itemCount: applications.length,

                itemBuilder: (context, index) {
                  final app = applications[index];

                  Uint8List? iconBytes;

                  if (app.iconBase64 != null &&
                      app.iconBase64!.isNotEmpty) {
                    try {
                      iconBytes = base64Decode(app.iconBase64!);
                    } catch (_) {
                      iconBytes = null;
                    }
                  }

                  return ListTile(
                    leading: iconBytes != null
                        ? Image.memory(
                      iconBytes,
                      width: 40,
                      height: 40,
                    )
                        : const Icon(
                      Icons.apps,
                      size: 40,
                    ),

                    title: Text(
                      app.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    subtitle: Text(
                      app.path ?? "Unknown path",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    onTap: () {
                      Navigator.pop(ctx, app);
                    },
                  );
                },
              ),
            ),

            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
            ],
          );
        },
      );

      if (selected != null) {
        setState(() {
          _labelController.text = selected.title;
          _cmdController.text = selected.path ?? "";
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to get applications: $e"),
        ),
      );
    }
  }
  Widget _buildDialog(BuildContext ctx, {required bool isNew, PcCommand? existingCmd}) {
    return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(isNew ? "Add Command" : "Edit Command"),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: Icon(Icons.apps,color: Theme.of(context).colorScheme.inversePrimary,),
                label: Text("Select Application", style: TextStyle(color: Theme.of(context).colorScheme.inversePrimary),),
                onPressed: _selectApplication,
              ),
              TextField(controller: _labelController, decoration: InputDecoration(labelText: "Label")),
              SizedBox(height: 15),
              TextField(controller: _cmdController, decoration: InputDecoration(labelText: "Command")),
              SizedBox(height: 15),
              GestureDetector(
                onTap: _pickImage,
                child: Container(height: 100, width: double.infinity, color: Colors.grey[300],
                  child: _tempImageFile != null ? Image.file(_tempImageFile!, fit: BoxFit.cover)
                      : (existingCmd?.imageBase64 != null ? Image.memory(_convertBase64ToImage(existingCmd!.imageBase64)!, fit: BoxFit.cover)
                      : Center(child: Icon(Icons.add_a_photo, color: Colors.grey))),
                ),
              ),
              if (!isNew && existingCmd?.imageBase64 != null)
                TextButton(onPressed: () { setDialogState(() { _tempImageBase64 = null; }); }, child: Text("Remove Image", style: TextStyle(color: Colors.red))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            if (_labelController.text.isEmpty || _cmdController.text.isEmpty) return;
            setState(() {
              if (isNew) {
                currentProfile.commands.add(PcCommand(id: DateTime.now().millisecondsSinceEpoch.toString(), label: _labelController.text, commandString: _cmdController.text, imageBase64: _tempImageBase64));
              } else {
                final index = currentProfile.commands.indexWhere((c) => c.id == existingCmd!.id);
                if (index != -1) currentProfile.commands[index] = PcCommand(id: existingCmd!.id, label: _labelController.text, commandString: _cmdController.text, imageBase64: _tempImageBase64 ?? existingCmd.imageBase64);
              }
            });
            _saveData();
            Navigator.pop(ctx);
          },
          child: Text(isNew ? "Add" : "Save"),
        ),
      ],
    ));
  }

  void _removeCommand(String id) {
    setState(() => currentProfile.commands.removeWhere((cmd) => cmd.id == id));
    _saveData();
  }

  void _addProfile() {
    final name = TextEditingController();
    final ip = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("New Profile"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: "Profile Name",
              ),
            ),
            TextField(
              controller: ip,
              decoration: const InputDecoration(
                labelText: "IP Address",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _profiles.add(
                  PcProfile(
                    id: DateTime.now()
                        .millisecondsSinceEpoch
                        .toString(),
                    name: name.text,
                    ip: ip.text,
                    commands: [],
                  ),
                );

                _currentProfile = _profiles.length - 1;
              });

              _saveData();
              Navigator.pop(context);
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  void _duplicateProfile() {
    final p = currentProfile;

    _profiles.add(
      PcProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: "${p.name} Copy",
        ip: p.ip,
        port: p.port,
        gridColumns: p.gridColumns,
        commands: p.commands
            .map((c) => PcCommand.fromJson(c.toJson()))
            .toList(),
      ),
    );

    _saveData();
  }

  Future<void> _deleteCurrentProfile() async {
    if (_profiles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must have at least one profile."),
        ),
      );

      return;
    }

    final profile = currentProfile;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Profile?"),

        content: Text(
          'Are you sure you want to delete "${profile.name}"?\n\n'
              'All buttons and settings belonging to this profile will be removed.',
        ),

        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
            },
            child: const Text("Cancel"),
          ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx, true);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _profiles.removeAt(_currentProfile);

      // Select a valid profile
      if (_currentProfile >= _profiles.length) {
        _currentProfile = _profiles.length - 1;
      }

      _ipController.text = currentProfile.ip;
    });

    // Disconnect from the old profile
    try {
      await _socket?.close();
    } catch (_) {}

    _socket = null;

    setState(() {
      _status = "Disconnected";
    });

    await _saveData();
  }


  // --- Updated Grid Builder ---
  Widget _buildGrid(bool isEdit) {
    return GridView.builder(
      padding: EdgeInsets.all(10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: currentProfile.gridColumns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: currentProfile.commands.length,
      itemBuilder: (ctx, index) {
        final cmd = currentProfile.commands[index];
        final Uint8List? imgBytes = _convertBase64ToImage(cmd.imageBase64);
        final bool isSmallCard = currentProfile.gridColumns >= 5; // Threshold for hiding text

        return Card(
          color: isEdit ? Colors.grey[200] : null,
          child: GestureDetector(
            onTap: isEdit ? null : () => _sendCommand(cmd.commandString),
            onLongPress: () {
              // Show Context Menu on Long Press
              final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
              showMenu(
                context: context,
                position: RelativeRect.fromRect(
                  Rect.fromPoints(overlay.localToGlobal(Offset.zero), overlay.localToGlobal(Offset.zero)),
                  Rect.fromLTWH(0, 0, MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
                ),
                items: [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(leading: Icon(Icons.edit, color: Colors.orange), title: Text("Edit"), contentPadding: EdgeInsets.zero),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text("Delete"), contentPadding: EdgeInsets.zero),
                  ),
                ],
              ).then((value) {
                if (value == 'edit') _showEditDialog(cmd);
                if (value == 'delete') _removeCommand(cmd.id);
              });
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Image or Icon
                  if (imgBytes != null)
                    ClipOval(child: Image.memory(imgBytes, fit: BoxFit.fill))
                  else
                    Icon(Icons.gamepad, size: isSmallCard ? 30 : 40, color: isEdit ? Colors.grey : Colors.blue),

                  // SizedBox(height: isSmallCard ? 4 : 10),

                  // Responsive Text
                  if (!isSmallCard) // Always show text if no image, or if card is big
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        cmd.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallCard ? 10 : 14,
                          color: isEdit ? Colors.grey : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Connection Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            Text("PC IP Address"),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "e.g. 192.168.1.15",
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.save),
                  onPressed: () {
                    setState(() => currentProfile.ip = _ipController.text);
                    _saveData();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("IP Saved!")));
                  },
                ),
              ),
            ),
            SizedBox(height: 10),
            Text("Tip: Find your PC IP by running 'ipconfig' in CMD (Windows) or 'ifconfig' (Linux/Mac)."),
            SizedBox(height: 30),
            ElevatedButton.icon(
              icon: Icon(Icons.wifi,color: Theme.of(context).colorScheme.inversePrimary,),
              label: Text("Connect Now",style: TextStyle(color: Theme.of(context).colorScheme.inversePrimary,) ),
              onPressed: () {
                setState(() => currentProfile.ip = _ipController.text);
                _saveData();
                _connect();
              },
            ),
            SizedBox(height: 20),
            Divider(),
            SizedBox(height: 10),
            Text("Grid Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Slider(
              value: currentProfile.gridColumns.toDouble(),
              min: 1, max: 9, divisions: 8,
              label: currentProfile.gridColumns.toString(),
              activeColor: Theme.of(context).colorScheme.inversePrimary,
              onChanged: (val) {
                setState(() => currentProfile.gridColumns = val.toInt());
                _saveData();
              },
            ),
            Divider(),
            SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            const Text(
              "Dark Mode",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            CupertinoSwitch(
              value:
              Provider.of<ThemeProvider>(context, listen: false)
                  .isDarkMode,
              onChanged: (value) async {
                Provider.of<ThemeProvider>(context, listen: false)
                    .toggleTheme();
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('theme_darkmode', value); // Save theme mode
              },
            ),

              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool currentEditMode = _navIndex == 2;
    return Scaffold(
      appBar:  isLandscape == false ? AppBar(title: Text(_profiles[_currentProfile].name,), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.computer),

          onSelected: (value) {
            if (value == 'new') {
              _addProfile();
              return;
            }

            if (value == 'delete') {
              _deleteCurrentProfile();
              return;
            }

            final index = int.parse(value);

            setState(() {
              _currentProfile = index;
              _ipController.text = currentProfile.ip;
            });

            _saveData();
          },

          itemBuilder: (_) => [
            for (int i = 0; i < _profiles.length; i++)
              PopupMenuItem(
                value: i.toString(),
                child: Row(
                  children: [
                    const Icon(Icons.computer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _profiles[i].name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    if (i == _currentProfile)
                      const Icon(Icons.check),
                  ],
                ),
              ),

            const PopupMenuDivider(),

            const PopupMenuItem(
              value: 'new',
              child: Row(
                children: [
                  Icon(Icons.add),
                  SizedBox(width: 8),
                  Text("New Profile"),
                ],
              ),
            ),

            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    "Delete Current Profile",
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Text("Status: $_status", style: TextStyle(fontWeight: FontWeight.bold)),
        IconButton(icon: Icon(_socket == null ? Icons.wifi_off : Icons.wifi, color: _status == "Connected" ? Colors.green : Colors.red), onPressed: _connect),
        Padding(padding: EdgeInsetsGeometry.all(10)),
        if (_navIndex == 0 || _navIndex == 2) IconButton(icon: Icon(Icons.add), onPressed: _showAddDialog),
      ]) : null,
      body: Column(children: [
        // Padding(padding: EdgeInsets.all(8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        //
        //
        // ])),
        Expanded(child: _navIndex == 1 ? _buildSettings() : (currentProfile.commands.isEmpty ? Center(child: Text("No commands")) : _buildGrid(currentEditMode))),
      ]),
      bottomNavigationBar: isLandscape == false ? BottomNavigationBar(currentIndex: _navIndex, onTap: (index) => setState(() => _navIndex = index), items: [
        BottomNavigationBarItem(icon: Icon(Icons.gamepad), label: "Control"),
        BottomNavigationBarItem(icon: Icon(Icons.tune), label: "Settings"),
        BottomNavigationBarItem(icon: Icon(Icons.edit), label: "Edit"),
      ]) : null,
    );
  }
}