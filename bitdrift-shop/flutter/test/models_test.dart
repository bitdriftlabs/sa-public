import 'package:flutter_test/flutter_test.dart';
import 'package:bitdrift_shop_flutter/models/models.dart';

void main() {
  test('Product.fromJson maps the backend fields', () {
    final p = Product.fromJson({
      'id': 'p1',
      'name': 'Widget',
      'price': 12.5,
      'image_url': '/images/p1.png',
      'category': 'Home',
      'brand': 'Acme',
    });
    expect(p.id, 'p1');
    expect(p.name, 'Widget');
    expect(p.price, 12.5);
    expect(p.category, 'Home');
    expect(p.brand, 'Acme');
  });

  test('Product.list only accepts JSON lists', () {
    expect(Product.list([{'id': 'a', 'name': 'A', 'price': 1}]).single.id, 'a');
    expect(Product.list({'unexpected': true}), isEmpty);
    expect(Product.list(null), isEmpty);
  });

  test('Category.fromJson reads product_count', () {
    expect(
      Category.fromJson({'name': 'Books', 'product_count': 7}).productCount,
      7,
    );
  });
}
