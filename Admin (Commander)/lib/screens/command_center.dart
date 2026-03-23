import 'dart:convert';

import '../services/firebase_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:locket_boss/main.dart';

class BossDashboard extends StatefulWidget {
  final IO.Socket socket;
  final String hisMode;

  const BossDashboard({Key? key, required this.socket, required this.hisMode})
    : super(key: key);

  @override
  _BossDashboardState createState() => _BossDashboardState();
}

class _BossDashboardState extends State<BossDashboard> {
  int _selectedIndex = 0;
  final FirebaseService _db = FirebaseService();

  // Controllers
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _taskPointsController = TextEditingController();
  final TextEditingController _rewardTitleController = TextEditingController();
  final TextEditingController _rewardPriceController = TextEditingController();
  final TextEditingController _ruleController = TextEditingController();
  final TextEditingController _punishmentTitleController =
      TextEditingController();
  final TextEditingController _punishmentPointsController =
      TextEditingController();
  final TextEditingController _taskPenaltyController = TextEditingController();

  final List<String> _titles = [
    "Manage Tasks",
    "Rewards",
    "Rules",
    "Penalties",
    "Inbox (Proofs) 📥",
  ];
  // 👈 Ye batayega ke saza di gayi hai ya nahi

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.pop(context);
  }

  Future<void> _showPointManagerDialog(
    int currentRewards,
    int currentPunishments,
  ) async {
    int pointsToAdjust = 0;
    String reason = "";
    bool isAddingReward = true; // True = Reward, False = Punishment

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          // Popup ke andar UI update karne ke liye
          builder: (context, setPopupState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Manage His Points 👑",
                style: TextStyle(color: Colors.pinkAccent),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Toggle Button (Reward ya Punishment)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ChoiceChip(
                        label: const Text("Reward 🌟"),
                        selected: isAddingReward,
                        selectedColor: Colors.green.withOpacity(0.3),
                        onSelected: (val) =>
                            setPopupState(() => isAddingReward = true),
                      ),
                      ChoiceChip(
                        label: const Text("Demerit ⚠️"),
                        selected: !isAddingReward,
                        selectedColor: Colors.red.withOpacity(0.3),
                        onSelected: (val) =>
                            setPopupState(() => isAddingReward = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Points Input
                  TextField(
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Points Amount",
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) => pointsToAdjust = int.tryParse(val) ?? 0,
                  ),
                  const SizedBox(height: 15),

                  // Reason Input
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: "Reason (Why?)",
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) => reason = val,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAddingReward ? Colors.green : Colors.red,
                  ),
                  onPressed: () async {
                    if (pointsToAdjust <= 0 || reason.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Enter valid points and a reason!"),
                        ),
                      );
                      return;
                    }

                    // Firebase Update Logic
                    var docRef = FirebaseFirestore.instance
                        .collection('users')
                        .doc('sub_station');

                    if (isAddingReward) {
                      await docRef.update({
                        'rewardPoints': FieldValue.increment(pointsToAdjust),
                      });
                    } else {
                      await docRef.update({
                        'punishmentPoints': FieldValue.increment(
                          pointsToAdjust,
                        ),
                      });
                    }

                    // 🚨 NEW: History Log mein entry save karna
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc('sub_station')
                        .collection('point_history')
                        .add({
                          'type': isAddingReward ? 'Reward' : 'Punishment',
                          'amount': pointsToAdjust,
                          'reason': reason,
                          'timestamp': FieldValue.serverTimestamp(),
                        });

                    // Aapko alert bhejna
                    widget.socket.emit('trigger_vibration', {
                      'type': 'MSG',
                      'message': isAddingReward
                          ? '🌟 You received +$pointsToAdjust Rewards: "$reason"'
                          : '⚠️ You received +$pointsToAdjust Demerits: "$reason"',
                    });

                    if (mounted) Navigator.pop(context);
                  },
                  child: Text(isAddingReward ? "Add Reward" : "Add Demerit"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onAddPressed() {
    if (_selectedIndex == 0)
      _showAddTaskSheet();
    else if (_selectedIndex == 1)
      _showAddRewardSheet();
    else if (_selectedIndex == 2)
      _showAddRuleSheet();
    else if (_selectedIndex == 3)
      _showAddPenaltiesheet();
  }

  // ==== POPUP SHEETS (Aapka purana theek code yahan hai) ====
  void _showAddTaskSheet() {
    String localVerificationType = 'Photo Proof';
    String localFrequency = 'Daily';
    int localGraceMinutes = 60; // 👈 NAYA: Default 1 hour grace period
    TimeOfDay? localTime;
    DateTime localDate = DateTime.now();
    
    _taskController.clear();
    _taskPointsController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Issue a New Task",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _taskController,
                    decoration: const InputDecoration(labelText: "Task Title"),
                  ),
                  TextField(
                    controller: _taskPointsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Reward Points",
                    ),
                  ),
                  TextField(
                    controller: _taskPenaltyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Penalty Points (If Missed)",
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ROW FOR TIME & FREQUENCY
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: localFrequency,
                          decoration: const InputDecoration(
                            labelText: "Frequency",
                          ),
                          items:
                              [
                                    'One-Time',
                                    'Hourly',
                                    'Daily',
                                    'Weekly',
                                    'Monthly',
                                  ]
                                  .map(
                                    (val) => DropdownMenuItem(
                                      value: val,
                                      child: Text(val),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) =>
                              setSheetState(() => localFrequency = val!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(
                            localTime == null
                                ? "Set Time"
                                : localTime!.format(context),
                          ),
                          onPressed: () async {
                            TimeOfDay? picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (picked != null)
                              setSheetState(() => localTime = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (localFrequency == 'One-Time')
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, color: Colors.pinkAccent),
                        label: Text("Select Date: ${localDate.day}/${localDate.month}/${localDate.year}"),
                        onPressed: () async {
                          DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: localDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setSheetState(() => localDate = picked);
                        },
                      ),
                    ),
                  const SizedBox(height: 10),



                  // 👈 NAYA: GRACE PERIOD DROPDOWN
                  DropdownButtonFormField<int>(
                    value: localGraceMinutes,
                    decoration: const InputDecoration(
                      labelText: "Grace Period (Time to complete)",
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text("1 Minutes")),
                      DropdownMenuItem(value: 5, child: Text("5 Minutes")),
                      DropdownMenuItem(value: 15, child: Text("15 Minutes")),
                      DropdownMenuItem(value: 30, child: Text("30 Minutes")),
                      DropdownMenuItem(value: 60, child: Text("1 Hour")),
                      DropdownMenuItem(value: 120, child: Text("2 Hours")),
                      DropdownMenuItem(
                        value: 1440,
                        child: Text("Full Day (24 Hrs)"),
                      ),
                    ],
                    onChanged: (val) =>
                        setSheetState(() => localGraceMinutes = val!),
                  ),

                  DropdownButtonFormField<String>(
                    value: localVerificationType,
                    decoration: const InputDecoration(
                      labelText: "Verification Type",
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: "Direct Done",
                        child: Text("No Proof (Direct Done)"),
                      ),
                      DropdownMenuItem(
                        value: "Photo Proof",
                        child: Text("Photo Proof Required"),
                      ),
                      DropdownMenuItem(
                        value: "Approval Required",
                        child: Text("Manual Approval Required"),
                      ),
                    ],
                    onChanged: (val) =>
                        setSheetState(() => localVerificationType = val!),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton(
                    onPressed: () async {
                      if (_taskController.text.isNotEmpty &&
                          _taskPointsController.text.isNotEmpty &&
                          _taskPenaltyController.text.isNotEmpty &&
                          localTime != null) {
                        String timeString =
                            "${localTime!.hour.toString().padLeft(2, '0')}:${localTime!.minute.toString().padLeft(2, '0')}";

                        // 🚨 DB SAVE WALI LINE UPDATE KI HAI (Grace period add kiya)
                        await FirebaseFirestore.instance
                            .collection('tasks')
                            .add({
                              'title': _taskController.text,
                              'points': int.parse(_taskPointsController.text),
                              'penalty': int.parse(_taskPenaltyController.text),
                              'frequency': localFrequency,
                              'time': timeString,
                              'date': "${localDate.year}-${localDate.month.toString().padLeft(2,'0')}-${localDate.day.toString().padLeft(2,'0')}",
                              'gracePeriod':
                                  localGraceMinutes, // 👈 Saved to DB
                              'verificationType': localVerificationType,
                              'createdAt': FieldValue.serverTimestamp(),
                              'isActive': true,
                            });
                        widget.socket.emit('trigger_vibration', {
                          'type': 'MSG',
                          'message':
                              '🔔 Amore has assigned a new Task: ${_taskController.text}',
                        });

                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Task Deployed! 🚀')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("Deploy Task"),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddRewardSheet() {
    _rewardTitleController.clear();
    _rewardPriceController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Add a Rewards",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _rewardTitleController,
                decoration: const InputDecoration(
                  labelText: "Reward Name (e.g., 1 Hour Gaming)",
                ),
              ),
              TextField(
                controller: _rewardPriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Price (Points)"),
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: () async {
                  if (_rewardTitleController.text.isNotEmpty &&
                      _rewardPriceController.text.isNotEmpty) {
                    await _db.createReward(
                      _rewardTitleController.text,
                      int.parse(_rewardPriceController.text),
                    );
                    widget.socket.emit('trigger_vibration', {
                      'type': 'MSG',
                      'message':
                          '⚠️ New Penalty Added: ${_punishmentTitleController.text}',
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reward Added! 🎁')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("Add Reward"),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showAddRuleSheet() {
    _ruleController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Establish a New Rule",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _ruleController,
                decoration: const InputDecoration(
                  labelText: "Rule Description",
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: () async {
                  if (_ruleController.text.isNotEmpty) {
                    await _db.createRule(_ruleController.text);
                    widget.socket.emit('trigger_vibration', {
                      'type': 'MSG',
                      'message': '📜 New Rule Established by Amore!',
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Rule Established! 📜')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("Enforce Rule"),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showAddPenaltiesheet() {
    _punishmentTitleController.clear();
    _punishmentPointsController.clear();
    bool localRequiresProof = true; // 👈 YAHAN DEFINE KIYA HAI

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          // 👈 TAAKE SWITCH KA BUTTON KAAM KARE
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Set a Punishment",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _punishmentTitleController,
                    decoration: const InputDecoration(
                      labelText: "Punishment Reason",
                    ),
                  ),
                  TextField(
                    controller: _punishmentPointsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Penalty (Demerits required)",
                    ),
                  ),

                  // 👈 YEH MISSING THA: Photo Proof Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Require Photo Proof?"),
                    value: localRequiresProof,
                    onChanged: (val) =>
                        setSheetState(() => localRequiresProof = val),
                  ),

                  const SizedBox(height: 15),
                  ElevatedButton(
                    onPressed: () async {
                      if (_punishmentTitleController.text.isNotEmpty &&
                          _punishmentPointsController.text.isNotEmpty) {
                        await _db.createPunishment(
                          _punishmentTitleController.text,
                          int.parse(_punishmentPointsController.text),
                          localRequiresProof,
                        );
                        widget.socket.emit('trigger_vibration', {
                          'type': 'MSG',
                          'message':
                              '🎁 New Reward Added: ${_rewardTitleController.text}',
                        });
                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Punishment Logged! ⚖️'),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("Apply Penalty"),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // YAHAN FIX KIYA HAI: _pages ko build se bahar nikal diya!
  List<Widget> get _pages => [
    // 1. TASKS LIST
    StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return const Center(child: Text("No tasks deployed yet."));

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: const Icon(Icons.task_alt, color: Colors.deepPurple),
                title: Text(
                  data['title'] ?? 'Unknown Task',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text("${data['frequency']} • ${data['time']}"),
                // 👇 YAHAN SE CHANGE KIYA HAI 👇
                trailing: Row(
                  mainAxisSize:
                      MainAxisSize.min, // 🚨 Yeh lazmi hai warna error aayega
                  children: [
                    Chip(
                      label: Text(
                        "${data['points']} pts",
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.deepPurple,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        // Task ko Firestore se delete karne ka code
                        await FirebaseFirestore.instance
                            .collection('tasks')
                            .doc(snapshot.data!.docs[index].id)
                            .delete();
                      },
                    ),
                  ],
                ),
              ),
            ).animate().fade(duration: 500.ms).slideY(begin: 0.2);
          },
        );
      },
    ),
    // 2. REWARDS LIST
    StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rewards')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return const Center(child: Text("Reward is empty."));

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: const Icon(Icons.card_giftcard, color: Colors.green),
                title: Text(
                  data['title'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: Row(
                  mainAxisSize:
                      MainAxisSize.min, // 🚨 Yeh lazmi hai warna error aayega
                  children: [
                    Chip(
                      label: Text(
                        "${data['price']} pts",
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.deepPurple,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        // Task ko Firestore se delete karne ka code
                        await FirebaseFirestore.instance
                            .collection('rewards')
                            .doc(snapshot.data!.docs[index].id)
                            .delete();
                      },
                    ),
                  ],
                ),
              ),
            ).animate().fade(duration: 500.ms).slideY(begin: 0.2);
          },
        );
      },
    ),
    // 3. RULES LIST
    StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rules')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return const Center(child: Text("No rules established."));

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: const Icon(Icons.gavel, color: Colors.blueAccent),
                title: Text(
                  data['description'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                // 👇 YAHAN AAYEGA TRAILING (EDIT & DELETE) 👇
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // EDIT BUTTON
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blueAccent),
                      onPressed: () {
                        TextEditingController editCtrl = TextEditingController(
                          text: data['description'],
                        );
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: Colors.grey[900],
                            title: const Text(
                              "Edit Rule",
                              style: TextStyle(color: Colors.white),
                            ),
                            content: TextField(
                              controller: editCtrl,
                              style: const TextStyle(color: Colors.white),
                            ),
                            actions: [
                              TextButton(
                                child: const Text(
                                  "SAVE",
                                  style: TextStyle(color: Colors.pinkAccent),
                                ),
                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection('rules')
                                      .doc(snapshot.data!.docs[index].id)
                                      .update({'description': editCtrl.text});
                                  Navigator.pop(context);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    // DELETE BUTTON
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('rules')
                            .doc(snapshot.data!.docs[index].id)
                            .delete();
                      },
                    ),
                  ],
                ),
                // 👆 TRAILING KHATAM 👆
              ),
            ).animate().fade(duration: 500.ms).slideY(begin: 0.2);
          },
        );
      },
    ),
    // 4. 🔥 UPGRADED Penalties LIST (WITH VALIDATION & MODE CHECK) 🔥
    StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Penalties')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return const Center(child: Text("No active Penalties."));

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            int reqPoints = data['requiredPoints'] ?? 0;
            bool needsProof = data['requiresProof'] ?? false;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Colors.redAccent, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: const Icon(Icons.warning, color: Colors.red),
                title: Text(
                  data['reason'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "Cost: $reqPoints Demerits | Proof: ${needsProof ? '📸 Required' : '❌ Not Required'}",
                ),

                trailing: Row(
                  mainAxisSize: MainAxisSize.min, // 🚨 Yeh lazmi hai
                  children: [
                    // 1. AAPKA PURANA FIRE BUTTON (Pura code wahi hai)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[900],
                      ),
                      onPressed: () async {
                        CommandScreen.isAwaitingPunishmentProof =
                            needsProof; // 👈 Saza dene ke baad proof ka intezar karna hai
                        CommandScreen.isScreenCurrentlyLocked =
                            true; // 👈 Screen lock karna hai
                        CommandScreen.releaseCondition = needsProof
                            ? "Proof (Photo)"
                            : "Manual (Only I release)";
                        var docRef = FirebaseFirestore.instance
                            .collection('users')
                            .doc('sub_station');
                        var snap = await docRef.get();

                        if (!snap.exists) return;
                        int currentDemerits =
                            snap.data()?['punishmentPoints'] ?? 0;

                        // 🛑 LOGIC 1: INSUFFICIENT POINTS BLOCKER
                        if (currentDemerits < reqPoints) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "⚠️ Not enough Demerits! You need $reqPoints but he only has $currentDemerits.",
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return; // YAHIN RUK JAO
                        }

                        // ✔️ Agar points hain, toh minus karo
                        await docRef.update({
                          'punishmentPoints': currentDemerits - reqPoints,
                        });

                        // 🛑 LOGIC 2: MODE CHECK FOR OVERLAY
                        String deliveryType = (widget.hisMode == "Our Time 💑")
                            ? 'OVERLAY'
                            : 'NOTIFICATION';

                        widget.socket.emit('trigger_vibration', {
                          'type': 'OVERLAY_COMMAND',
                          'delivery': deliveryType,
                          'release_type': needsProof
                              ? 'Proof (Photo)'
                              : 'Manual (Only I release)',
                          'message':
                              '🚨 PUNISHMENT ACTIVE: ${data['reason']} 🚨',
                          'priority': 'HIGH',
                        });

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              deliveryType == 'OVERLAY'
                                  ? "Attention Demanded! 🔔"
                                  : "Punishment sent via Notification (Mode is not 'Our Time 💑') 📲",
                            ),
                            backgroundColor: deliveryType == 'OVERLAY'
                                ? Colors.black
                                : Colors.blueGrey,
                          ),
                        );
                      },
                      child: const Text(
                        "FIRE",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // 2. NAYA DELETE BUTTON
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.grey),
                      tooltip: "Delete Penalty",
                      onPressed: () async {
                        // Punishments collection se delete karna
                        await FirebaseFirestore.instance
                            .collection('Penalties')
                            .doc(snapshot.data!.docs[index].id)
                            .delete();
                      },
                    ),
                  ],
                ),
              ),
            ).animate().fade(duration: 500.ms).slideY(begin: 0.2);
          },
        );
      },
    ),

    // 5. 📥 THE NEW INBOX (PHASE 3: APPROVE/REJECT PROOFS) 📥
    StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pending_proofs')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return const Center(
            child: Text("Inbox is empty. No pending proofs. 🎉"),
          );

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var data = doc.data() as Map<String, dynamic>;
            int taskReward = data['taskPoints'] ?? 0;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Task: ${data['taskTitle']}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Yahan photo show hogi agar wo base64 mein save hui hai
                    // BossDashboard ke Inbox/Pending Proofs block mein:
                    if (data['mediaUrl'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Image.memory(
                          base64Decode(
                            data['mediaUrl'],
                          ), // 👈 Brackets theek kar diye hain
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text("⚠️ Error loading task image"),
                        ),
                      )
                    else // 👇 YEH NAYA ADD KIYA HAI (Approval Required Tasks Ke Liye) 👇
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.gavel, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Manual Verification Required. Did he behave and finish it properly?",
                                style: TextStyle(color: Colors.orangeAccent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // APPROVE BUTTON
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: Text(
                            "Approve (+${data['taskPoints']} Pts)",
                            style: const TextStyle(color: Colors.white),
                          ),
                          onPressed: () async {
                            var docRef = FirebaseFirestore.instance
                                .collection('users')
                                .doc('sub_station');
                            var taskRef = FirebaseFirestore.instance
                                .collection('tasks')
                                .doc(data['taskId']); // 👈 Task ka link

                            await FirebaseFirestore.instance.runTransaction((
                              transaction,
                            ) async {
                              var snap = await transaction.get(docRef);
                              var taskSnap = await transaction.get(taskRef);

                              int currentRewards =
                                  snap.data()?['rewardPoints'] ?? 0;
                              transaction.update(docRef, {
                                'rewardPoints': currentRewards + taskReward,
                              });
                              transaction.update(doc.reference, {
                                'status': 'approved',
                              });

                              // 🔥 Agar One-Time tha, toh usay hamesha ke liye inactive kardo
                              if (taskSnap.exists &&
                                  taskSnap.data()?['frequency'] == 'One-Time') {
                                transaction.update(taskRef, {
                                  'isActive': false,
                                });
                              }
                            });
                          },
                        ),

                        // REJECT BUTTON
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          icon: const Icon(Icons.close, color: Colors.white),
                          label: Text(
                            "Reject (+${data['taskPenalty'] ?? 5} Oopsie Pts)",
                            style: const TextStyle(color: Colors.white),
                          ),
                          onPressed: () async {
                            int penaltyToApply = data['taskPenalty'] ?? 5;
                            var docRef = FirebaseFirestore.instance
                                .collection('users')
                                .doc('sub_station');
                            var taskRef = FirebaseFirestore.instance
                                .collection('tasks')
                                .doc(data['taskId']);

                            await FirebaseFirestore.instance.runTransaction((
                              transaction,
                            ) async {
                              var snap = await transaction.get(docRef);
                              int currentDemerits =
                                  snap.data()?['punishmentPoints'] ?? 0;

                              transaction.update(docRef, {
                                'punishmentPoints':
                                    currentDemerits + penaltyToApply,
                              });
                              transaction.update(doc.reference, {
                                'status': 'rejected',
                              });

                              // 🔥 Task se "lastCompleted" hata do taake button wapis active ho jaye!
                              transaction.update(taskRef, {
                                'lastCompleted': FieldValue.delete(),
                              });
                            });

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Proof Rejected! Penalty given."),
                                backgroundColor: Colors.red,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ).animate().fade(duration: 500.ms).slideY(begin: 0.2);
          },
        );
      },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Her Locket 👑",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        // NAYA HISSA: Live Points Display
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50.0),
          child: StreamBuilder<DocumentSnapshot>(
            stream: _db.getSubStationProfile(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                _db.initSubStationProfile(); // Agar profile nahi hai toh bana do
                return const SizedBox(
                  height: 50,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );
              }

              var data = snapshot.data!.data() as Map<String, dynamic>;
              return Container(
                color: Colors.black12,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.stars, color: Colors.amber, size: 20),
                        const SizedBox(width: 5),
                        Text(
                          "Rewards: ${data['rewardPoints']}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.warning,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          "Demerits: ${data['punishmentPoints']}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit_note,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: "Manage Points",
                      onPressed: () => _showPointManagerDialog(
                        data['rewardPoints'] ?? 0,
                        data['punishmentPoints'] ?? 0,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.deepPurple),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "Command Center",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_back, color: Colors.deepPurple),
              title: const Text(
                'Back to Main Chat',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(context);
              }, // Yahan hum isay pop kar ke wapis Chat screen par bhej rahe hain
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.check_box),
              title: const Text('Tasks'),
              selected: _selectedIndex == 0,
              onTap: () => _onItemTapped(0),
            ),
            ListTile(
              leading: const Icon(Icons.card_giftcard),
              title: const Text('Rewards'),
              selected: _selectedIndex == 1,
              onTap: () => _onItemTapped(1),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('Rules'),
              selected: _selectedIndex == 2,
              onTap: () => _onItemTapped(2),
            ),
            ListTile(
              leading: const Icon(Icons.warning),
              title: const Text('Penalties'),
              selected: _selectedIndex == 3,
              onTap: () => _onItemTapped(3),
            ),
            ListTile(
              leading: const Icon(Icons.inbox),
              title: const Text('Inbox (Proofs)'),
              selected: _selectedIndex == 4,
              onTap: () => _onItemTapped(4),
            ),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
      floatingActionButton: _selectedIndex != 4
          ? FloatingActionButton.extended(
              onPressed: _onAddPressed,
              icon: const Icon(Icons.add),
              label: Text("Add ${_titles[_selectedIndex].split(' ')[0]}"),
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            )
          : null, // Inbox par koi button nahi
    );
  }
}
