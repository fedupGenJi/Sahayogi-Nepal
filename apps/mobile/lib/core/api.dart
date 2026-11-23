import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the `{ data, error }` contract from docs/API-CONTRACT.md.
class ApiResult<T> {
  final T? data;
  final String? errorCode;
  final String? errorMessage;
  const ApiResult({this.data, this.errorCode, this.errorMessage});
  bool get ok => errorCode == null;
}

class Api {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Authenticated volunteer endpoints. Supabase Functions attaches the active
  /// session's access token to these requests.
  static Future<ApiResult<dynamic>> volunteerAction(
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final response = await _sb.functions.invoke(
        'volunteer-api/$action',
        body: body,
      );
      final envelope = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      if (rawError is Map) {
        final error = Map<String, dynamic>.from(rawError);
        return ApiResult(
          errorCode: error['code']?.toString() ?? 'volunteer_api_failed',
          errorMessage: error['message']?.toString() ??
              'The request could not be completed.',
        );
      }
      if (!envelope.containsKey('data')) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected response.',
        );
      }
      return ApiResult<dynamic>(data: envelope['data']);
    } on FunctionException catch (error) {
      final details = error.details;
      final envelope = details is Map
          ? Map<String, dynamic>.from(details)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      final body = rawError is Map
          ? Map<String, dynamic>.from(rawError)
          : <String, dynamic>{};
      return ApiResult(
        errorCode: body['code']?.toString() ?? 'volunteer_api_failed',
        errorMessage: body['message']?.toString() ?? error.toString(),
      );
    } catch (error) {
      return ApiResult(errorCode: 'network', errorMessage: error.toString());
    }
  }

  static Future<ApiResult<List<Map<String, dynamic>>>>
      getVolunteerOffers() async {
    final result = await volunteerAction('offers');
    if (!result.ok) {
      return ApiResult(
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      );
    }
    if (result.data is! List) {
      return const ApiResult(
        errorCode: 'invalid_response',
        errorMessage: 'The server returned an unexpected offers response.',
      );
    }
    return ApiResult(
      data: (result.data as List)
          .whereType<Map>()
          .map((offer) => Map<String, dynamic>.from(offer))
          .toList(),
    );
  }

  static Future<ApiResult<List<Map<String, dynamic>>>>
      getNearbyVolunteerOffers({
    required double latitude,
    required double longitude,
    double radiusKm = 100,
  }) async {
    final result = await volunteerAction(
      'offers/nearby',
      body: {
        'lat': latitude,
        'lng': longitude,
        'radius_km': radiusKm,
      },
    );
    dynamic responseData = result.data;
    if (!result.ok && result.errorCode == 'unknown_action') {
      // Older deployed Edge Function versions may not have the nested route yet.
      // The authenticated RPC applies the same volunteer, tier, and distance rules.
      try {
        responseData = await _sb.rpc(
          'nearby_offers',
          params: {
            'p_lat': latitude,
            'p_lng': longitude,
            'p_radius_km': radiusKm,
          },
        );
      } catch (error) {
        return ApiResult(
          errorCode: 'nearby_offers_failed',
          errorMessage: error.toString(),
        );
      }
    } else if (!result.ok) {
      return ApiResult(
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      );
    }
    if (responseData is! List) {
      return const ApiResult(
        errorCode: 'invalid_response',
        errorMessage:
            'The server returned an unexpected nearby offers response.',
      );
    }
    return ApiResult(
      data: responseData.whereType<Map>().map((offer) {
        final normalized = Map<String, dynamic>.from(offer);
        normalized['id'] ??= normalized['assignment_id'];
        return normalized;
      }).toList(),
    );
  }

  static Future<ApiResult<Map<String, dynamic>>> getVolunteerStats() async {
    final result = await volunteerAction('stats');
    return _mapResult(result, 'stats');
  }

  static Future<ApiResult<List<Map<String, dynamic>>>>
      getVolunteerRequestHistory() async {
    final result = await volunteerAction('requests');
    if (!result.ok) {
      return ApiResult(
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      );
    }
    if (result.data is! List) {
      return const ApiResult(
        errorCode: 'invalid_response',
        errorMessage:
            'The server returned an unexpected request history response.',
      );
    }
    return ApiResult(
      data: (result.data as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
    );
  }

  static Future<ApiResult<Map<String, dynamic>>> getVolunteerAssignment(
    String id,
  ) async {
    final result =
        await volunteerAction('assignments/detail', body: {'id': id});
    return _mapResult(result, 'assignment');
  }

  static Future<ApiResult<Map<String, dynamic>>> getVolunteerRoutePreview({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    try {
      final response = await _sb.functions.invoke(
        'get-route',
        body: {
          'locations': [
            {'lat': originLatitude, 'lon': originLongitude},
            {'lat': destinationLatitude, 'lon': destinationLongitude},
          ],
        },
      );
      final envelope = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      if (rawError is Map) {
        final error = Map<String, dynamic>.from(rawError);
        return ApiResult(
          errorCode: error['code']?.toString() ?? 'route_failed',
          errorMessage:
              error['message']?.toString() ?? 'Could not load a route preview.',
        );
      }
      final data = envelope['data'];
      if (data is! Map) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected route response.',
        );
      }
      return ApiResult(data: Map<String, dynamic>.from(data));
    } on FunctionException catch (error) {
      final details = error.details;
      final envelope = details is Map
          ? Map<String, dynamic>.from(details)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      final body = rawError is Map
          ? Map<String, dynamic>.from(rawError)
          : <String, dynamic>{};
      return ApiResult(
        errorCode: body['code']?.toString() ?? 'route_failed',
        errorMessage: body['message']?.toString() ?? error.toString(),
      );
    } catch (error) {
      return ApiResult(
          errorCode: 'route_failed', errorMessage: error.toString());
    }
  }

  static Future<ApiResult<Map<String, dynamic>>> claimVolunteerAssignment(
    String id,
  ) async {
    final result = await volunteerAction('assignments/claim', body: {'id': id});
    return _mapResult(result, 'assignment');
  }

  static Future<ApiResult<Map<String, dynamic>>> updateVolunteerAssignmentState(
    String id,
    String state,
  ) async {
    final result = await volunteerAction(
      'assignments/state',
      body: {'id': id, 'state': state},
    );
    return _mapResult(result, 'assignment state');
  }

  static Future<ApiResult<Map<String, dynamic>>> verifyVolunteerOtp({
    required String id,
    required String purpose,
    required String code,
    bool confirmed = false,
  }) async {
    final result = await volunteerAction(
      'assignments/verify-otp',
      body: {
        'id': id,
        'purpose': purpose,
        'code': code,
        if (confirmed) 'confirmed': true,
      },
    );
    return _mapResult(result, 'OTP verification');
  }

  static Future<ApiResult<Map<String, dynamic>>> reportVolunteerIssue({
    required String id,
    required String type,
    required String note,
  }) async {
    final result = await volunteerAction(
      'assignments/report-issue',
      body: {'id': id, 'type': type, 'note': note},
    );
    return _mapResult(result, 'issue report');
  }

  static Future<ApiResult<Map<String, dynamic>>> updateVolunteerLocation({
    required String id,
    required double latitude,
    required double longitude,
  }) async {
    final result = await volunteerAction(
      'assignments/location',
      body: {'id': id, 'lat': latitude, 'lng': longitude},
    );
    return _mapResult(result, 'location update');
  }

  static ApiResult<Map<String, dynamic>> _mapResult(
    ApiResult<dynamic> result,
    String label,
  ) {
    if (!result.ok) {
      return ApiResult(
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      );
    }
    if (result.data is! Map) {
      return ApiResult(
        errorCode: 'invalid_response',
        errorMessage: 'The server returned an unexpected $label response.',
      );
    }
    return ApiResult(data: Map<String, dynamic>.from(result.data as Map));
  }

  /// Public, privacy-preserving map markers from the `map_markers` RPC.
  static Future<ApiResult<List<Map<String, dynamic>>>> getMapMarkers() async {
    try {
      final raw = await _sb.rpc('map_markers');
      if (raw is! List) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected map response.',
        );
      }
      return ApiResult(
        data: raw
            .whereType<Map>()
            .map((marker) => Map<String, dynamic>.from(marker))
            .toList(),
      );
    } catch (e) {
      return ApiResult(errorCode: 'map_failed', errorMessage: e.toString());
    }
  }

  /// Public tracking lookup. The ref and secret token together prove ownership.
  static Future<ApiResult<Map<String, dynamic>>> getRequestTracking({
    required String reference,
    required String token,
  }) async {
    try {
      final res = await _sb.functions.invoke(
        'public-api/tracking',
        body: {'ref': reference, 'token': token},
      );
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final rawError = body['error'];
      final err = rawError is Map ? Map<String, dynamic>.from(rawError) : null;
      if (err != null) {
        return ApiResult(
          errorCode: err['code']?.toString() ?? 'tracking_failed',
          errorMessage:
              err['message']?.toString() ?? 'Could not load tracking.',
        );
      }
      final rawData = body['data'];
      if (rawData is! Map) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected tracking response.',
        );
      }
      return ApiResult(data: Map<String, dynamic>.from(rawData));
    } on FunctionException catch (e) {
      final details = e.details;
      final rawError = details is Map ? details['error'] : null;
      final err = rawError is Map ? rawError : null;
      return ApiResult(
        errorCode: err?['code']?.toString() ?? 'tracking_failed',
        errorMessage: err?['message']?.toString() ?? e.toString(),
      );
    } catch (e) {
      return ApiResult(errorCode: 'network', errorMessage: e.toString());
    }
  }

  /// Public requester actions. These functions intentionally work without a
  /// volunteer session; the ref and one-time tracking token authorize them.
  static Future<ApiResult<dynamic>> publicTrackingAction(
    String action, {
    required String reference,
    required String token,
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final response = await _sb.functions.invoke(
        'public-api/tracking/$action',
        body: {'ref': reference, 'token': token, ...body},
      );
      final envelope = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      if (rawError is Map) {
        final error = Map<String, dynamic>.from(rawError);
        return ApiResult(
          errorCode: error['code']?.toString() ?? 'tracking_action_failed',
          errorMessage:
              error['message']?.toString() ?? 'Could not complete this action.',
        );
      }
      if (!envelope.containsKey('data')) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected response.',
        );
      }
      return ApiResult<dynamic>(data: envelope['data']);
    } on FunctionException catch (error) {
      final details = error.details;
      final envelope = details is Map
          ? Map<String, dynamic>.from(details)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      final body = rawError is Map
          ? Map<String, dynamic>.from(rawError)
          : <String, dynamic>{};
      return ApiResult(
        errorCode: body['code']?.toString() ?? 'tracking_action_failed',
        errorMessage: body['message']?.toString() ?? error.toString(),
      );
    } catch (error) {
      return ApiResult(errorCode: 'network', errorMessage: error.toString());
    }
  }

  static Future<ApiResult<Map<String, dynamic>>> requestTrackingOtp({
    required String reference,
    required String token,
    required String purpose,
  }) async {
    final result = await publicTrackingAction(
      'otp',
      reference: reference,
      token: token,
      body: {'purpose': purpose},
    );
    return _mapResult(result, 'OTP');
  }

  static Future<ApiResult<Map<String, dynamic>>>
      updateDonationPickupQuantities({
    required String reference,
    required String token,
    required List<Map<String, dynamic>> items,
  }) async {
    final result = await publicTrackingAction(
      'pickup-qty',
      reference: reference,
      token: token,
      body: {'items': items},
    );
    return _mapResult(result, 'pickup quantities');
  }

  static Future<ApiResult<Map<String, dynamic>>> confirmRequestDelivery({
    required String reference,
    required String token,
    required bool full,
    String? note,
    List<Map<String, dynamic>>? shortfall,
  }) async {
    final result = await publicTrackingAction(
      'confirm-delivery',
      reference: reference,
      token: token,
      body: {
        'full': full,
        if (note != null) 'note': note,
        if (shortfall != null) 'shortfall': shortfall,
      },
    );
    return _mapResult(result, 'delivery confirmation');
  }

  /// Anonymous public intake via Edge Function (no direct table insert).
  static Future<ApiResult<Map<String, dynamic>>> submitRequest(
      Map<String, dynamic> payload) async {
    try {
      final res = await _sb.functions.invoke('submit-request', body: payload);
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final rawError = body['error'];
      final err = rawError is Map ? Map<String, dynamic>.from(rawError) : null;
      if (err != null) {
        return ApiResult(
          errorCode: err['code']?.toString() ?? 'request_failed',
          errorMessage:
              err['message']?.toString() ?? 'Could not submit request.',
        );
      }
      final rawData = body['data'];
      if (rawData is! Map) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The server returned an unexpected response.',
        );
      }
      return ApiResult(data: Map<String, dynamic>.from(rawData));
    } on FunctionException catch (e) {
      final d = e.details;
      final rawError = d is Map ? d['error'] : null;
      final err = rawError is Map ? rawError : null;
      return ApiResult(
        errorCode: err?['code']?.toString() ?? 'request_failed',
        errorMessage: err?['message']?.toString() ?? e.toString(),
      );
    } catch (e) {
      return ApiResult(errorCode: 'network', errorMessage: e.toString());
    }
  }

  /// Sends a description to the constrained server-side form assistant. The
  /// function returns values only; it cannot submit requests or edit layout.
  static Future<ApiResult<Map<String, dynamic>>> assistForm({
    required String formType,
    required String message,
  }) async {
    try {
      final response = await _sb.functions.invoke(
        'assist-form',
        body: {
          'form_type': formType,
          'message': message,
        },
      );
      final envelope = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      if (rawError is Map) {
        final error = Map<String, dynamic>.from(rawError);
        return ApiResult(
          errorCode: error['code']?.toString() ?? 'assistant_failed',
          errorMessage: error['message']?.toString() ??
              'Could not prepare suggestions.',
        );
      }
      final rawData = envelope['data'];
      if (rawData is! Map || rawData['suggestions'] is! Map) {
        return const ApiResult(
          errorCode: 'invalid_response',
          errorMessage: 'The assistant returned an unexpected response.',
        );
      }
      return ApiResult(data: Map<String, dynamic>.from(rawData));
    } on FunctionException catch (error) {
      final details = error.details;
      final envelope = details is Map
          ? Map<String, dynamic>.from(details)
          : <String, dynamic>{};
      final rawError = envelope['error'];
      final body = rawError is Map
          ? Map<String, dynamic>.from(rawError)
          : <String, dynamic>{};
      return ApiResult(
        errorCode: body['code']?.toString() ?? 'assistant_failed',
        errorMessage:
            body['message']?.toString() ?? 'Could not prepare suggestions.',
      );
    } catch (error) {
      return ApiResult(errorCode: 'network', errorMessage: error.toString());
    }
  }
}
