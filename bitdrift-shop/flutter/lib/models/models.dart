/// Small typed views over the backend's JSON. The API client returns
/// `Map<String, dynamic>`; these wrap only the pieces the UI actually renders.
class Product {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String? category;
  final String? brand;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    this.category,
    this.brand,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '—').toString(),
        price: double.tryParse((j['price'] ?? '0').toString()) ?? 0.0,
        imageUrl: (j['image_url'] ?? '').toString(),
        category: j['category']?.toString(),
        brand: j['brand']?.toString(),
      );

  /// Accepts a decoded JSON list, or any other value (yields an empty list).
  static List<Product> list(dynamic json) {
    if (json is List) {
      return json.whereType<Map<String, dynamic>>().map(Product.fromJson).toList();
    }
    return const [];
  }
}

class Category {
  final String name;
  final int productCount;

  Category({required this.name, required this.productCount});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        name: (j['name'] ?? '').toString(),
        productCount: int.tryParse((j['product_count'] ?? '0').toString()) ?? 0,
      );

  static List<Category> list(dynamic json) {
    if (json is List) {
      return json
          .whereType<Map<String, dynamic>>()
          .map(Category.fromJson)
          .toList();
    }
    return const [];
  }
}
