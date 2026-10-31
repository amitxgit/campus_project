// lib/core/services/notification_service.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  Future<void> init({Function(String? payload)? onNotificationTap}) async {
    if (_initialized) return;

    const androidInit =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      macOS: iosInit,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (onNotificationTap != null) {
          onNotificationTap(response.payload);
        }
      },
    );

    _initialized = true;
    debugPrint('NotificationService: Initialized');
  }

  // ---------------------------------------------------------------------------
  // PERMISSIONS
  // ---------------------------------------------------------------------------

  Future<bool> requestPermissions() async {
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _local.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    bool? granted = false;
    if (android != null) {
      granted = await android.requestNotificationsPermission();
    } else if (ios != null) {
      granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    return granted ?? false;
  }

  // ---------------------------------------------------------------------------
  // SHOW NOTIFICATION
  // ---------------------------------------------------------------------------

  Future<void> showLocal(
      String title,
      String body, {
        String? payload,
      }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'campustrack_local',
      'Batchwise notifications',
      channelDescription: 'Alerts for attendance and timetable changes',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Unique notification ID
    final millisRemainder =
    DateTime.now().millisecondsSinceEpoch.remainder(100000);
    final randomFallback = Random().nextInt(1000);
    final notificationId = millisRemainder + randomFallback;

    try {
      await _local.show(
        notificationId,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      // Safe fallback (won't crash app)
      debugPrint('🔔 LOCAL NOTIFICATION: $title - $body');
    }
  }
}
// FIXED: Removed duplicate 'notifServiceProvider' definition.
// It is defined in lib/main.dart.