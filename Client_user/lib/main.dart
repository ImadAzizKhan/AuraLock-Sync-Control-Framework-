import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vibration/vibration.dart';
import 'package:quick_actions/quick_actions.dart'; 
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:camera/camera.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as OWindow;
import 'package:audioplayers/audioplayers.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/vault_screen.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// --- GLOBAL VARIABLES ---
final StreamController<String> selectNotificationStream = StreamController<String>.broadcast();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final AudioPlayer _audioPlayer = AudioPlayer();


// Intensity Mapping
Map<String, int> intensityMap = {
  "Busy": 0,
  "Sleeping": 64,   
  "Class": 127,     
  "Our Time 💑": 255 
};

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'btn_class') FlutterForegroundTask.sendDataToMain("Class");
    if (id == 'btn_busy') FlutterForegroundTask.sendDataToMain("Busy");
    if (id == 'btn_sleep') FlutterForegroundTask.sendDataToMain("Sleeping");
    if (id == 'btn_feet') FlutterForegroundTask.sendDataToMain("Our Time 💑");
  }
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LockdownOverlayScreen(),
  ));
}

void main() async {
  
  WidgetsFlutterBinding.ensureInitialized(); // Yeh line lazmi hai Firebase ke liye
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort(); 

  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings, 
    onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
      if (notificationResponse.payload != null) {
        selectNotificationStream.add(notificationResponse.payload!);
      }
    },
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LocketApp(),
  ));
}

class LocketApp extends StatefulWidget {
  const LocketApp({super.key});
  @override
  State<LocketApp> createState() => _LocketAppState();
}

class _LocketAppState extends State<LocketApp> {
  final String serverUrl = 'https://YOUR-RENDER-URL.onrender.com'; 
  late IO.Socket socket;

  bool _isHerInDanger = false;
  double? _herLat;
  double? _herLng;
  double? _herSpeed;
  String _lastLocationUpdate = "";
  
  String statusText = "Connecting...";
  Color statusColor = Colors.orange;
  String myMode = "Our Time 💑"; 
  final TextEditingController _replyController = TextEditingController();
  final QuickActions quickActions = const QuickActions();
  
  List<Map<String, dynamic>> incomingLogs = [];
  List<Map<String, dynamic>> busyQueue = []; 

