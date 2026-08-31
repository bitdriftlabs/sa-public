import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../bd/capture.dart';
import '../config.dart';

/// Thrown for non-2xx HTTP responses (already logged as `api_response_error`).
class ApiError implements Exception {
  final int status;
  ApiError(this.status);
  @override
  String toString() => 'ApiError($status)';
}

/// Shop API client.
///
/// Every call is timed and logged (`api_response` / `api_response_error` /
/// `api_request_failed`) and sends `x-capture-path-template` for dynamic
/// routes so high-cardinality URLs collapse in the dashboard — mirroring the
/// React Native `ApiClient.ts`.
class Api {
  Api._();
  static final HttpClient _client = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;

  static Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? body,
    String? pathTemplate,
  }) async {
    final url = Uri.parse('${Config.backendBaseUrl}$path');
    final start = DateTime.now();
    final loggedPath = pathTemplate ?? path;
    try {
      final req = await _client.openUrl(method, url);
      req.headers.set('accept', 'application/json');
      if (body != null) req.headers.set('content-type', 'application/json');
      if (pathTemplate != null) {
        req.headers.set('x-capture-path-template', '/api$pathTemplate');
      }
      if (body != null) req.write(jsonEncode(body));

      final res = await req.close();
      final text = await res.transform(const Utf8Decoder()).join();
      final durMs = DateTime.now().difference(start).inMilliseconds;

      Map<String, dynamic> data;
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text);
        data = decoded is Map<String, dynamic>
            ? decoded
            : {'value': decoded};
      } else {
        data = <String, dynamic>{};
      }

      final fields = <String, String>{
        'method': method,
        'path': loggedPath,
        'status': '${res.statusCode}',
        'duration_ms': '$durMs',
      };
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await Bd.debug('api_response', fields: fields);
        return data;
      }
      await Bd.warning('api_response_error', fields: fields);
      throw ApiError(res.statusCode);
    } on ApiError {
      rethrow;
    } catch (e) {
      final durMs = DateTime.now().difference(start).inMilliseconds;
      await Bd.error(
        'api_request_failed',
        fields: {
          'method': method,
          'path': loggedPath,
          'duration_ms': '$durMs',
          'error': '$e',
        },
      );
      rethrow;
    }
  }

  // ── read ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> welcome() => request('/welcome');
  static Future<Map<String, dynamic>> browse() => request('/browse');
  static Future<Map<String, dynamic>> search(String q) => request(
        '/search?q=${Uri.encodeQueryComponent(q)}',
      );
  static Future<Map<String, dynamic>> featured() => request('/featured');
  static Future<Map<String, dynamic>> categories() => request('/categories');
  static Future<Map<String, dynamic>> categoryProducts(String c) => request(
        '/categories/${Uri.encodeComponent(c)}',
        pathTemplate: '/categories/<category>',
      );
  static Future<Map<String, dynamic>> product(String id) => request(
        '/product/$id',
        pathTemplate: '/product/<id>',
      );
  static Future<Map<String, dynamic>> reviews(String id) => request(
        '/product/$id/reviews',
        pathTemplate: '/product/<id>/reviews',
      );

  // ── cart / wishlist ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> cart() => request('/cart');
  static Future<Map<String, dynamic>> addToCart(String id, [int qty = 1]) =>
      request('/cart', method: 'POST', body: {'product_id': id, 'quantity': qty});
  static Future<Map<String, dynamic>> removeCartItem(String id) => request(
        '/cart/$id',
        method: 'DELETE',
        pathTemplate: '/cart/<id>',
      );
  static Future<Map<String, dynamic>> wishlist(String id) => request(
        '/wishlist',
        method: 'POST',
        body: {'product_id': id},
      );

  // ── checkout / payment ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> checkoutGuest([String email = '']) =>
      request('/checkout/guest', method: 'POST', body: {'email': email});
  static Future<Map<String, dynamic>> checkoutSignIn([String email = '']) =>
      request('/checkout/signin', method: 'POST', body: {'email': email});
  static Future<Map<String, dynamic>> payCard(String session, [String last4 = '4242']) =>
      request('/payment/card',
          method: 'POST', body: {'checkout_session': session, 'card_last4': last4});
  static Future<Map<String, dynamic>> payApplePay(String session) =>
      request('/payment/applepay',
          method: 'POST', body: {'checkout_session': session});
  static Future<Map<String, dynamic>> payPayPal(String session) =>
      request('/payment/paypal',
          method: 'POST', body: {'checkout_session': session});
  static Future<Map<String, dynamic>> payAndroidPay(String session) =>
      request('/payment/androidpay',
          method: 'POST', body: {'checkout_session': session});
  static Future<Map<String, dynamic>> confirmation(String id) => request(
        '/confirmation/$id',
        pathTemplate: '/confirmation/<id>',
      );
}
