import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:app_links/app_links.dart';
import 'screens/command_center.dart'; // Agar file ka naam command_center.dart hai
import 'package:geolocator/geolocator.dart';


final FlutterLocalNotificationsPlugin bossNotifications = FlutterLocalNotificationsPlugin();
final AudioPlayer _audioPlayer = AudioPlayer();
final AppLinks _appLinks = AppLinks();

void main() async {

  WidgetsFlutterBinding.ensureInitialized(); // Yeh line lazmi hai Firebase ke liye
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb) {
    const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: initSettingsAndroid);
    await bossNotifications.initialize(settings: initSettings);
  }

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: CommandScreen(), // WAPIS PURANI SCREEN LAGA DI
  ));
}

class CommandScreen extends StatefulWidget {
  const CommandScreen({super.key});
  static bool isAwaitingPunishmentProof = false;
  static bool isScreenCurrentlyLocked = false;
  static String releaseCondition = "Manual (Only I release)"; // Default condition, lekin punishment ke hisaab se change hoga
  
  @override
  State<CommandScreen> createState() => _CommandScreenState();
  
}

class _CommandScreenState extends State<CommandScreen> {
  late IO.Socket socket;
  bool isConnected = false;
  String hisMode = "Synicing....";

  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLiveTracking = false;
  

  final TextEditingController _msgController = TextEditingController();
  bool isForcedOverlay = false;
  
  bool isVoiceMode = false; 

  int sosPressCount = 0;
  
  List<Map<String, dynamic>> incomingLogs = [];

  // Boss Voice Recording State
  final AudioRecorder _bossRecorder = AudioRecorder();
  bool _isBossRecording = false;
  String? _pendingVoiceBase64;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _connectToServer();
    // 👇 NFC Tap Listener
    // 👇 NFC Tap Listener
    _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null && uri.scheme == 'amore') {
        
        // 1. NFC Locket Signal
        if (uri.host == 'missyou') {
          _triggerLoveSignal();
        } 
        
        // 2. 💖 Widget Heart Signal
        else if (uri.host == 'heart') {
          _triggerLoveSignal(); // Filhal isay bhi same love signal par rakhte hain
        } 
        
        // 3. ⚠️ Widget Danger Signal
        else if (uri.host == 'danger') {

          
          
          // 🚨 DANGER BUTTON PRESSED FROM HOMESCREEN!
          _startLiveDangerTracking();
          if (!mounted) return;          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("⚠️ DANGER ALARM TRIGGERED!"), backgroundColor: Colors.red, duration: Duration(seconds: 3))
          );
        }
      }
    });

    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null && uri.scheme == 'amore' && uri.host == 'missyou') {
        _triggerLoveSignal();
      }
    });
  }

  void _triggerLoveSignal() {
    Future.delayed(const Duration(seconds: 2), () {
      if (isConnected) {
        // 👇 Theek kiya hua payload (Imad ki app ko vibrate karega aur msg dega)
        socket.emit('trigger_vibration', {
          'type': 'OVERLAY_COMMAND', 
          'delivery': 'NOTIFICATION', // Is se screen lock nahi hogi, sirf notification + vibrate hoga
          'release_type': 'Manual (Only I release)', 
          'message': '💖 Amore tapped her locket! She misses you!',
          'priority': 'HIGH'
        });
        
        // Boss ki screen par chota sa cute popup
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✨ Love vibration sent to Imad! ✨"), backgroundColor: Colors.pinkAccent)
          );
        }
      }
    });
  }

  Future<void> _startLiveDangerTracking() async {
  // 1. Pehle siren bhej dein
  socket.emit('trigger_vibration', {'type': 'SOS_ALARM'});

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
    setState(() => _isLiveTracking = true);
    
    // 🚨 CONSTANT STREAM SHURU! (Har 10 meter baad location update hogi)
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // 10 meter move karne par update bhejega
      )
    ).listen((Position position) {
      if (isConnected) {
        socket.emit('danger_location', {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'speed': position.speed, // Unki speed bhi pata chalegi!
          'timestamp': DateTime.now().toString(),
        });
        print("Live Location Sent: ${position.latitude}, ${position.longitude}");
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🚨 LIVE LOCATION STREAMING TO SUB-STATION!"), backgroundColor: Colors.red)
    );
  }
}