  bool isUnderLockdown = false;
  String trapMode = "";

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    Health().configure();
    _setupHomeShortcuts(); 
    _initForegroundTask();
    _connectToSocketServer();
    _startForegroundService();
    _checkHealthPermission();
    _checkOverlayPermission();
    FirebaseMessaging.instance.subscribeToTopic('substation_device');
    [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();

    OWindow.FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data == "CHECK_IN_REQUEST") {
        socket.emit('trigger_vibration', {
          'type': 'LOG_ENTRY', 
          'message': '✅ Imad Checked-In: User is Active.'
        });
        setState(() {
          incomingLogs.insert(0, {'content': 'You: ✅ Checked In', 'time': _timeNow()});
        });
        await OWindow.FlutterOverlayWindow.shareData("WAITING_MODE|Check-In Button");
      }
    });
    
    selectNotificationStream.stream.listen((String payload) async {

      if (payload.startsWith("PUNISHMENT_")) {
        String mode = payload.split("_")[1]; // CAMERA ya VOICE ya CHECK_IN
        
        await OWindow.FlutterOverlayWindow.closeOverlay();
        setState(() {
          isUnderLockdown = true;
          trapMode = mode; // Ye mode ab seedha TrapScreen kholega
        });
      }

      else if (payload == "CAMERA" || payload == "VOICE" || payload == "CHECK_IN") {
        await OWindow.FlutterOverlayWindow.closeOverlay();
        setState(() {
          isUnderLockdown = true;
          trapMode = payload;
        });
      }
    });
  }

  String _timeNow() => "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";

  Future<void> _checkOverlayPermission() async {
    bool isGranted = await OWindow.FlutterOverlayWindow.isPermissionGranted();
    if (!isGranted) {
      await OWindow.FlutterOverlayWindow.requestPermission();
    }
  }

  Future<void> _showPunishmentNotification(String title, String body, String mode) async {
    AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'punishment_channel', 
      'Punishments',
      importance: Importance.max, 
      priority: Priority.high,
      fullScreenIntent: true, // 👈 Lock screen par bhi nazar aayega
      color: Colors.red,
      ongoing: true, // 👈 Swipe karke delete nahi ho sakega jab tak click na karein
    );
    
    await flutterLocalNotificationsPlugin.show(
      id: 0, 
      title: title, 
      body: body, 
      notificationDetails: NotificationDetails(android: androidPlatformChannelSpecifics), 
      payload: "PUNISHMENT_$mode" // 👈 Click par TrapScreen kholne ke liye
    );
  }

  Future<void> _checkHealthPermission() async {
    var types = [HealthDataType.STEPS, HealthDataType.HEART_RATE];
    var perms = [HealthDataAccess.READ, HealthDataAccess.READ]; // 🚨 YAHAN ADD KIA
    bool? hasPermissions = await Health().hasPermissions(types, permissions: perms);
    
    if (hasPermissions == true) {
      print("Health already linked.");
    }
}

  Future<void> _showLockdownNotification(String title, String body, String payload) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'lockdown_channel_silent_v2', 
      'Lockdown Alerts',
      importance: Importance.max, 
      priority: Priority.high,
      fullScreenIntent: true,
      enableLights: true,
      color: Colors.pink,
      playSound: false, 
      enableVibration: false,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecond, 
      title: title, 
      body: body, 
      notificationDetails: platformChannelSpecifics, 
      payload: payload
    );
  }

  // --- HEALTH API FINAL VERSION ---
  Future<void> _fetchAndSendHealthData() async {
    final health = Health();
    
    final types = [
      HealthDataType.STEPS,
      HealthDataType.HEART_RATE,
      HealthDataType.BLOOD_GLUCOSE,
      HealthDataType.BLOOD_OXYGEN,
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
      HealthDataType.TOTAL_CALORIES_BURNED,
      HealthDataType.SLEEP_SESSION,
    ];

    try {
      // 1. Activity Permission Check
      await Permission.activityRecognition.request();
      
      // 2. Auth Check
      bool authorized = await health.requestAuthorization(types);

      if (!authorized) {
        socket.emit('trigger_vibration', {
          'type': 'HEALTH_DATA', 
          'message': '❌ Access Denied: Sub-station did not grant health permissions.'
        });
        return;
      }

      // 3. Fetch Data (Last 24 Hours)
      DateTime now = DateTime.now();
      DateTime yesterday = now.subtract(const Duration(days: 1));

      // Steps (Aggregate total)
      int? steps = await health.getTotalStepsInInterval(yesterday, now);
      
      // All other points
      List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
        startTime: yesterday, 
        endTime: now, 
        types: types
      );

      // 4. Extract Latest Values
      String hr = "N/A", glu = "N/A", ox = "N/A", bpSys = "", bpDia = "", cal = "N/A";

      for (var p in healthData) {
        String val = p.value.toString();
        if (p.type == HealthDataType.HEART_RATE) hr = "$val BPM";
        if (p.type == HealthDataType.BLOOD_GLUCOSE) glu = "$val mg/dL";
        if (p.type == HealthDataType.BLOOD_OXYGEN) ox = "$val%";
        if (p.type == HealthDataType.TOTAL_CALORIES_BURNED) cal = "$val kcal";
        if (p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC) bpSys = val;
        if (p.type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC) bpDia = val;
      }

      String bpFinal = (bpSys.isNotEmpty && bpDia.isNotEmpty) ? "$bpSys/$bpDia mmHg" : "N/A";

      // 5. Construct Professional Report
      String report = """
📊 -- SUB-STATION REPORT --
🚶‍♂️ Steps (24h): ${steps ?? 0}
💓 Heart Rate: $hr
🩺 Blood Pressure: $bpFinal
🔥 Calories: $cal
🩸 Glucose: $glu
🌬️ Blood Oxygen: $ox
________________________
🕒 Last Sync: ${_timeNow()}
""";

      // 6. Send to Boss
      socket.emit('trigger_vibration', {'type': 'HEALTH_DATA', 'message': report});

      setState(() {
        incomingLogs.insert(0, {'content': '📊 Health vitals sent to Boss.', 'time': _timeNow()});
      });

    } catch (e) {
      print("Sync Error: $e");
      socket.emit('trigger_vibration', {'type': 'HEALTH_DATA', 'message': '⚠️ Sync Failed: $e'});
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery, 
        imageQuality: 50, 

      );
      
      if (photo != null) {
        List<int> imageBytes = await File(photo.path).readAsBytes();
        String base64Image = base64Encode(imageBytes);
        
        socket.emit('proof_submitted', {'image': base64Image, 'isProof': false});
        
        setState(() {
          incomingLogs.insert(0, {
            'type': 'photo',
            'content': '📸 You sent a photo.',
            'image': base64Image,
            'time': _timeNow()
          }); 
        }); 
      }
    } catch (e) {
      // Agar double tap ho jaye ya picker stuck ho jaye toh app crash nahi hogi!
      print("Image Picker Error: $e");
    }
  }

  Future<void> _toggleRecording() async {
    if (await Permission.microphone.request().isGranted) {
      if (_isRecording) {
        String? path = await _audioRecorder.stop();
        setState(() => _isRecording = false);
        if (path != null) {
          
        
          List<int> audioBytes = await File(path).readAsBytes();
          String base64Audio = base64Encode(audioBytes);
          socket.emit('proof_submitted', {'audio': base64Audio, 'isProof': false}); 
          socket.emit('trigger_vibration', {'type': 'REPLY', 'message': '🎤 Voice note sent.'});
          setState(() {
            incomingLogs.insert(0, {
              'type': 'voice',
              'content': '🎤 You sent a voice note.',
              'audio': base64Audio,
              'time': _timeNow()
            });
          });
        }
      } else {
        Directory tempDir = await getTemporaryDirectory();
        String path = '${tempDir.path}/voice_note.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      }
    }
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'locket_foreground', channelName: 'Locket System',
        channelImportance: NotificationChannelImportance.LOW, priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), 
        autoRunOnBoot: true, allowWakeLock: true, allowWifiLock: true,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  void _onReceiveTaskData(Object data) {
    if (data is String && mounted) _setMode(data); 
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _replyController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _startForegroundService() async {
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.restartService();
    } else {
      FlutterForegroundTask.startService(
        notificationTitle: 'Locket Connected', notificationText: 'Current Mode: $myMode',
        notificationButtons: [
          const NotificationButton(id: 'btn_class', text: 'Class'),
          const NotificationButton(id: 'btn_busy', text: 'Busy'),
          const NotificationButton(id: 'btn_sleep', text: 'Sleep'),
          const NotificationButton(id: 'btn_feet', text: 'Feet'),
        ],
        callback: startCallback,
      );
    }
  }

  void _setupHomeShortcuts() {
    quickActions.initialize((String shortcutType) {
      if (mounted) _setMode(shortcutType);
    });
    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(type: 'Class', localizedTitle: '📘 Class'),
      const ShortcutItem(type: 'Busy', localizedTitle: '🟠 Busy'),
      const ShortcutItem(type: 'Sleeping', localizedTitle: '🟣 Sleeping'),
      const ShortcutItem(type: 'Our Time 💑', localizedTitle: '💖 Our Time 💑'),
    ]);
  }

  void _connectToSocketServer() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket', 'polling'], 'autoConnect': true,
    });

    socket.onConnect((_) {
      if (mounted) {
        setState(() { statusText = "Sub-Station Active"; statusColor = Colors.green; });
        socket.emit('register', 'substation');
        socket.emit('update_status', {'mode': myMode}); 
      }
    });

    socket.on('danger_location', (data) {
      if (!mounted) return;
      setState(() {
        _isHerInDanger = true;
        _herLat = (data['latitude'] as num?)?.toDouble();
        _herLng = (data['longitude'] as num?)?.toDouble();
        _herSpeed = (data['speed'] as num?)?.toDouble() ?? 0.0;
        
        // Time ko thora saaf kar ke dikhane ke liye
        DateTime now = DateTime.now();
        _lastLocationUpdate = "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      });
    });

    socket.on('vibrate_signal', (data) async {

      

      if (data['type'] == 'MSG' && data['message'].contains('Danger Mode Deactivated')) {
        if (!mounted) return;
        setState(() {
          _isHerInDanger = false; // Danger radar screen se hata do
        });
      }

      String type = data['type'] ?? "";
      String msg = data['message'] ?? "";
      String releaseRequirement = data['release_type'] ?? "Manual";
      String deliveryMode = data['delivery'] ?? "OVERLAY";
      int intensity = intensityMap[myMode] ?? 100;

      if (type == 'REQUEST_STATUS') {
        // Boss app ne status maanga hai, apna current mode bhej do
        socket.emit('update_status', {'mode': myMode});
        return;
      }
      
      if (type == 'REQUEST_HEALTH') {
        _fetchAndSendHealthData();
        return;
      }

      if (type == 'SOS_ALARM') {
        Vibration.vibrate(duration: 10000, amplitude: 255);
        // 👇 Naya Volume Controller Logic
        await FlutterVolumeController.updateShowSystemUI(false); 
        await FlutterVolumeController.setVolume(0.8); // 80% Volume
        _showLockdownNotification("🚨 DANGER ALERT", "Amore has triggered the SOS Radar!", "DANGER");

        await _audioPlayer.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              usageType: AndroidUsageType.alarm, 
              contentType: AndroidContentType.music,
              audioFocus: AndroidAudioFocus.gainTransient,
            ),
          ),
        );
        await _audioPlayer.play(AssetSource('raw/emergency.mp3'));
        return;
      }

      if (type == 'HEART_PULSE_START') {
        if (myMode == "Busy") {
          return;
        } else if (myMode == "Sleeping") {
          // 👇 Naya Volume Controller Logic
          await FlutterVolumeController.updateShowSystemUI(false);
          await FlutterVolumeController.setVolume(0.3); // 30% volume

          await _audioPlayer.setAudioContext(
            AudioContext(
              android: AudioContextAndroid(
                usageType: AndroidUsageType.alarm, 
                contentType: AndroidContentType.music,
                audioFocus: AndroidAudioFocus.gainTransientMayDuck,
              ),
            ),
          );
          await _audioPlayer.play(AssetSource('raw/sleep_whisper.mp3'));
        }
        else if (myMode == "Class") Vibration.vibrate(duration: 10000, amplitude: 10);
        else if (myMode == "Our Time 💑") Vibration.vibrate(duration: 10000, amplitude: 255);
        return;
      }
      
      if (type == 'HEART_PULSE_STOP') {
        Vibration.cancel();
        if (myMode == "Sleeping") await _audioPlayer.stop(); 
        return;
      }

      if (myMode == "Busy" && type == 'OVERLAY_COMMAND') {
        busyQueue.add(data);
        setState(() => incomingLogs.insert(0, {'content': '📥 Queued: $msg', 'time': _timeNow()}));
        return;
      }

      // 🚨 REPLACED BLOCK FOR AUDIO & LOGGING 🚨
      if (mounted) {
        bool hasAudio = data.containsKey('audio') && data['audio'] != null;
        
        // 1. Agar Audio hai toh process karo
        if (hasAudio) {
          try {
            String cleanAudio = data['audio'].toString().replaceAll(RegExp(r'\s+'), '');
            Uint8List bytes = base64Decode(cleanAudio);
            Directory tempDir = await getTemporaryDirectory();
            File tempFile = File('${tempDir.path}/boss_incoming_audio.m4a');
            await tempFile.writeAsBytes(bytes);

            // Agar Overlay mode hai toh full volume par Auto-Play karo
            if (deliveryMode == 'OVERLAY') {
              print("🚨 OVERLAY MODE: Auto-playing Boss Voice!");
              await _audioPlayer.setVolume(1.0);
              await _audioPlayer.play(DeviceFileSource(tempFile.path));
            }
          } catch (e) {
            print("⚠️ Audio processing error: $e");
          }
        }

        // 2. Log mein insert karo (Text aur Audio dono handle karega)
        if (msg.isNotEmpty || hasAudio) {
          setState(() {
            incomingLogs.insert(0, {
              'content': msg.isNotEmpty ? msg : '🎤 Voice Instruction',
              'audio': data['audio'],
              'isForced': deliveryMode == 'OVERLAY',
              'time': _timeNow()
            });
          });
          
          if (type != 'OVERLAY_COMMAND') {
            FlutterForegroundTask.updateService(notificationTitle: 'Message from Amore:', notificationText: msg.isNotEmpty ? msg : 'New Voice Note');
          }
        }
      }

      if (type == 'OVERLAY_COMMAND') {
        if (myMode != "Our Time 💑" && myMode != "Class" && myMode != "Sleeping") {
          setState(() => incomingLogs.insert(0, {'content': '⚠️ Lockdown Blocked by Mode', 'time': _timeNow()}));
        } else {
          
          // 1. Agar 'Our Time' hai toh Overlay dikhao
          if (deliveryMode == 'OVERLAY' && myMode == "Our Time 💑") {
            bool isActive = await OWindow.FlutterOverlayWindow.isActive();
            if (!isActive) {
              await OWindow.FlutterOverlayWindow.showOverlay(
                flag: OWindow.OverlayFlag.focusPointer, height: -1, width: -1,
              );
            }
            OWindow.FlutterOverlayWindow.shareData("$msg|$releaseRequirement");
          } else {
            // Notification bar update
            FlutterForegroundTask.updateService(notificationTitle: 'BOSS COMMAND:', notificationText: msg);
            if (intensity > 0) Vibration.vibrate(duration: 400, amplitude: intensity);
          }

          // 2. Decide karo TrapScreen ka mode kya hoga
          String tMode = "CHECK_IN";
          if (releaseRequirement.contains("Proof")) {
            tMode = "CAMERA";
          } else if (releaseRequirement.contains("Voice")) tMode = "VOICE";

          // 3. 🚨 SIRF EK NOTIFICATION DIKHAO (Jo click par TrapScreen khole)
          // Hum naya logic use kar rahe hain jo seedha Trap khole
          _showPunishmentNotification("⚠️ COMMAND FROM BOSS", msg, tMode);

          // Voice playback for sleeping mode
          if (myMode == "Sleeping") {
             await _audioPlayer.play(AssetSource('raw/sleep_whisper.mp3'));
          }
        }
      }

      if (type == 'RELEASE_OVERLAY') {
        await OWindow.FlutterOverlayWindow.closeOverlay();
        if (mounted) setState(() { isUnderLockdown = false; trapMode = ""; });   
        Vibration.cancel();
      }
      
      if (myMode == "Sleeping" && type == 'OVERLAY_COMMAND') {
         await _audioPlayer.play(AssetSource('raw/sleep_whisper.mp3'));
      }
    });

    socket.onDisconnect((_) {
      if (mounted) setState(() { statusColor = Colors.red; statusText = "Offline"; });
    });
  }

  void _setMode(String newMode) {
    String oldMode = myMode;
    setState(() {
      myMode = newMode;
      FlutterForegroundTask.updateService(notificationTitle: 'Sub-Station Active', notificationText: 'Current Mode: $myMode');
    });
    socket.emit('update_status', {'mode': newMode});

    if (oldMode == "Busy" && newMode != "Busy" && busyQueue.isNotEmpty) {
      for (var i = 0; i < busyQueue.length; i++) {
        var qData = busyQueue[i];
        Future.delayed(Duration(seconds: i * 2), () {
           _showLockdownNotification("Pending Message", qData['message'], qData['release_type'].toString().contains("Proof") ? "CAMERA" : "CHECK_IN");
        });
      }
      busyQueue.clear();
    }
  }

  void _sendReply() {
    if (_replyController.text.isNotEmpty) {
      socket.emit('trigger_vibration', {'type': 'REPLY', 'message': _replyController.text});
      setState(() => incomingLogs.insert(0, {'content': "You: ${_replyController.text}", 'time': _timeNow()}));
      _replyController.clear();
      FocusScope.of(context).unfocus(); 
    }
  }

  Future<void> _openGoogleMaps() async {
    if (_herLat == null || _herLng == null) return;
    
    // 🚨 Sahi URL: Ab isme Amore ke asli coordinates (Lat, Lng) jaayenge!
    final String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=$_herLat,$_herLng";
    final Uri uri = Uri.parse(googleMapsUrl);

    try {
      // Direct external application (Google Maps) mein open karega
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open Maps. Make sure it is installed."))
      );
    }
  }
  // 🚨 ADD THIS FUNCTION AFTER _sendReply() 🚨
  Future<void> _playManualAudio(String base64String) async {
    try {
      String cleanAudio = base64String.replaceAll(RegExp(r'\s+'), '');
      Uint8List bytes = base64Decode(cleanAudio);
      Directory tempDir = await getTemporaryDirectory();
      File tempFile = File('${tempDir.path}/boss_manual_audio.m4a');
      await tempFile.writeAsBytes(bytes);
      
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Playback Error: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isUnderLockdown) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TrapScreen(socket: socket, mode: trapMode, onRelease: () => setState(() => isUnderLockdown = false)),
      );
    }

    return WithForegroundTask(
      child: Scaffold(
        backgroundColor: Colors.black,
        // 👇 NAYA HISSA: YAHAN SE VAULT KHULEGA 👇
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text("IMAD'S 💖 LOCKET TERMINAL", style: TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 2)),
          actions: [
            IconButton(
              icon: const Icon(Icons.lock_person, color: Colors.pinkAccent),
              tooltip: "Open The Vault",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => VaultScreen(socket: socket)),
                );
              },
            )
          ],
        ),
        // 👆 NAYA HISSA YAHAN KHATAM 👆
        body: SafeArea(
          child: Column(
            children: [
              if (_isHerInDanger && _herLat != null)
                Container(
                  margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[900]?.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent, width: 2),
                    boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.warning, color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Text("DANGER PROTOCOL ACTIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text("Her Speed: ${(_herSpeed! * 3.6).toStringAsFixed(1)} km/h", style: const TextStyle(color: Colors.white)),
                      Text("Last Update: $_lastLocationUpdate", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red[900]),
                          icon: const Icon(Icons.map),
                          label: const Text("OPEN LIVE LOCATION IN MAPS", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: _openGoogleMaps,
                        ),
                      )
                    ],
                  ),
                ),
              // 👆👆👆 DANGER RADAR KHATAM 👆👆👆
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  
                  children: [
                    const Text("YOUR CURRENT STATUS", style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2)),
                    const SizedBox(height: 15),
                    Wrap(
                      spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
                      children: [
                        _buildMenuBtn("Class", Icons.school, Colors.blue),
                        _buildMenuBtn("Busy", Icons.do_not_disturb_on, Colors.orange),
                        _buildMenuBtn("Sleeping", Icons.bedtime, Colors.purple),
                        _buildMenuBtn("Our Time 💑", Icons.favorite, Colors.pink), 
                      ],
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.withOpacity(0.2),
                        side: const BorderSide(color: Colors.greenAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      icon: const Icon(Icons.sync, color: Colors.greenAccent),
                      label: const Text("Link Health Connect", style: TextStyle(color: Colors.greenAccent)),
                      onPressed: () async {
                        final health = Health();

                        // 1. All Supported Data Types
                        final types = [
                          HealthDataType.STEPS,
                          HealthDataType.HEART_RATE,
                          HealthDataType.BLOOD_GLUCOSE,
                          HealthDataType.BLOOD_OXYGEN,
                          HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
                          HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
                          HealthDataType.TOTAL_CALORIES_BURNED,
                          HealthDataType.SLEEP_SESSION,
                        ];

                        // Sab ke liye READ permission map karein
                        final perms = types
                            .map((e) => HealthDataAccess.READ)
                            .toList();

                        // 2. Activity Recognition Request (Android 14 Physical Sensors ke liye lazmi hai)
                        await Permission.activityRecognition.request();

                        try {
                          // 3. Health Connect Authorization Popup
                          bool requested = await health.requestAuthorization(
                            types,
                            permissions: perms,
                          );

                          if (requested) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "✅ All Health Vitals Linked Successfully!",
                                ),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "❌ Permissions were not fully granted.",
                                ),
                                backgroundColor: Colors.orange,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint("Health Auth Error: $e");
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("⚠️ Error: $e"),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                    Icon(Icons.wifi_tethering, color: statusColor, size: 24),
                    const SizedBox(height: 10),
                    Text(statusText, style: TextStyle(color: statusColor, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1)))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text("COMMUNICATION LOG", style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2)),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: incomingLogs.length,
                          itemBuilder: (context, index) {
                            var log = incomingLogs[index];
                            bool isMe = log['content'].toString().startsWith("You:");
                            return ListTile(
                              leading: Icon(isMe ? Icons.arrow_upward : Icons.arrow_downward, color: isMe ? Colors.white38 : Colors.pinkAccent),
                              title: Text(log['content'], style: TextStyle(color: isMe ? Colors.white54 : Colors.white)),
                              // Naya Subtitle (Audio Button ke liye)
                              subtitle: (log.containsKey('audio') && log['audio'] != null)
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: log['isForced'] == true ? Colors.red.withOpacity(0.2) : Colors.white10
                                        ),
                                        icon: Icon(
                                          log['isForced'] == true ? Icons.replay_circle_filled : Icons.play_circle_fill, 
                                          color: log['isForced'] == true ? Colors.redAccent : Colors.pinkAccent
                                        ),
                                        label: Text(
                                          log['isForced'] == true ? "Replay Forced Audio" : "Play Voice Note", 
                                          style: const TextStyle(color: Colors.white, fontSize: 12)
                                        ),
                                        onPressed: () async => await _playManualAudio(log['audio'].toString()),
                                      ),
                                    )
                                  : null, // Agar audio nahi hai toh kuch na dikhaye
                              trailing: Text(log['time'], style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.image, color: Colors.blueAccent), onPressed: _pickAndSendImage),
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _isRecording ? "Recording..." : "Message Amore...",
                          hintStyle: const TextStyle(color: Colors.white24),
                          filled: true, fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic, color: _isRecording ? Colors.red : Colors.pinkAccent), 
                      onPressed: _toggleRecording
                    ),
                    IconButton(icon: const Icon(Icons.send, color: Colors.greenAccent), onPressed: _sendReply),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuBtn(String title, IconData icon, Color color) {
    bool isSelected = myMode == title;
    return InkWell(
      onTap: () => _setMode(title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.2) : Colors.transparent, border: Border.all(color: isSelected ? color : Colors.white10), borderRadius: BorderRadius.circular(30)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 16, color: isSelected ? color : Colors.white54), const SizedBox(width: 8), Text(title, style: TextStyle(color: isSelected ? color : Colors.white54))],
        ),
      ),
    );
  }
}

