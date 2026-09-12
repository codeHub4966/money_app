import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _notificationsPlugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
  }

  // Returns a map of which permissions are granted.
  Future<ReminderPermissionStatus> checkPermissions() async {
    final notif = await Permission.notification.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    final exactAlarm =
        await _androidPlugin?.canScheduleExactNotifications() ?? true;

    return ReminderPermissionStatus(
      notification: notif.isGranted,
      exactAlarm: exactAlarm,
      batteryOptimizationExempt: battery.isGranted,
    );
  }

  // Request notification permission; returns true if granted.
  Future<bool> requestNotificationPermission() async {
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  // Open system exact alarm settings page.
  Future<void> openExactAlarmSettings() async {
    await _androidPlugin?.requestExactAlarmsPermission();
  }

  // Request battery optimization exemption; returns true if granted.
  Future<bool> requestBatteryOptimizationExemption() async {
    final result = await Permission.ignoreBatteryOptimizations.request();
    return result.isGranted;
  }

  Future<void> scheduleDailyReminder(int hour, int minute) async {
    await cancelReminder();

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminder',
      channelDescription: 'Reminds you to record your daily expenses',
      importance: Importance.high,
      priority: Priority.high,
    );

    final canExact =
        await _androidPlugin?.canScheduleExactNotifications() ?? false;
    final scheduleMode = canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _notificationsPlugin.zonedSchedule(
      0,
      'Time to Record Expenses',
      "Don't forget to log your spending today!",
      scheduledDate,
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelReminder() async {
    await _notificationsPlugin.cancel(0);
  }

  // Schedules a one-off insight alert for [scheduledDate] (a local wall-clock
  // time; converted to the device's zone internally) instead of showing it
  // immediately. Used to silently delay the unusual-spending alert by a few
  // minutes and to deliver the next-day financial summary at a fixed time.
  // Re-scheduling with the same [id] replaces whatever was pending under it.
  Future<void> scheduleInsightNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    bool expandable = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'smart_insights',
      'Smart Insights',
      channelDescription:
          'Alerts for unusual spending days and new spending insights',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: expandable ? BigTextStyleInformation(body) : null,
    );

    final canExact =
        await _androidPlugin?.canScheduleExactNotifications() ?? false;
    final scheduleMode = canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      NotificationDetails(
          android: androidDetails, iOS: const DarwinNotificationDetails()),
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // Cancels a pending notification scheduled via [scheduleInsightNotification]
  // that hasn't fired yet.
  Future<void> cancelInsightNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}

class ReminderPermissionStatus {
  final bool notification;
  final bool exactAlarm;
  final bool batteryOptimizationExempt;

  const ReminderPermissionStatus({
    required this.notification,
    required this.exactAlarm,
    required this.batteryOptimizationExempt,
  });

  bool get allGranted =>
      notification && exactAlarm && batteryOptimizationExempt;
}
