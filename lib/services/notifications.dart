import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/app_state.dart';
import '../logic/stock_logic.dart';
import '../models/models.dart';

/// Notifications de péremption (Android) : une notification à 9 h le jour où
/// des produits entrent dans le délai d'alerte (3 jours avant par défaut).
/// Elles sont reprogrammées à chaque changement du stock, et après un
/// redémarrage du téléphone (géré par le module).
class ExpiryNotifications {
  ExpiryNotifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Timer? _debounce;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'peremption',
      'Péremption',
      channelDescription: 'Produits qui vont bientôt périmer',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// À appeler au démarrage : prépare le module et demande l'autorisation.
  static Future<void> start(AppState state) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Paris'));
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
      await reschedule(state);
      state.addListener(() {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 2), () => reschedule(state));
      });
    } catch (e) {
      debugPrint('Notifications indisponibles : $e');
    }
  }

  static Future<void> reschedule(AppState state) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    final plan = planNotifications(state.batches.values, state.products, state.settings.alertDays, DateTime.now());
    for (final n in plan) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime(tz.local, n.when.year, n.when.month, n.when.day, n.when.hour),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: n.title,
        body: n.body,
      );
    }
  }
}

class PlannedNotification {
  final int id;
  final DateTime when;
  final String title;
  final String body;
  PlannedNotification(this.id, this.when, this.title, this.body);
}

/// Calcule les notifications à programmer (logique pure, testée).
List<PlannedNotification> planNotifications(
    Iterable<Batch> batches, Map<String, Product> products, int alertDays, DateTime now,
    {int hour = 9, int max = 60}) {
  final byDay = <DateTime, List<Batch>>{};
  final today = dateOnly(now);
  for (final b in batches) {
    if (b.frozen) continue; // congelé : la date ne compte plus
    final day = dateOnly(b.expirationDate).subtract(Duration(days: alertDays));
    final when = DateTime(day.year, day.month, day.day, hour);
    if (!when.isAfter(now)) continue; // déjà dans la zone d'alerte : visible dans l'appli
    byDay.putIfAbsent(DateTime(day.year, day.month, day.day), () => []).add(b);
  }
  final days = byDay.keys.toList()..sort();
  final result = <PlannedNotification>[];
  for (final day in days.take(max)) {
    final lots = byDay[day]!;
    final names = <String>[];
    for (final b in sortFefo(lots)) {
      final p = products[b.productId];
      if (p != null && !names.contains(p.name)) names.add(p.name);
    }
    if (names.isEmpty) continue;
    final title = names.length == 1
        ? '« ${names.first} » périme bientôt'
        : '${names.length} produits périment bientôt';
    final shown = names.take(4).join(', ') + (names.length > 4 ? '…' : '');
    final body = alertDays == 0 ? "À consommer aujourd'hui : $shown" : 'Dans $alertDays jours : $shown';
    final id = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(2020)).inDays;
    result.add(PlannedNotification(id, DateTime(day.year, day.month, day.day, hour), title, body));
  }
  return result..removeWhere((n) => n.when.isBefore(today));
}