class TrapScreen extends StatefulWidget {
  final IO.Socket socket;
  final String mode; 
  final VoidCallback onRelease; 
  const TrapScreen({super.key, required this.socket, required this.mode, required this.onRelease});
  @override
  State<TrapScreen> createState() => _TrapScreenState();
}

class _TrapScreenState extends State<TrapScreen> {
  String statusPhase = "INITIALIZING..."; 
  CameraController? _cameraController;
  List<CameraDescription>? cameras; 
  int selectedCameraIndex = 0; 
  final TextEditingController _msgController = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (widget.mode == "CAMERA") {
      _loadCameras();
    } else if (widget.mode == "VOICE") {
      statusPhase = "NEEDS_ACTION";
    } else {
      statusPhase = "WAITING";
      _sendCheckInLog();
    }

    widget.socket.on('vibrate_signal', (data) {
      
      if (!mounted) return; 
      if (data['type'] == 'RELEASE_OVERLAY') widget.onRelease(); 
      if (data['message'].toString().toLowerCase().contains("rejected")) {
        setState(() => statusPhase = "NEEDS_ACTION");
        Vibration.vibrate(duration: 500, amplitude: 255);
      }
    });
  }

  void _sendMessageToBoss() {
    if (_msgController.text.isEmpty) return;
    widget.socket.emit('trigger_vibration', {'type': 'REPLY', 'message': 'Lockdown Msg: ${_msgController.text}'});
    _msgController.clear();
    FocusScope.of(context).unfocus(); 
  }

  Future<void> _loadCameras() async {
    cameras = await availableCameras();
    if (cameras != null && cameras!.isNotEmpty) {
      selectedCameraIndex = cameras!.indexWhere((cam) => cam.lensDirection == CameraLensDirection.front);
      if (selectedCameraIndex == -1) selectedCameraIndex = 0;
      _initializeCamera(cameras![selectedCameraIndex]);
    }
  }

  Future<void> _initializeCamera(CameraDescription description) async {
    try {
      if (_cameraController != null) await _cameraController!.dispose();
      _cameraController = CameraController(description, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      if (mounted) setState(() => statusPhase = "NEEDS_ACTION");
    } catch (e) {
      if (mounted) setState(() => statusPhase = "CAMERA ERROR");
    }
  }

  void _toggleCamera() {
    if (cameras == null || cameras!.length < 2) return;
    selectedCameraIndex = (selectedCameraIndex + 1) % cameras!.length;
    _initializeCamera(cameras![selectedCameraIndex]);
  }

  void _sendCheckInLog() => widget.socket.emit('trigger_vibration', {'type': 'LOG_ENTRY', 'message': '✅ Substation Checked-In.'});

  @override
  void dispose() {
    _cameraController?.dispose();
    _msgController.dispose();
    _audioRecorder.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    setState(() => statusPhase = "PROCESSING");
    try {
      final XFile photo = await _cameraController!.takePicture();
      List<int> imageBytes = await File(photo.path).readAsBytes();
      String base64Image = base64Encode(imageBytes);
      
      // 🚨 CHECK KAREIN KE SIZE KITNA HAI 🚨
      print("📸 Image Base64 Size: ${base64Image.length} bytes");

      widget.socket.emit('proof_submitted', {'image': base64Encode(imageBytes), 'isProof': true});
      widget.socket.emit('trigger_vibration', {'type': 'REPLY', 'message': '📸 Photo Proof Submitted.'});
      if (mounted) setState(() => statusPhase = "WAITING");
    } catch (e) {
      if (mounted) setState(() => statusPhase = "NEEDS_ACTION"); 
    }
  }

  Future<void> _toggleVoiceRecord() async {
    if (await Permission.microphone.request().isGranted) {
      if (_isRecording) {
        String? path = await _audioRecorder.stop();
        setState(() { _isRecording = false; statusPhase = "PROCESSING"; });
        if (path != null) {
          List<int> audioBytes = await File(path).readAsBytes();
          widget.socket.emit('proof_submitted', {'audio': base64Encode(audioBytes), 'isProof': true}); 
          widget.socket.emit('trigger_vibration', {'type': 'REPLY', 'message': '🎤 Voice Proof Submitted.'});
          if (mounted) setState(() => statusPhase = "WAITING");
        }
      } else {
        Directory tempDir = await getTemporaryDirectory();
        await _audioRecorder.start(const RecordConfig(), path: '${tempDir.path}/trap_voice.m4a');
        setState(() => _isRecording = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, 
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (statusPhase == "INITIALIZING...") ...[
                    const CircularProgressIndicator(color: Colors.pinkAccent),
                    const SizedBox(height: 20),
                    const Text("OPENING LOVE KIOSK...", style: TextStyle(color: Colors.white54)),
                  ],

                  if (statusPhase == "NEEDS_ACTION") ...[
                    const Text("ATTENTION REQUIRED 💖", style: TextStyle(color: Colors.redAccent, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 4)),
                    const SizedBox(height: 30),
                    
                    if (widget.mode == "CAMERA" && _cameraController != null) ...[
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(height: 380, width: 300, decoration: BoxDecoration(border: Border.all(color: Colors.pinkAccent, width: 3), borderRadius: BorderRadius.circular(15)), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CameraPreview(_cameraController!))),
                          Padding(padding: const EdgeInsets.all(8.0), child: CircleAvatar(backgroundColor: Colors.black54, child: IconButton(icon: const Icon(Icons.flip_camera_android, color: Colors.white), onPressed: _toggleCamera))),
                        ],
                      ),
                      const SizedBox(height: 25),
                      SizedBox(width: 250, height: 60, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: _takePhoto, icon: const Icon(Icons.camera_alt, color: Colors.white), label: const Text("SEND PROOF", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
                    ],

                    if (widget.mode == "VOICE") ...[
                      GestureDetector(
                        onTap: _toggleVoiceRecord,
                        child: CircleAvatar(radius: 80, backgroundColor: _isRecording ? Colors.redAccent : Colors.pinkAccent.withOpacity(0.2), child: Icon(_isRecording ? Icons.stop : Icons.mic, size: 80, color: Colors.white)),
                      ),
                      const SizedBox(height: 20),
                      Text(_isRecording ? "RECORDING... TAP TO SEND" : "TAP TO RECORD VOICE PROOF", style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                    ],

                    const SizedBox(height: 30),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: TextField(
                        controller: _msgController, style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(hintText: "Send message to Her...", hintStyle: const TextStyle(color: Colors.white24, fontSize: 14), filled: true, fillColor: Colors.white.withOpacity(0.05), suffixIcon: IconButton(icon: const Icon(Icons.send, color: Colors.pinkAccent), onPressed: _sendMessageToBoss), border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                      ),
                    ),
                  ],

                  if (statusPhase == "WAITING") ...[const Icon(Icons.lock_clock, color: Colors.pinkAccent, size: 80), const SizedBox(height: 25), const Text("WAITING FOR HER APPROVAL...", textAlign: TextAlign.center, style: TextStyle(color: Colors.pinkAccent, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.bold)), const SizedBox(height: 40), const CircularProgressIndicator(color: Colors.pinkAccent)],
                  if (statusPhase == "PROCESSING") ...[const CircularProgressIndicator(color: Colors.white), const SizedBox(height: 25), const Text("TRANSMITTING TO COMMAND CENTER...", style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w300))],
                  if (statusPhase.contains("REJECTED")) ...[const Icon(Icons.error_outline, color: Colors.red, size: 80), const SizedBox(height: 25), Text(statusPhase, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 30), ElevatedButton(onPressed: () => setState(() => statusPhase = "NEEDS_ACTION"), child: const Text("TRY AGAIN"))],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LockdownOverlayScreen extends StatefulWidget { const LockdownOverlayScreen({super.key}); @override State<LockdownOverlayScreen> createState() => _LockdownOverlayScreenState(); }
class _LockdownOverlayScreenState extends State<LockdownOverlayScreen> {
  String bossMsg = "Screen Locked."; String type = "Manual"; bool isWaiting = false;
  @override void initState() { super.initState(); OWindow.FlutterOverlayWindow.overlayListener.listen((event) { if (event == "WAITING_MODE") { setState(() => isWaiting = true); } else { var parts = event.toString().split("|"); setState(() { bossMsg = parts[0]; type = parts[1]; isWaiting = false; }); } }); }
  @override Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black.withOpacity(0.9), body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text("COMMAND: $bossMsg", style: const TextStyle(color: Colors.white, fontSize: 20)), const SizedBox(height: 20), if (isWaiting) const CircularProgressIndicator(color: Colors.pink) else if (type == "Check-In Button") ElevatedButton(onPressed: () => OWindow.FlutterOverlayWindow.shareData("CHECK_IN_REQUEST"), child: const Text("Check In")) else if (type.contains("Proof") || type.contains("Voice")) const Text("PULL DOWN NOTIFICATION PANEL", style: TextStyle(color: Colors.blueAccent)) else const Text("Only she can release this screen.", style: TextStyle(color: Colors.white54))]))); }
}

