import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DayMateApp());
}

const Color navy = Color(0xFF172554);
const Color purple = Color(0xFF6558D3);
const Color pageBackground = Color(0xFFF5F6FC);

// ------------------------------------------------------------
// APP
// ------------------------------------------------------------

class DayMateApp extends StatelessWidget {
  const DayMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DayMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: pageBackground,
        colorScheme: ColorScheme.fromSeed(seedColor: purple),
        appBarTheme: const AppBarTheme(
          backgroundColor: pageBackground,
          foregroundColor: navy,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const DayMateHome(),
    );
  }
}

// ------------------------------------------------------------
// REMINDER MODEL
// ------------------------------------------------------------

class Routine {
  final int id;
  String title;
  String category;
  int hour;
  int minute;
  bool completed;

  Routine({
    required this.id,
    required this.title,
    required this.category,
    required this.hour,
    required this.minute,
    this.completed = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'hour': hour,
    'minute': minute,
    'completed': completed,
  };

  factory Routine.fromJson(Map<String, dynamic> json) {
    return Routine(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      category: json['category'] as String,
      hour: (json['hour'] as num).toInt(),
      minute: (json['minute'] as num).toInt(),
      completed: json['completed'] as bool? ?? false,
    );
  }

  String get timeKey =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';

  String get displayTime {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m ${hour >= 12 ? 'PM' : 'AM'}';
  }
}

// ------------------------------------------------------------
// MAIN SCREEN AND APP FEATURES
// ------------------------------------------------------------

class DayMateHome extends StatefulWidget {
  const DayMateHome({super.key});

  @override
  State<DayMateHome> createState() => _DayMateHomeState();
}

class _DayMateHomeState extends State<DayMateHome> {
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  final TextEditingController profileController = TextEditingController(
    text: 'DayMate User',
  );

  List<Routine> routines = [];

  final Map<String, bool> habits = {
    'Drink enough water': false,
    'Exercise': false,
    'Study or read': false,
    'Take regular breaks': false,
  };

  int selectedTab = 0;
  bool loading = true;

  bool apiLoading = false;

  String profileName = 'DayMate User';
  String advice = 'Stay consistent with your daily routine.';
  String? apiError;

  TimeOfDay bedtime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay wakeUpTime = const TimeOfDay(hour: 6, minute: 0);

  final List<String> pageTitles = [
    'DayMate',
    'My Reminders',
    'Sleep Tracker',
    'Daily Habits',
    'My Profile',
  ];

  @override
  void initState() {
    super.initState();
    initializeApp();
  }

  @override
  void dispose() {
    profileController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // INITIALIZATION AND LOCAL STORAGE
  // ----------------------------------------------------------

  Future<void> initializeApp() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    } catch (_) {
      // Time zone setup is only needed for scheduled notifications.
    }

    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await notifications.initialize(
        settings: const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );

      final android = notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final ios = notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      await android?.requestNotificationsPermission();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      // Notifications are not supported on this platform (e.g. Windows).
      // The app still works; only scheduled reminders are unavailable.
      debugPrint('Notification init skipped: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      profileName = prefs.getString('daymate_profile') ?? 'DayMate User';
      profileController.text = profileName;

      bedtime = TimeOfDay(
        hour: prefs.getInt('daymate_bed_hour') ?? 22,
        minute: prefs.getInt('daymate_bed_minute') ?? 0,
      );

      wakeUpTime = TimeOfDay(
        hour: prefs.getInt('daymate_wake_hour') ?? 6,
        minute: prefs.getInt('daymate_wake_minute') ?? 0,
      );

      final savedRoutines = prefs.getString('daymate_routines');

      if (savedRoutines != null) {
        try {
          routines = (jsonDecode(savedRoutines) as List)
              .map((item) => Routine.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        } catch (_) {
          routines = defaultRoutines();
        }
      } else {
        routines = defaultRoutines();
      }

      final savedHabits = prefs.getString('daymate_habits');

      if (savedHabits != null) {
        try {
          final decoded = Map<String, dynamic>.from(jsonDecode(savedHabits));

          for (final key in habits.keys.toList()) {
            habits[key] = decoded[key] as bool? ?? false;
          }
        } catch (_) {
          // Use the default unchecked habits.
        }
      }

      await saveRoutines();
    } catch (e) {
      debugPrint('Failed to load saved data: $e');
    }

    if (mounted) {
      setState(() => loading = false);
    }

    if (mounted) {
      showMessage('Welcome back, $profileName!');
    }

    // Retrieve online motivational advice.
    await fetchAdvice();
  }

