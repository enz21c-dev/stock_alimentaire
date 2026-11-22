import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alimentaire/models/models.dart';
import 'package:stock_alimentaire/services/local_products.dart';
import 'package:stock_alimentaire/services/notifications.dart';

void main() {
  group('Notifications de péremption', () {
    final now = DateTime(2026, 11, 22, 18, 0);
    final products = {
      'y': Product(id: 'y', name: 'Yaourt'),
      'l': Product(id: 'l', name: 'Lait'),
      'n': Product(id: 'n', name: 'Nutella'),
    };
    final batches = [
      Batch(productId: 'y', quantity: 2, expirationDate: DateTime(2026, 11, 30)), // alerte le 27
      Batch(productId: 'l', quantity: 1, expirationDate: DateTime(2026, 11, 30)), // même jour
      Batch(productId: 'y', quantity: 2, expirationDate: DateTime(2026, 12, 10)), // alerte le 7/12
      Batch(productId: 'n', quantity: 1, expirationDate: DateTime(2026, 11, 24)), // alerte passée
    ];

    test('une notification par jour, à 9 h, 3 jours avant', () {
      final plan = planNotifications(batches, products, 3, now);
      expect(plan.map((n) => n.when), [DateTime(2026, 11, 27, 9), DateTime(2026, 12, 7, 9)]);
      expect(plan.first.title, '2 produits périment bientôt');
      expect(plan.first.body, 'Dans 3 jours : Yaourt, Lait');
      expect(plan.last.title, '« Yaourt » périme bientôt');
    });

    test('délai réglable et identifiants uniques', () {
      final plan = planNotifications(batches, products, 0, now);
      expect(plan.length, 3);
      expect(plan.map((n) => n.id).toSet().length, 3);
      expect(plan.first.body, startsWith("À consommer aujourd'hui"));
    });
  });

  group('Base de produits embarquée', () {
    test('lecture d\'une ligne', () {
      final p = LocalProducts.parseLine('3017620422003', 'Nutella\tFerrero\t2\t400 g\tfront_en.879.200.jpg');
      expect(p.name, 'Nutella');
      expect(p.brand, 'Ferrero');
      expect(p.category, 'Épicerie');
      expect(p.quantity, 400);
      expect(p.unit, 'g');
      expect(p.imageUrl, 'https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.879.200.jpg');
      expect(LocalProducts.imageUrl('00000051', 'f.jpg'),
          'https://images.openfoodfacts.org/images/products/00000051/f.jpg');
      expect(LocalProducts.parseLine('1', 'Eau\t\t4\t\t').brand, isNull);
    });
  });
}
