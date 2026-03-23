import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:async'; // 👈 Yeh lazmi hai
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Notification ke liye
import 'package:socket_io_client/socket_io_client.dart' as IO;


class VaultScreen extends StatefulWidget {
  final IO.Socket socket;
  const VaultScreen({super.key, required this.socket});

  @override
  _VaultScreenState createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  Timer? _expiryChecker;

  @override
  void initState() {
    super.initState();
    _startExpiryChecker();
  }

  @override
  void dispose() {
    _expiryChecker?.cancel(); // 👈 Screen band ho toh timer ruk jaye
    super.dispose();
  }

  void _startExpiryChecker() {
    _expiryChecker = Timer.periodic(const Duration(minutes: 1), (timer) async {
      var snapshot = await _db.collection('tasks').where('isActive', isEqualTo: true).get();
      DateTime now = DateTime.now();

      for (var doc in snapshot.docs) {
        var data = doc.data();

        int taskYear = now.year;
int taskMonth = now.month;
int taskDay = now.day;

// Agar Boss ne koi specific date di hai toh wo set karo
if (data['date'] != null) {
  List<String> dateParts = data['date'].split('-');
  taskYear = int.parse(dateParts[0]);
  taskMonth = int.parse(dateParts[1]);
  taskDay = int.parse(dateParts[2]);
}
        List<String> timeParts = data['time'].split(':');
        
        
        DateTime taskTime = DateTime(taskYear, taskMonth, taskDay, int.parse(timeParts[0]), int.parse(timeParts[1]));
        int graceMinutes = data['gracePeriod'] ?? 60;
        DateTime expirationTime = taskTime.add(Duration(minutes: graceMinutes));

        // ✅ Theek kiya hua logic
        int minutesLeft = expirationTime.difference(now).inMinutes;

        
        Timestamp? lastCompTs = data['lastCompleted'] as Timestamp?;
            bool isDoneCurrentPeriod = false;
            String freq = data['frequency'] ?? 'Daily';

            if (lastCompTs != null) {
              DateTime lastDate = lastCompTs.toDate();
              DateTime now = DateTime.now();

              if (freq == 'One-Time') {
                isDoneCurrentPeriod = true;
              } else if (freq == 'Hourly') {
                if (lastDate.year == now.year && lastDate.month == now.month && lastDate.day == now.day && lastDate.hour == now.hour) isDoneCurrentPeriod = true;
              } else if (freq == 'Daily') {
                if (lastDate.year == now.year && lastDate.month == now.month && lastDate.day == now.day) isDoneCurrentPeriod = true;
              } else if (freq == 'Weekly') {
                // Agar 7 din ke andar hai aur hafte ka din (e.g. Monday se Tuesday) aage barha hai toh same week hai
                if (now.difference(lastDate).inDays < 7 && now.weekday >= lastDate.weekday) isDoneCurrentPeriod = true;
              } else if (freq == 'Monthly') {
                if (lastDate.year == now.year && lastDate.month == now.month) isDoneCurrentPeriod = true;
              }
            }

        

        // Agar 5 min reh gaye aur task done NAYI hua
        if (minutesLeft == 5 && now.isAfter(taskTime) && !isDoneCurrentPeriod) {
          _showWarningNotification(data['title']);
        }
        // Agar task poori tarah miss ho gaya hai (Expiration time guzar gaya)
        if (now.isAfter(expirationTime) && !isDoneCurrentPeriod) {
          
          // 🔥 1. DATABASE SE TASK KI APNI PENALTY NIKALEIN 🔥
          int taskPenalty = data['penalty'] ?? 5; // Agar purana task hai jisme penalty nahi, toh default 5 dega
          
          // 2. Task ko Inactive kar do
          await _db.collection('tasks').doc(doc.id).update({'isActive': false});

          // 3. Custom Saza (Oopsie Points) de do
          var subStationDoc = _db.collection('users').doc('sub_station');
          await _db.runTransaction((transaction) async {
            var snap = await transaction.get(subStationDoc);
            int currentDemerits = snap.data()?['punishmentPoints'] ?? 0;
            // 🚨 Ab yahan custom penalty add hogi
            transaction.update(subStationDoc, {'punishmentPoints': currentDemerits + taskPenalty}); 
          });

          // 4. Local phone par notification bhi custom penalty ke sath
          FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
          const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
            'penalty_warnings', 'Penalties',
            importance: Importance.max, priority: Priority.high, color: Colors.red
          );
          await plugin.show(
            id: DateTime.now().millisecond, 
            title: "⚠️ TASK MISSED! PENALTY APPLIED!", 
            body: "You missed '${data['title']}'. +$taskPenalty Oopsie Points added.", // 👈 Yahan bhi custom penalty aayegi
            notificationDetails: const NotificationDetails(android: androidDetails)
          );
        }
      }
    });
  }

  // Chota sa local notification function
  Future<void> _showWarningNotification(String taskName) async {
    FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'task_warnings', 'Task Warnings',
      importance: Importance.max, priority: Priority.high, color: Colors.orange
    );
    await plugin.show(
      id: DateTime.now().millisecond, 
      title: "⚠️ TASK EXPIRING SOON!", 
      body: "You have 5 minutes left to complete: $taskName", 
      notificationDetails: const NotificationDetails(android: androidDetails)
    );
  }

  // ==== TASK COMPLETION LOGIC ====
  // ==== TASK COMPLETION LOGIC ====
  // ==== TASK COMPLETION LOGIC ====
  Future<void> _handleTaskCompletion(String taskId, Map<String, dynamic> taskData) async {
    bool needsProof = taskData['requiresProof'] ?? false;
    String verificationType = taskData['verificationType'] ?? (needsProof ? "Photo Proof" : "Direct Done");
    int points = taskData['points'] ?? 0;
    String title = taskData['title'] ?? 'Task';

    // ---------------------------------------------------------
    // TYPE 1: DIRECT DONE
    // ---------------------------------------------------------
    if (verificationType == "Direct Done") {
      var docRef = _db.collection('users').doc('sub_station');
      await _db.runTransaction((transaction) async {
        var snap = await transaction.get(docRef);
        int currentPoints = snap.data()?['rewardPoints'] ?? 0;
        transaction.update(docRef, {'rewardPoints': currentPoints + points});
      });
      
      if (taskData['frequency'] == 'One-Time') {
        await _db.collection('tasks').doc(taskId).update({'isActive': false});
      } else {
        await _db.collection('tasks').doc(taskId).update({'lastCompleted': FieldValue.serverTimestamp()});
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Task Checked! +$points Pts 🌟'), backgroundColor: Colors.green));
    } 
    
    // ---------------------------------------------------------
    // TYPE 2: PHOTO PROOF
    // ---------------------------------------------------------
    else if (verificationType == "Photo Proof") {
      try {
        final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
        if (photo != null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading proof... ⏳'), backgroundColor: Colors.blueGrey));
          List<int> imageBytes = await File(photo.path).readAsBytes();
          String base64Image = base64Encode(imageBytes);

          await _db.collection('pending_proofs').add({
            'taskId': taskId,
            'taskTitle': title,
            'taskPoints': points,
            'taskPenalty': taskData['penalty'] ?? 5,
            'mediaUrl': base64Image,
            'status': 'pending',
            'submittedAt': FieldValue.serverTimestamp(),
          });

          await _db.collection('tasks').doc(taskId).update({'lastCompleted': FieldValue.serverTimestamp()});

          widget.socket.emit('trigger_vibration', {
        'type': 'OVERLAY_COMMAND', 
        'delivery': 'NOTIFICATION', 
        'release_type': 'Manual (Only I release)', 
        'message': '🔔 PENDING APPROVAL: Imad marked "${taskData['title']}" as done! Open Inbox to verify.',
        'priority': 'HIGH'
      });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proof Sent to Her Inbox 📥'), backgroundColor: Colors.blueAccent));
          
        }
      } catch (e) {
        print("Camera Error: $e");
      }
    }

    // ---------------------------------------------------------
    // TYPE 3: APPROVAL REQUIRED (Bina photo ke Inbox mein)
    // ---------------------------------------------------------
    else if (verificationType == "Approval Required") {
      await _db.collection('pending_proofs').add({
        'taskId': taskId,
        'taskTitle': title,
        'taskPoints': points,
        'taskPenalty': taskData['penalty'] ?? 5,
        'mediaUrl': null, // Photo nahi chahiye
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      });

      

      await _db.collection('tasks').doc(taskId).update({'lastCompleted': FieldValue.serverTimestamp()});

      // NOTE: Aapki app mein filhal Socket connection seedha VaultScreen mein available nahi hai.
      // Toh hum yahan se ek chota sa Snackbar dikha denge. 
      // (Asal Ping bhejni hai toh hume VaultScreen mein Socket import karna parega).
      widget.socket.emit('trigger_vibration', {
        'type': 'OVERLAY_COMMAND', 
        'delivery': 'NOTIFICATION', 
        'release_type': 'Manual (Only I release)', 
        'message': '🔔 PENDING APPROVAL: Imad marked "${taskData['title']}" as done! Open Inbox to verify.',
        'priority': 'HIGH'
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request sent! Waiting for Her approval 👑"), backgroundColor: Colors.orange)
        
      );
      
    }
  }

  // ==== REWARD REDEMPTION LOGIC ====
  Future<void> _buyReward(Map<String, dynamic> rewardData) async {
    int price = rewardData['price'] ?? 0;
    String title = rewardData['title'] ?? 'Reward';

    var docRef = _db.collection('users').doc('sub_station');
    var snap = await docRef.get();
    if (!snap.exists) return;
    
    int currentPoints = snap.data()?['rewardPoints'] ?? 0;

    if (currentPoints >= price) {
      // Points Deduct Karo
      await docRef.update({'rewardPoints': currentPoints - price});
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchased: $title! 🎉 Enjoy.'), backgroundColor: Colors.green)
      );
    } else {
      // Insufficient Points
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not enough points! You need $price pts.'), backgroundColor: Colors.redAccent)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, 
      child: Scaffold(
        backgroundColor: const Color(0xFF050505), // Ultra Dark Hacker Theme
        appBar: AppBar(
          title: const Text("OUR LOVE HUB 💖", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 3, fontSize: 18)),
          backgroundColor: const Color(0xFF121212),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 5,
          shadowColor: Colors.pinkAccent.withOpacity(0.2),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(130.0),
            child: Column(
              children: [
                _buildLivePointsBar(),
                const TabBar(
                  indicatorColor: Colors.pinkAccent,
                  indicatorWeight: 3,
                  labelColor: Colors.pinkAccent,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  tabs: [
                    Tab(icon: Icon(Icons.check_box_outlined), text: "ACTIVE TASKS"),
                    Tab(icon: Icon(Icons.diamond_outlined), text: "REWARDS"),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildTasksList(),
            _buildRewardsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildLivePointsBar() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc('sub_station').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(color: Colors.pinkAccent));
        }
        
        var data = snapshot.data!.data() as Map<String, dynamic>;
        int rewards = data['rewardPoints'] ?? 0;
        int demerits = data['punishmentPoints'] ?? 0;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.grey[900]!, Colors.black],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 5))
            ]
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text("REWARD POINTS", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(height: 5),
                  Text("$rewards", style: const TextStyle(color: Colors.greenAccent, fontSize: 32, fontWeight: FontWeight.w900)),
                ],
              ),
              Container(height: 50, width: 1, color: Colors.white12), 
              Column(
                children: [
                  const Text("DEMERITS", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(height: 5),
                  Text("$demerits", style: const TextStyle(color: Colors.redAccent, fontSize: 32, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTasksList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('tasks').where('isActive', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No active tasks from Amore. Enjoy the peace.", style: TextStyle(color: Colors.white54)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var data = doc.data() as Map<String, dynamic>;
            bool needsProof = data['requiresProof'] ?? false;
            
            // 🔥 NAYA: TIME LOCK & DONE LOGIC 🔥
            DateTime now = DateTime.now();
            Timestamp? lastCompTs = data['lastCompleted'] as Timestamp?;
            bool isDoneCurrentPeriod = false;

            String freq = data['frequency'] ?? 'Daily';
            if (lastCompTs != null) {
              DateTime lastDate = lastCompTs.toDate();
              if (freq == 'One-Time') {
                isDoneCurrentPeriod = true;
              } else if (freq == 'Hourly') {
                if (lastDate.year == now.year && lastDate.month == now.month && lastDate.day == now.day && lastDate.hour == now.hour) isDoneCurrentPeriod = true;
              } else if (freq == 'Daily') {
                if (lastDate.year == now.year && lastDate.month == now.month && lastDate.day == now.day) isDoneCurrentPeriod = true;
              } else if (freq == 'Weekly') {
                if (now.difference(lastDate).inDays < 7 && now.weekday >= lastDate.weekday) isDoneCurrentPeriod = true;
              } else if (freq == 'Monthly') {
                if (lastDate.year == now.year && lastDate.month == now.month) isDoneCurrentPeriod = true;
              }
            }

            int taskYear = now.year;
int taskMonth = now.month;
int taskDay = now.day;

// Agar Boss ne koi specific date di hai toh wo set karo
if (data['date'] != null) {
  List<String> dateParts = data['date'].split('-');
  taskYear = int.parse(dateParts[0]);
  taskMonth = int.parse(dateParts[1]);
  taskDay = int.parse(dateParts[2]);
}

List<String> timeParts = data['time'].split(':');
DateTime taskTime = DateTime(taskYear, taskMonth, taskDay, int.parse(timeParts[0]), int.parse(timeParts[1]));
            int graceMinutes = data['gracePeriod'] ?? 60; 
            DateTime expirationTime = taskTime.add(Duration(minutes: graceMinutes));

            bool isTooEarly = now.isBefore(taskTime);
            bool isMissed = now.isAfter(expirationTime) && !isDoneCurrentPeriod; // Agar done ho gaya toh missed nahi mana jayega!
            bool canDoTask = !isTooEarly && !isMissed && !isDoneCurrentPeriod; // Button tabhi chalega jab teeno false hon

            String verificationType = data['verificationType'] ?? (needsProof ? "Photo Proof" : "Direct Done");
            String btnText = "MARK AS DONE";
            Color? btnColor = needsProof ? Colors.blueAccent[700] : Colors.green[700];
            IconData btnIcon = needsProof ? Icons.camera_alt : Icons.check_circle;

            if (isDoneCurrentPeriod) {
              btnText = data['frequency'] == 'One-Time' ? "WAITING FOR APPROVAL" : "DONE FOR TODAY";
              btnColor = Colors.grey[800];
              btnIcon = Icons.done_all;
            } else if (isTooEarly) {
              btnText = "UNLOCKS AT ${data['time']}";
              btnColor = Colors.grey[800];
              btnIcon = Icons.lock_clock;
            } else if (isMissed) {
              btnText = "MISSED (EXPIRED)";
              btnColor = Colors.red[900];
              btnIcon = Icons.error;
            } else {
              // 🚨 BUTTON TYPE DECIDER 🚨
              if (verificationType == "Photo Proof") {
                btnText = "SEND PROOF TO INBOX";
                btnColor = Colors.blueAccent[700];
                btnIcon = Icons.camera_alt;
              } else if (verificationType == "Approval Required") {
                btnText = "REQUEST VERIFICATION";
                btnColor = Colors.orange[800];
                btnIcon = Icons.gavel;
              } else {
                btnText = "MARK AS DONE";
                btnColor = Colors.green[700];
                btnIcon = Icons.check_circle;
              }
            }

            return Card(
              color: const Color(0xFF1A1A1A),
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15), 
                side: BorderSide(color: isTooEarly ? Colors.grey : (isMissed ? Colors.red : (needsProof ? Colors.blueAccent : Colors.greenAccent)).withOpacity(0.3))
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(data['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: Text("+${data['points']} pts", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("Time: ${data['time']} (Grace: $graceMinutes mins)", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton.icon(
                        // Agar early hai ya missed hai toh button disabled (null) ho jayega
                        onPressed: canDoTask ? () => _handleTaskCompletion(doc.id, data) : null,
                        icon: Icon(btnIcon, color: Colors.white, size: 20),
                        label: Text(btnText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: btnColor,
                          disabledBackgroundColor: btnColor, // Disabled hone par bhi color maintain rakhega
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRewardsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('rewards').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No rewards available yet.", style: TextStyle(color: Colors.white54)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            
            return Card(
              color: const Color(0xFF1A1A1A),
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.pinkAccent.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.diamond, color: Colors.pinkAccent, size: 28)
                ),
                title: Text(data['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text("Cost: ${data['price']} Points", style: const TextStyle(color: Colors.white54)),
                ),
                trailing: ElevatedButton(
                  onPressed: () => _buyReward(data),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, 
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                  ),
                  child: const Text("REDEEM", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}