  List<Routine> defaultRoutines() {
    return [
      Routine(
        id: 1001,
        title: 'Breakfast time',
        category: 'Breakfast',
        hour: 7,
        minute: 0,
      ),
      Routine(
        id: 1002,
        title: 'Lunch break',
        category: 'Lunch',
        hour: 12,
        minute: 0,
      ),
      Routine(
        id: 1003,
        title: 'Dinner time',
        category: 'Dinner',
        hour: 18,
        minute: 0,
      ),
      Routine(
        id: 1004,
        title: 'Time to sleep',
        category: 'Sleep',
        hour: 22,
        minute: 0,
      ),
      Routine(
        id: 1005,
        title: 'Wake-up time',
        category: 'Wake-up',
        hour: 6,
        minute: 0,
      ),
    ];
  }

  Future<void> saveRoutines() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'daymate_routines',
      jsonEncode(routines.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> saveHabits() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('daymate_habits', jsonEncode(habits));
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          backgroundColor: navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
  }

  void navigateToTab(int index) {
    setState(() => selectedTab = index);
    showMessage('Switched to ${pageTitles[index]}.');
  }

  // ----------------------------------------------------------
  // API INTEGRATION
  // ----------------------------------------------------------

  Future<void> fetchAdvice() async {
    if (!mounted) return;

    setState(() {
      apiLoading = true;
      apiError = null;
    });

    try {
      final response = await http
          .get(
            Uri.parse('https://api.adviceslip.com/advice'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final message = data['slip']?['advice'];

      if (message is! String || message.isEmpty) {
        throw Exception('The API returned invalid data.');
      }

      if (mounted) {
        setState(() => advice = message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          apiError =
              'Unable to load advice. Check your internet connection and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => apiLoading = false);
      }
    }
  }

  // ----------------------------------------------------------
  // NOTIFICATION BUTTON AND SCHEDULED REMINDERS
  // ----------------------------------------------------------

  Future<void> sendTestNotification() async {
    try {
      final android = notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final ios = notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      final grantedAndroid = await android?.requestNotificationsPermission();
      final grantedIOS = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (grantedAndroid == false && grantedIOS == false) {
        showMessage(
          'Please allow DayMate notifications in your device Settings.',
        );
        return;
      }

      await notifications.show(
        id: 999999,
        title: 'DayMate Notification',
        body: 'Your daily reminder assistant is ready!',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daymate_button_notifications',
            'DayMate App Notifications',
            channelDescription:
                'Notifications triggered by the DayMate notification button',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );

      showMessage('Notification sent. Check your phone notification bar.');
    } catch (e) {
      showMessage('Could not send notification: $e');
    }
  }

  Future<void> scheduleRoutine(Routine routine) async {
    if (!notificationsSupported) return;

    try {
      final now = tz.TZDateTime.now(tz.local);

      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        routine.hour,
        routine.minute,
      );

      if (!scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      await notifications.zonedSchedule(
        id: routine.id,
        title: 'DayMate Reminder',
        body: routine.title,
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daymate_reminders',
            'DayMate Reminders',
            channelDescription:
                'Daily reminders for meals, sleep, and activities',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Failed to schedule reminder: $e');
    }
  }

  /// True on platforms where local notifications actually work
  /// (Android and iOS). On Windows/web the plugin has no implementation,
  /// so any call would throw MissingPluginException and crash the flow.
  bool get notificationsSupported {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // ----------------------------------------------------------
  // ADD AND EDIT REMINDERS
  // ----------------------------------------------------------

  Future<void> addOrEditRoutine({Routine? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');

    String category = existing?.category ?? 'Custom';

    TimeOfDay selectedTime = existing == null
        ? const TimeOfDay(hour: 8, minute: 0)
        : TimeOfDay(hour: existing.hour, minute: existing.minute);

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Routine>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Reminder' : 'Edit Reminder'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Reminder name',
                          prefixIcon: Icon(Icons.edit_calendar),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a reminder name.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items:
                            [
                              'Breakfast',
                              'Lunch',
                              'Dinner',
                              'Sleep',
                              'Wake-up',
                              'Study',
                              'Exercise',
                              'Appointment',
                              'Custom',
                            ].map((item) {
                              return DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            updateDialog(() => category = value);
                            showMessage('Category changed to $value.');
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.access_time),
                        label: Text(selectedTime.format(dialogContext)),
                        onPressed: () async {
                          final localizations = MaterialLocalizations.of(
                            dialogContext,
                          );
                          final picked = await showTimePicker(
                            context: dialogContext,
                            initialTime: selectedTime,
                          );

                          if (!mounted) return;
                          if (!dialogContext.mounted) return;

                          if (picked != null) {
                            updateDialog(() => selectedTime = picked);
                            if (mounted) {
                              showMessage(
                                'Reminder time set to '
                                '${localizations.formatTimeOfDay(picked)}.',
                              );
                            }
                          } else {
                            if (mounted) {
                              showMessage('Time selection cancelled.');
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;

                    Navigator.pop(
                      dialogContext,
                      Routine(
                        id:
                            existing?.id ??
                            DateTime.now().microsecondsSinceEpoch % 2000000000,
                        title: titleController.text.trim(),
                        category: category,
                        hour: selectedTime.hour,
                        minute: selectedTime.minute,
                        completed: existing?.completed ?? false,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    // NOTE: titleController is intentionally not disposed right here.
    // The dialog is still animating out after showDialog() resolves, and
    // disposing its controller during that animation causes
    // "A TextEditingController was used after being disposed".

    if (!mounted) return;
    if (result == null) {
      showMessage(
        existing == null
            ? 'Adding reminder cancelled.'
            : 'Editing reminder cancelled.',
      );
      return;
    }

    if (existing != null) {
      if (notificationsSupported) {
        try {
          await notifications.cancel(id: existing.id);
        } catch (_) {}
      }

      final index = routines.indexWhere((r) => r.id == existing.id);

      if (index != -1) {
        routines[index] = result;
      }
    } else {
      routines.add(result);
    }

    await saveRoutines();
    await scheduleRoutine(result);

    if (mounted) {
      setState(() {});
      showMessage(
        existing == null
            ? 'Reminder added and scheduled.'
            : 'Reminder updated successfully.',
      );
    }
  }

  // ----------------------------------------------------------
  // DELETE REMINDERS
  // ----------------------------------------------------------

  Future<void> deleteRoutine(Routine routine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Reminder?'),
          content: Text('Are you sure you want to delete "${routine.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      showMessage('Reminder deletion cancelled.');
      return;
    }

    if (notificationsSupported) {
      try {
        await notifications.cancel(id: routine.id);
      } catch (_) {}
    }

    routines.removeWhere((r) => r.id == routine.id);

    await saveRoutines();

    if (mounted) {
      setState(() {});
      showMessage('Reminder deleted successfully.');
    }
  }

  Future<void> toggleCompleted(Routine routine, bool? value) async {
    routine.completed = value ?? false;

    await saveRoutines();

    if (mounted) {
      setState(() {});
      showMessage(
        routine.completed
            ? '${routine.title} marked as completed.'
            : '${routine.title} marked as not completed.',
      );
    }
  }

  // ----------------------------------------------------------
  // PROFILE
  // ----------------------------------------------------------

  Future<void> saveProfile() async {
    final name = profileController.text.trim();

    if (name.isEmpty) {
      showMessage('Please enter your display name.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('daymate_profile', name);

    if (mounted) {
      setState(() => profileName = name);
      showMessage('Profile updated successfully.');
    }
  }

  // ----------------------------------------------------------
  // SLEEP TRACKER
  // ----------------------------------------------------------

  Future<void> saveSleepSetting({
    required bool isBedtime,
    required TimeOfDay selectedTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (isBedtime) {
      bedtime = selectedTime;
      await prefs.setInt('daymate_bed_hour', selectedTime.hour);
      await prefs.setInt('daymate_bed_minute', selectedTime.minute);
    } else {
      wakeUpTime = selectedTime;
      await prefs.setInt('daymate_wake_hour', selectedTime.hour);
      await prefs.setInt('daymate_wake_minute', selectedTime.minute);
    }

    final category = isBedtime ? 'Sleep' : 'Wake-up';
    final title = isBedtime ? 'Time to sleep' : 'Time to wake up';

    final matches = routines.where((r) => r.category == category).toList();
    final existing = matches.isEmpty ? null : matches.first;

    final routine = Routine(
      id: existing?.id ?? (isBedtime ? 1004 : 1005),
      title: title,
      category: category,
      hour: selectedTime.hour,
      minute: selectedTime.minute,
      completed: existing?.completed ?? false,
    );

    if (existing != null) {
      if (notificationsSupported) {
        try {
          await notifications.cancel(id: existing.id);
        } catch (_) {}
      }
      routines.removeWhere((r) => r.category == category);
    }

    routines.add(routine);

    await saveRoutines();
    await scheduleRoutine(routine);

    if (mounted) {
      setState(() {});
      showMessage(
        isBedtime
            ? 'Bedtime and reminder updated.'
            : 'Wake-up time and reminder updated.',
      );
    }
  }

  Future<void> pickSleepTime({required bool isBedtime}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isBedtime ? bedtime : wakeUpTime,
    );

    if (picked == null) {
      showMessage('Time selection cancelled.');
      return;
    }

    await saveSleepSetting(isBedtime: isBedtime, selectedTime: picked);
  }

  // ----------------------------------------------------------
  // DAILY HABITS
  // ----------------------------------------------------------

  Future<void> toggleHabit(String habit, bool? value) async {
    setState(() => habits[habit] = value ?? false);
    await saveHabits();
    showMessage(
      habits[habit] == true
          ? '$habit marked as complete.'
          : '$habit marked as incomplete.',
    );
  }

  Future<void> resetHabits() async {
    setState(() {
      habits.updateAll((key, value) => false);
    });

    await saveHabits();

    if (mounted) showMessage('Daily habits have been reset.');
  }

  // ----------------------------------------------------------
  // SHARED UI HELPERS
  // ----------------------------------------------------------

  IconData categoryIcon(String category) {
    switch (category) {
      case 'Breakfast':
        return Icons.free_breakfast_rounded;
      case 'Lunch':
        return Icons.lunch_dining_rounded;
      case 'Dinner':
        return Icons.dinner_dining_rounded;
      case 'Sleep':
        return Icons.bedtime_rounded;
      case 'Wake-up':
        return Icons.wb_sunny_rounded;
      case 'Study':
        return Icons.menu_book_rounded;
      case 'Exercise':
        return Icons.fitness_center_rounded;
      case 'Appointment':
        return Icons.event_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  String get todayLabel {
    final now = DateTime.now();

    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${days[now.weekday - 1]}, '
        '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Widget summaryCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: purple, size: 26),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // REMINDER CARD
  // ----------------------------------------------------------

  Widget routineCard(Routine routine) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(categoryIcon(routine.category), color: purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      decoration: routine.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${routine.category} • ${routine.displayTime}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    routine.completed ? 'Completed' : 'Daily reminder',
                    style: TextStyle(
                      color: routine.completed ? Colors.green : purple,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Reminder options',
              onSelected: (value) {
                if (value == 'edit') {
                  addOrEditRoutine(existing: routine);
                } else if (value == 'delete') {
                  deleteRoutine(routine);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            Checkbox(
              value: routine.completed,
              onChanged: (value) => toggleCompleted(routine, value),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // PAGE 1: HOME
  // ----------------------------------------------------------

  Widget dashboard() {
    final sorted = [...routines]
      ..sort((a, b) => a.timeKey.compareTo(b.timeKey));

    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final upcomingItems = sorted.where((r) {
      final reminderMinutes = r.hour * 60 + r.minute;

      return !r.completed && reminderMinutes >= currentMinutes;
    }).toList();

    final upcoming = upcomingItems.isEmpty ? null : upcomingItems.first;

    final completedCount = routines.where((r) => r.completed).length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(todayLabel, style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        const Text(
          'Make today count!',
          style: TextStyle(
            color: navy,
            fontSize: 27,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [navy, purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.notifications_active,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(height: 12),
              const Text(
                'YOUR NEXT REMINDER',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 5),
              Text(
                upcoming?.title ?? 'You are all caught up!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                upcoming?.displayTime ?? 'Enjoy your free time.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => navigateToTab(1),
                icon: const Icon(Icons.calendar_month),
                label: const Text('View my schedule'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: summaryCard(
                Icons.calendar_today,
                'Reminders',
                '${routines.length}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: summaryCard(
                Icons.check_circle_outline,
                'Completed',
                '$completedCount',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's schedule",
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => navigateToTab(1),
              child: const Text('See all'),
            ),
          ],
        ),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No reminders yet. Tap + to add one.'),
          )
        else
          ...sorted.take(4).map(routineCard),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFFEDEAFF),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: purple),
                    SizedBox(width: 8),
                    Text(
                      'Daily motivation',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (apiLoading)
                  const Center(child: CircularProgressIndicator())
                else if (apiError != null)
                  Text(apiError!)
                else
                  Text('"$advice"', style: const TextStyle(height: 1.5)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: apiLoading
                        ? null
                        : () async {
                            await fetchAdvice();
                            showMessage(
                              apiError == null
                                  ? 'Daily advice refreshed.'
                                  : 'Unable to refresh daily advice.',
                            );
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh advice'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Created by Iverson',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // PAGE 2: LIST VIEW
  // ----------------------------------------------------------

  Widget schedulePage() {
    final sorted = [...routines]
      ..sort((a, b) => a.timeKey.compareTo(b.timeKey));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'My Reminders',
                  style: TextStyle(
                    color: navy,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => addOrEditRoutine(),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        Expanded(
          child: sorted.isEmpty
              ? const Center(
                  child: Text('No reminders yet. Tap Add to get started.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    return routineCard(sorted[index]);
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Center(
            child: Text(
              'Created by Iverson',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // PAGE 3: SLEEP TRACKER
  // ----------------------------------------------------------

  Widget sleepPage() {
    final bedMinutes = bedtime.hour * 60 + bedtime.minute;
    final wakeMinutes = wakeUpTime.hour * 60 + wakeUpTime.minute;

    var sleepMinutes = wakeMinutes - bedMinutes;

    if (sleepMinutes <= 0) {
      sleepMinutes += 24 * 60;
    }

    final hours = sleepMinutes ~/ 60;
    final minutes = sleepMinutes % 60;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Sleep Tracker',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: navy,
          ),
        ),
        const SizedBox(height: 8),
        const Text('Plan your bedtime and wake-up routine.'),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: navy,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              const Icon(Icons.nightlight_round, color: Colors.white, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Planned sleep duration',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                '${hours}h ${minutes}m',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.bedtime, color: purple),
            title: const Text('Bedtime'),
            subtitle: Text(bedtime.format(context)),
            trailing: const Icon(Icons.edit),
            onTap: () => pickSleepTime(isBedtime: true),
          ),
        ),
        Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.wb_sunny, color: Colors.orange),
            title: const Text('Wake-up time'),
            subtitle: Text(wakeUpTime.format(context)),
            trailing: const Icon(Icons.edit),
            onTap: () => pickSleepTime(isBedtime: false),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Both settings create daily scheduled notifications. '
          'Notification delivery depends on your device settings.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Created by Iverson',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // PAGE 4: DAILY HABITS
  // ----------------------------------------------------------

  Widget habitsPage() {
    final completed = habits.values.where((value) => value).length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Daily Habits',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: navy,
          ),
        ),
        const SizedBox(height: 8),
        const Text('Small steps can make your day better.'),
        const SizedBox(height: 20),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your daily progress',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: habits.isEmpty ? 0 : completed / habits.length,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: purple,
                ),
                const SizedBox(height: 8),
                Text('$completed of ${habits.length} habits completed'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...habits.keys.map((habit) {
          IconData icon;

          switch (habit) {
            case 'Drink enough water':
              icon = Icons.water_drop;
              break;
            case 'Exercise':
              icon = Icons.fitness_center;
              break;
            case 'Study or read':
              icon = Icons.menu_book;
              break;
            default:
              icon = Icons.coffee;
          }

          return Card(
            color: Colors.white,
            child: CheckboxListTile(
              value: habits[habit] ?? false,
              title: Text(habit),
              secondary: Icon(icon, color: purple),
              onChanged: (value) => toggleHabit(habit, value),
            ),
          );
        }),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: resetHabits,
          icon: const Icon(Icons.refresh),
          label: const Text('Reset daily habits'),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Created by Iverson',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // PAGE 5: PROFILE
  // ----------------------------------------------------------

  Widget profilePage() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        const CircleAvatar(
          radius: 48,
          backgroundColor: Color(0xFFEDEAFF),
          child: Icon(Icons.person, size: 55, color: purple),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            profileName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Center(child: Text('Your daily routine profile')),
        const SizedBox(height: 28),
        const Text(
          'Personal Information',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: profileController,
          decoration: const InputDecoration(
            labelText: 'Display name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: saveProfile,
          icon: const Icon(Icons.save),
          label: const Text('Save Profile'),
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.notifications_active, color: purple),
            title: const Text('My reminders'),
            subtitle: Text('${routines.length} saved reminders'),
            onTap: () => navigateToTab(1),
          ),
        ),
        Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.check_circle_outline, color: purple),
            title: const Text('Completed reminders'),
            subtitle: Text(
              '${routines.where((r) => r.completed).length} completed',
            ),
          ),
        ),
        Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.bedtime, color: purple),
            title: const Text('Bedtime'),
            subtitle: Text(bedtime.format(context)),
            onTap: () => navigateToTab(2),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'DayMate - Your daily routine companion',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Version 1.0.0',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Created by Iverson',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // MAIN NAVIGATION AND APP BAR
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      dashboard(),
      schedulePage(),
      sleepPage(),
      habitsPage(),
      profilePage(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 480 ? 480.0 : constraints.maxWidth;

        return ColoredBox(
          color: pageBackground,
          child: Center(
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Scaffold(
                appBar: AppBar(
                  title: Row(
                    children: [
                      const Icon(Icons.wb_sunny_rounded, color: purple),
                      const SizedBox(width: 8),
                      Text(
                        pageTitles[selectedTab],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Send notification',
                      onPressed: sendTestNotification,
                      icon: const Icon(
                        Icons.notifications_active,
                        color: purple,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: loading
                    ? const Center(child: CircularProgressIndicator())
                    : IndexedStack(index: selectedTab, children: pages),
                floatingActionButton: selectedTab == 0 || selectedTab == 1
                    ? FloatingActionButton.extended(
                        onPressed: () => addOrEditRoutine(),
                        backgroundColor: purple,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_alarm),
                        label: const Text('Add Reminder'),
                      )
                    : null,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: selectedTab,
                  onDestinationSelected: navigateToTab,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.list_alt_outlined),
                      selectedIcon: Icon(Icons.list_alt),
                      label: 'List View',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.bedtime_outlined),
                      selectedIcon: Icon(Icons.bedtime),
                      label: 'Sleep',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.checklist_outlined),
                      selectedIcon: Icon(Icons.checklist),
                      label: 'Habits',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
