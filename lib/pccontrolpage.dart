import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

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
  // final String pcIpAddress = '192.168.1.201';
  final int pcPort = 8080;
  Socket? _socket;
  String _status = "Disconnected";
  List<PcCommand> _commands = [];
  int _crossAxisCount = 2;
  String _savedIp = "192.168.1.15"; // Default
  final _ipController = TextEditingController();
  int _navIndex = 0;

  final _labelController = TextEditingController();
  final _cmdController = TextEditingController();
  final _picker = ImagePicker();
  File? _tempImageFile;
  String? _tempImageBase64;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- Persistence & Logic (Same as before) ---
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    // Load IP
    _savedIp = prefs.getString('pc_ip') ?? "192.168.1.15";
    _ipController.text = _savedIp;
    final String? data = prefs.getString('pc_commands');

    if (data != null) {
      // 1. Decode to List<dynamic>
      final List<dynamic> jsonList = jsonDecode(data);

      // 2. Explicitly map to List<PcCommand>
      setState(() {
        _commands = jsonList.map((item) => PcCommand.fromJson(item as Map<String, dynamic>)).toList();
      });
    } else {
      // Default commands
      setState(() {
        _commands = [
          PcCommand(id: '1', label: 'Notepad', commandString: 'open_notepad'),
          PcCommand(id: '2', label: 'Calculator', commandString: 'open_calculator'),
        ];
      });
    }

    // Load grid count
    _crossAxisCount = prefs.getInt('grid_columns') ?? 2;
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pc_ip', _savedIp); // Save IP
    await prefs.setString('pc_commands', jsonEncode(_commands.map((c) => c.toJson()).toList()));
    await prefs.setInt('grid_columns', _crossAxisCount);
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

  Future<void> _connect() async {
    try {
      _socket = await Socket.connect(_savedIp, pcPort);
      setState(() => _status = "Connected");
      _socket!.listen((event) {}, onDone: () => setState(() => _status = "Disconnected"));
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

  Widget _buildDialog(BuildContext ctx, {required bool isNew, PcCommand? existingCmd}) {
    return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(isNew ? "Add Command" : "Edit Command"),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _labelController, decoration: InputDecoration(labelText: "Label")),
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
                _commands.add(PcCommand(id: DateTime.now().millisecondsSinceEpoch.toString(), label: _labelController.text, commandString: _cmdController.text, imageBase64: _tempImageBase64));
              } else {
                final index = _commands.indexWhere((c) => c.id == existingCmd!.id);
                if (index != -1) _commands[index] = PcCommand(id: existingCmd!.id, label: _labelController.text, commandString: _cmdController.text, imageBase64: _tempImageBase64 ?? existingCmd.imageBase64);
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
    setState(() => _commands.removeWhere((cmd) => cmd.id == id));
    _saveData();
  }

  // --- Updated Grid Builder ---
  Widget _buildGrid(bool isEdit) {
    return GridView.builder(
      padding: EdgeInsets.all(10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: _commands.length,
      itemBuilder: (ctx, index) {
        final cmd = _commands[index];
        final Uint8List? imgBytes = _convertBase64ToImage(cmd.imageBase64);
        final bool isSmallCard = _crossAxisCount >= 5; // Threshold for hiding text

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
                    setState(() => _savedIp = _ipController.text);
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
              icon: Icon(Icons.wifi),
              label: Text("Connect Now"),
              onPressed: () {
                setState(() => _savedIp = _ipController.text);
                _saveData();
                _connect();
              },
            ),
            SizedBox(height: 20),
            Divider(),
            SizedBox(height: 10),
            Text("Grid Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Slider(
              value: _crossAxisCount.toDouble(),
              min: 1, max: 9, divisions: 8,
              label: "$_crossAxisCount",
              onChanged: (val) {
                setState(() => _crossAxisCount = val.toInt());
                _saveData();
              },
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
      appBar: AppBar(title: Text(currentEditMode ? "Edit Mode" : "PC Remote"), actions: [
        if (_navIndex == 0 || _navIndex == 2) IconButton(icon: Icon(Icons.add), onPressed: _showAddDialog),
      ]),
      body: Column(children: [
        Padding(padding: EdgeInsets.all(8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("Status: $_status", style: TextStyle(fontWeight: FontWeight.bold)),
          IconButton(icon: Icon(_socket == null ? Icons.wifi_off : Icons.wifi, color: _status == "Connected" ? Colors.green : Colors.red), onPressed: _connect),
        ])),
        Expanded(child: _navIndex == 1 ? _buildSettings() : (_commands.isEmpty ? Center(child: Text("No commands")) : _buildGrid(currentEditMode))),
      ]),
      bottomNavigationBar: BottomNavigationBar(currentIndex: _navIndex, onTap: (index) => setState(() => _navIndex = index), items: [
        BottomNavigationBarItem(icon: Icon(Icons.gamepad), label: "Control"),
        BottomNavigationBarItem(icon: Icon(Icons.tune), label: "Settings"),
        BottomNavigationBarItem(icon: Icon(Icons.edit), label: "Edit"),
      ]),
    );
  }
}