// 🚨 Tracking Rokne ka function (Jab wo khud Stop dabayengi)
void _stopLiveTracking() {
  _positionStreamSubscription?.cancel();
  setState(() => _isLiveTracking = false);
  socket.emit('trigger_vibration', {'type': 'MSG', 'message': 'Danger Mode Deactivated. Location stopped.'});
}

  

  Future<void> _requestPermissions() async {
    if (!kIsWeb) {
      await [
        Permission.microphone,
        Permission.notification,
        Permission.camera,
        Permission.location,
      ].request();
    }
  }

  void _connectToServer() {
    socket = IO.io('https://locket-backend-t4m7.onrender.com', <String, dynamic>{
      'transports': ['websocket', 'polling'],
      'autoConnect': true,
    });

    socket.onConnect((_) {
      if (mounted) {
        setState(() => isConnected = true);
        
        // 👇 NAYI LINE: Connect hote hi Imad ki app ko ping karo
        socket.emit('trigger_vibration', {'type': 'REQUEST_STATUS'}); 
      }
    });
    socket.onDisconnect((_) => setState(() => isConnected = false));

    socket.on('status_updated', (data) {
      if (mounted) {
        setState(() {
          hisMode = data['mode'];
          if (hisMode != "Our Time 💑") isForcedOverlay = false;
        });
      }
    });

    socket.on('vibrate_signal', (data) {
      if (!mounted) return;
      String type = data['type'] ?? "";
      String msg = data['message'] ?? "";
      
      if (type == 'HEALTH_DATA') {
        _showNotification("Health Vitals Received", "Tap to view vitals");
        _showHealthPopup(msg);
        return;
      }

      if (type == 'REPLY' || type == 'LOG_ENTRY' || type == 'MSG' || type == 'CHECK_IN') {
        _showNotification("My Boy Update", msg);
        setState(() {
          incomingLogs.insert(0, {
            'type': 'text',
            'content': msg,
            'time': _timeNow()
          });
        });
      }
    });

    // 🚨 UPDATED: Universal Media Listener
    socket.on('proof_submitted', (data) {
      if (mounted) {

        // YEH PRINT LAZMI LAGA DIJIYE
        print("====== MEDIA RECEIVED ======");
        print("Image exist karti hai? ${data.containsKey('image')}");
        if (data.containsKey('image') && data['image'] != null) {
          print("Image ki length (size) kitni hai: ${data['image'].toString().length}");
        }
        
        print("============================");

        bool isImage = data.containsKey('image') && data['image'] != null;
        
        _showNotification(isImage ? "Photo Received" : "Voice Note Received", "New media from My Boy.");
        
        setState(() {
          // 🔥 NAYA: Jaise hi proof aaye, Red Panel Auto-open ho jaye!
          
          
          if (data['isProof'] == true && CommandScreen.isAwaitingPunishmentProof == true) {
            CommandScreen.isScreenCurrentlyLocked = true;
          }
          incomingLogs.insert(0, {
            
            'type': isImage ? 'photo' : 'voice',
            'content': isImage ? '📸 Media Received' : '🎤 Voice Note Received',
            'image': data['image'], 
            'audio': data['audio'], 
            'time': _timeNow()
          });
        });
      }
    });
  }

  String _timeNow() => "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";

  Future<void> _showNotification(String title, String body) async {
    if (kIsWeb) return;
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'boss_alerts', 'My Boy Alerts',
      importance: Importance.max, priority: Priority.high,
    );
    await bossNotifications.show(
      id: DateTime.now().millisecond, 
      title: title, 
      body: body, 
      notificationDetails: const NotificationDetails(android: androidDetails)
    );
  }

  Future<void> _playBase64Audio(String base64String) async {
    try {
      // 1. Safayi
      String cleanAudio = base64String.replaceAll(RegExp(r'\s+'), '');

      if (kIsWeb) {
        // 2. WEB KE LIYE: Data URI ka istemal
        String audioUri = 'data:audio/mp4;base64,$cleanAudio';
        await _audioPlayer.play(UrlSource(audioUri));
      } else {
        // 3. ANDROID (POCO X7) KE LIYE: Temp file mein save karke play karna
        Uint8List bytes = base64Decode(cleanAudio);
        Directory tempDir = await getTemporaryDirectory();
        File tempFile = File('${tempDir.path}/boss_temp_audio.m4a');
        await tempFile.writeAsBytes(bytes);
        
        await _audioPlayer.play(DeviceFileSource(tempFile.path));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Audio Playback Error: $e"), backgroundColor: Colors.red)
      );
    }
  }

  // --- Boss Voice Command Recording ---
  Future<void> _toggleBossVoice() async {
    if (await Permission.microphone.request().isGranted) {
      if (_isBossRecording) {
        String? path = await _bossRecorder.stop();
        setState(() => _isBossRecording = false);
        if (path != null) {
          List<int> audioBytes = await File(path).readAsBytes();
          // 🚨 BHEJNA NAHI HAI, SIRF SAVE KARNA HAI 🚨
          setState(() {
            _pendingVoiceBase64 = base64Encode(audioBytes);
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Voice Instruction Sent")));
        }
      } else {
        final dir = await getTemporaryDirectory();
        await _bossRecorder.start(const RecordConfig(), path: '${dir.path}/boss_voice.m4a');
        setState(() {
          _isBossRecording = true;
          _pendingVoiceBase64 = null; // Purani audio clear kardi
        });
      }
    }
  }

  void _showHealthPopup(String healthInfo) {
    TextEditingController replyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(children: [Icon(Icons.monitor_heart, color: Colors.greenAccent), SizedBox(width: 8), Text("HIS VITALS", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18))]),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.of(context).pop())
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)), child: Text(healthInfo, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5))),
              const SizedBox(height: 20),
              TextField(
                controller: replyCtrl, style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(hintText: "Send instructions...", hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), suffixIcon: IconButton(icon: const Icon(Icons.send, color: Colors.pinkAccent), onPressed: () { if (replyCtrl.text.isNotEmpty) { socket.emit('trigger_vibration', {'type': 'OVERLAY_COMMAND', 'delivery': 'NOTIFICATION', 'release_type': 'Manual (Only I release)', 'message': "Health Reply: ${replyCtrl.text}", 'priority': 'HIGH'}); Navigator.of(context).pop(); } })),
              )
            ],
          ),
        );
      },
    );
  }

  void _executeCommand() {
    if (!isConnected) return;

    if (isForcedOverlay) {
      setState(() {
        CommandScreen.isAwaitingPunishmentProof = true; // 🚨 Gate khul gaya!
      });
    }
    
    // 1. Basic Payload
    final payload = {
      'type': 'OVERLAY_COMMAND', 
      'delivery': isForcedOverlay ? 'OVERLAY' : 'NOTIFICATION', 
      'release_type': CommandScreen.releaseCondition, 
      'message': _msgController.text.isNotEmpty ? _msgController.text : "Acknowledge Command.", 
      'priority': 'HIGH'
    };

    // 2. Agar Audio hold hui wi hai toh usay payload mein daal do 🚨
    if (_pendingVoiceBase64 != null) {
      payload['audio'] = _pendingVoiceBase64!;
      if (_msgController.text.isEmpty) {
        payload['message'] = "🎤 Voice Instruction"; // Default message agar text khali ho
      }
    }

    // 3. Emit kardo
    socket.emit('trigger_vibration', payload);
    
    // 4. Safayi (Reset everything)
    setState(() { 
      // 🔥 NAYA: Boss ka msg bhi log mein add karo
      incomingLogs.insert(0, {
        'type': 'text',
        'content': '👑 You: ${payload['message']}',
        'time': _timeNow()
      });
      if (isForcedOverlay) CommandScreen.isScreenCurrentlyLocked = true; 
      _msgController.clear(); 
      _pendingVoiceBase64 = null; // 🚨 Audio clear kardo next time ke liye
      FocusScope.of(context).unfocus(); 
    });
  }

  void _releaseHisScreen() {
    socket.emit('trigger_vibration', {'type': 'RELEASE_OVERLAY', 'message': 'Screen released by Boss.'});
    setState(() {
    CommandScreen.isScreenCurrentlyLocked = false;
    CommandScreen.isAwaitingPunishmentProof = false; // 🚨 Gate band! Ab naye proof par auto-open nahi hoga
  });
  }
  
  void _requestHealthSync() {
    socket.emit('trigger_vibration', {'type': 'REQUEST_HEALTH', 'message': 'Fetching Vitals...'});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Health Data Requested..."), duration: Duration(seconds: 2)));
  }

  Color _getStatusColor() {
    if (hisMode == "Class") return Colors.blueAccent;
    if (hisMode == "Busy") return Colors.orangeAccent;
    if (hisMode == "Sleeping") return Colors.purpleAccent;
    if (hisMode == "Our Time 💑") return Colors.pinkAccent;
    return Colors.redAccent;
  }

  @override
  void dispose() {
    // 🚨 Purane sockets aur controllers ko kill karna lazmi hai
    if (isConnected) {
      socket.disconnect();
      socket.dispose();
    }
    _msgController.dispose();
    _bossRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color themeColor = _getStatusColor();
    bool canTakeover = hisMode == "Our Time 💑";

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        title: Row(
          children: [
            Icon(Icons.circle, size: 12, color: isConnected ? Colors.green : Colors.red), 
            const SizedBox(width: 8), 
            const Text("My Love Hub 💖", style: TextStyle(letterSpacing: 3, fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))
          ]
        ),
        // YAHAN SE NAYA CODE SHURU HAI 👇 (Hawk-Eye Button)
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
            tooltip: "Open Vault Commands",
            onPressed: () {
              // Yeh button dabane se BossDashboard khul jayega!
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => BossDashboard(socket: socket, hisMode: hisMode)), 
              );
            },
          )
        ],
        // YAHAN NAYA CODE KHATAM HAI 👆
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: themeColor.withOpacity(0.1), border: Border.all(color: themeColor.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("My Boy:", style: TextStyle(color: Colors.white54, fontSize: 12)), Text(hisMode.toUpperCase(), style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, letterSpacing: 2))]), IconButton(icon: const Icon(Icons.favorite_border, color: Colors.greenAccent), tooltip: "Sync Health Vitals", onPressed: _requestHealthSync)]),
            ),
          ),
          Expanded(flex: 3, child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: CommandScreen.isScreenCurrentlyLocked ? _buildActiveLockdownPanel() : _buildMacroBuilder(canTakeover))),
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1)))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.all(16.0), child: Text("My Boy LOGS", style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2))),
                  Expanded(
                    child: ListView.builder(
                      itemCount: incomingLogs.length,
                      itemBuilder: (context, index) {
                        var log = incomingLogs[index];
                        IconData logIcon = Icons.message;
                        if (log['type'] == 'photo') logIcon = Icons.camera_alt;
                        if (log['type'] == 'voice') logIcon = Icons.mic;

                        return ListTile(
                          leading: Icon(logIcon, color: themeColor),
                          title: Text(log['content'], style: const TextStyle(color: Colors.white, fontSize: 14)),
                          
                          // 🚨 UPDATED: Crash-Proof Media Display Logic
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Image Render
if (log.containsKey('image') && log['image'] != null)
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Builder( // 👈 Builder bahar rakha taake string pehle clean ho jaye
      builder: (context) {
        String base64Str = log['image'].toString();
        
        // 🚨 YEH LINE CRASH KO ROKEGI
        if (base64Str.contains(',')) base64Str = base64Str.split(',').last;
        base64Str = base64Str.replaceAll(RegExp(r'\s+'), '');

        // 🚨 NAYA LOGIC: GestureDetector ab yahan se return hoga
        return GestureDetector(
          onTap: () {
            // 🚨 This opens the image in a full-screen popup!
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(8),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      InteractiveViewer(
                        panEnabled: true, // Allow panning
                        minScale: 0.5,
                        maxScale: 4.0, // Allow zooming in 4x
                        child: Image.memory(base64Decode(base64Str)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(base64Str),
              height: 150,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Text('⚠️ Image Error', style: TextStyle(color: Colors.red)),
            ),
          ),
        );
      }
    ),
  ),
                              
                              // Audio Render
                              if (log.containsKey('audio') && log['audio'] != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                                    icon: const Icon(Icons.play_arrow, color: Colors.pinkAccent),
                                    label: const Text("Play Audio", style: TextStyle(color: Colors.white, fontSize: 12)),
                                    onPressed: () async {
                                      try {
                                        String cleanAudio = log['audio'].toString().replaceAll(RegExp(r'\s+'), '');
                                        await _playBase64Audio(log['audio'].toString());
                                      } catch (e) {
                                        // ignore: use_build_context_synchronously
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                                      }
                                    },
                                  ),
                                ),
                                
                              Text(log['time'], style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveLockdownPanel() {
    bool needsProof = CommandScreen.releaseCondition.contains("Proof") || 
                      CommandScreen.releaseCondition.contains("Voice");
    return Container(
      padding: const EdgeInsets.all(24), 
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), border: Border.all(color: Colors.redAccent, width: 2), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        const Icon(Icons.lock_outline, color: Colors.redAccent, size: 60),
        const SizedBox(height: 16),
        const Text("SCREEN TAKEOVER ACTIVE", style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 8),
        Text("Waiting for: ${CommandScreen.releaseCondition}", style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 32),

        TextField(
          controller: _msgController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Send message while locked...",
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true, fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            suffixIcon: IconButton(
              icon: const Icon(Icons.send, color: Colors.pinkAccent),
              onPressed: () {
                if (_msgController.text.isNotEmpty) {
                  // Bina release kiye OVERLAY_COMMAND bhejo
                  socket.emit('trigger_vibration', {
                    'type': 'OVERLAY_COMMAND', 
                    'delivery': 'OVERLAY', 
                    'release_type': CommandScreen.releaseCondition, 
                    'message': _msgController.text, 
                    'priority': 'HIGH'
                  });
                  setState(() {
                    incomingLogs.insert(0, {'type': 'text', 'content': '👑 You (Locked): ${_msgController.text}', 'time': _timeNow()});
                    _msgController.clear();
                  });
                  FocusScope.of(context).unfocus();
                }
              }
            )
          ),
        ),
        const SizedBox(height: 20),

        if (needsProof) ...[
          // CASE 1: AGAR PROOF CHAHIYE (Photo/Voice)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 50)), 
            icon: const Icon(Icons.check, color: Colors.white), 
            label: const Text("ACCEPT PROOF & RELEASE", style: TextStyle(color: Colors.white)), 
            onPressed: _releaseHisScreen
          ),
          const SizedBox(height: 12),
          
          
          // 🚨 FIXED: REJECT BUTTON WITH REASON POPUP
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[900],
                minimumSize: const Size(double.infinity, 50)),
            icon: const Icon(Icons.close, color: Colors.white),
            label: const Text("REJECT PROOF (KEEP LOCKED)",
                style: TextStyle(color: Colors.white)),
            onPressed: () {
              TextEditingController reasonCtrl = TextEditingController();
              showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                        backgroundColor: Colors.grey[900],
                        title: const Text("Reject Proof",
                            style: TextStyle(color: Colors.redAccent)),
                        content: TextField(
                          controller: reasonCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                              hintText: "Reason (e.g., Blurry, Voice not clear)",
                              hintStyle: TextStyle(color: Colors.white38)),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("CANCEL")),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red),
                            onPressed: () {
                              String reason = reasonCtrl.text.isEmpty
                                  ? "Submit again properly."
                                  : reasonCtrl.text;

                              socket.emit('trigger_vibration', {
                                'type': 'OVERLAY_COMMAND',
                                'delivery': isForcedOverlay ? 'OVERLAY' : 'NOTIFICATION',
                                'release_type': CommandScreen.releaseCondition,
                                'message': '❌ PROOF REJECTED: $reason',
                                'priority': 'HIGH'
                              });

                              Navigator.pop(context); // Popup band karega
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text("Rejection & Reason sent!"),
                                      backgroundColor: Colors.red));
                            },
                            child: const Text("SEND REJECTION"), // 👈 VS Code ne ye line ura di thi
                          )
                        ],
                      ));
            },
          ),
          ] 
      else ...[
        // 🚨 YEH HAI WO "ELSE" JO MISSING THA 🚨
        // CASE: AGAR MANUAL RELEASE HAI
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueGrey[800], 
            minimumSize: const Size(double.infinity, 50)
          ), 
          icon: const Icon(Icons.lock_open, color: Colors.white), 
          label: const Text("RELEASE MANUALLY NOW", style: TextStyle(color: Colors.white)), 
          onPressed: _releaseHisScreen // Seedha release kar dega
        ),
      ],
        ]
      ),
    );
  }

  Widget _buildMacroBuilder(bool canTakeover) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: const CircleBorder(), padding: const EdgeInsets.all(20)), onPressed: () {
            setState(() => sosPressCount++);
            if (sosPressCount <= 3) {
              socket.emit('trigger_vibration', {'type': 'SOS_VIBRATE_ONLY'});
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Warning Sent ($sosPressCount/3)")));
            } else {
              showDialog(context: context, builder: (bc) => AlertDialog(backgroundColor: Colors.grey[900], title: const Text("⚠️ TRIGGER ALARM?", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)), content: const Text("Blast siren and override modes?", style: TextStyle(color: Colors.white)), actions: [TextButton(child: const Text("CANCEL"), onPressed: () { setState(() => sosPressCount = 0); Navigator.pop(bc); }), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("BLAST"), onPressed: () { _startLiveDangerTracking(); setState(() => sosPressCount = 0); Navigator.pop(bc); })]));
            }
          }, child: const Icon(Icons.warning, color: Colors.white, size: 30)),
          GestureDetector(onLongPressStart: (_) => socket.emit('trigger_vibration', {'type': 'HEART_PULSE_START'}), onLongPressEnd: (_) => socket.emit('trigger_vibration', {'type': 'HEART_PULSE_STOP'}), child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.pink.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.pinkAccent)), child: const Icon(Icons.favorite, color: Colors.pinkAccent, size: 50))),
        ]),
        const SizedBox(height: 30),

        // 👇👇👇 YAHAN NAYA CODE PASTE KAREIN 👇👇👇
        if (_isLiveTracking) ...[
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              icon: const Icon(Icons.cancel, color: Colors.white),
              label: const Text("STOP LIVE TRACKING & ALARM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
              onPressed: _stopLiveTracking,
            ),
          ),
          const SizedBox(height: 30),
        ],
        // 👆👆👆 NAYA CODE YAHAN KHATAM 👆👆👆

        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("COMMAND", style: TextStyle(color: Colors.white54, fontSize: 12)),
          Row(
            children: [
              // 🚨 Agar audio attach hai, toh delete ka button dikhayein
              if (_pendingVoiceBase64 != null) 
                IconButton(icon: const Icon(Icons.delete, color: Colors.white54), onPressed: () => setState(() => _pendingVoiceBase64 = null)),
              
              IconButton(
                // 🚨 Mic ka color green ho jayega agar audio attach hai
                icon: Icon(_isBossRecording ? Icons.stop_circle : (_pendingVoiceBase64 != null ? Icons.mic : Icons.mic_none), 
                color: _isBossRecording ? Colors.red : (_pendingVoiceBase64 != null ? Colors.greenAccent : Colors.pinkAccent)), 
                onPressed: _toggleBossVoice
              )
            ],
          )
        ]),
        TextField(controller: _msgController, maxLines: 3, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: _isBossRecording ? "RECORDING..." : "Enter text command...", hintStyle: const TextStyle(color: Colors.white24), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        const SizedBox(height: 30),
        const Text("DELIVERY METHOD", style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        if (!canTakeover) Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.info_outline, color: Colors.blueAccent, size: 16), SizedBox(width: 8), Expanded(child: Text("Takeover disabled. He is not 'Our Time 💑'.", style: TextStyle(color: Colors.blueAccent, fontSize: 12)))]))
        else SwitchListTile(title: const Text("Forced Screen Takeover", style: TextStyle(color: Colors.white)), subtitle: Text(isForcedOverlay ? "Locks his screen." : "Notification only.", style: const TextStyle(color: Colors.white54, fontSize: 12)), value: isForcedOverlay, activeColor: Colors.pinkAccent, onChanged: (val) => setState(() => isForcedOverlay = val), contentPadding: EdgeInsets.zero),
        const SizedBox(height: 20),
        if (canTakeover) ...[
          const Text("RELEASE REQUIREMENT / ACTION", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: CommandScreen.releaseCondition, isExpanded: true, dropdownColor: Colors.grey[900], style: const TextStyle(color: Colors.white, fontSize: 16), items: ["Check-In Button", "Voice (Record)" , "Manual (Only I release)", "Proof (Photo)"].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(), onChanged: (newVal) => setState(() => CommandScreen.releaseCondition = newVal!)))),
        ],
        const SizedBox(height: 40),
        SizedBox(width: double.infinity, height: 60, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: (canTakeover && isForcedOverlay) ? Colors.red[800] : Colors.pink[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _executeCommand, child: Text((canTakeover && isForcedOverlay) ? "INITIATE LOCKDOWN" : "SEND COMMAND", style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.bold)))),
      ],
    );
  }
}