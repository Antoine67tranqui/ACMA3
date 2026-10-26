import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';

final db = Supabase.instance.client;

/// Position courante, ou le centre de repli si la permission est refusée.
Future<({double lat, double lng, bool real})> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) throw Exception('gps_off');
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw Exception('denied');
    }
    final p = await Geolocator.getCurrentPosition();
    return (lat: p.latitude, lng: p.longitude, real: true);
  } catch (_) {
    return (lat: fallbackLat, lng: fallbackLng, real: false);
  }
}

Future<List<NearbyDriver>> nearbyDrivers(double lat, double lng, int radiusM) async {
  final rows = await db.rpc('nearby_drivers',
      params: {'p_lat': lat, 'p_lng': lng, 'p_radius_m': radiusM}) as List;
  return rows.map((r) => NearbyDriver.fromJson(r as Map<String, dynamic>)).toList();
}

Future<List<OpenRide>> openRides(int radiusM) async {
  final rows = await db.rpc('open_rides_near', params: {'p_radius_m': radiusM}) as List;
  return rows.map((r) => OpenRide.fromJson(r as Map<String, dynamic>)).toList();
}

Future<String> createRide({
  required double pickupLat,
  required double pickupLng,
  required double dropLat,
  required double dropLng,
  required double distanceKm,
  required int price,
  String? pickupLabel,
  String? dropLabel,
}) async {
  final row = await db.from('rides').insert({
    'client_id': db.auth.currentUser!.id,
    'pickup': 'SRID=4326;POINT($pickupLng $pickupLat)',
    'dropoff': 'SRID=4326;POINT($dropLng $dropLat)',
    'pickup_label': pickupLabel,
    'dropoff_label': dropLabel,
    'distance_km': distanceKm,
    'offered_price': price,
  }).select('id').single();
  return row['id'] as String;
}

Future<String> makeOffer(String rideId, int price) async =>
    await db.rpc('make_offer', params: {'p_ride_id': rideId, 'p_price': price}) as String;

Future<void> acceptOffer(String offerId) => db.rpc('accept_offer', params: {'p_offer_id': offerId});
Future<void> startRide(String id) => db.rpc('start_ride', params: {'p_ride_id': id});
Future<void> completeRide(String id) => db.rpc('complete_ride', params: {'p_ride_id': id});
Future<void> cancelRide(String id) => db.rpc('cancel_ride', params: {'p_ride_id': id});

/// Message lisible pour l'utilisateur à partir d'une erreur Postgres.
String errorText(Object e) {
  final s = e.toString();
  if (s.contains('ride_unavailable')) return "Cette demande n'est plus disponible.";
  if (s.contains('driver_unavailable')) return "Ce conducteur n'est plus disponible.";
  if (s.contains('offer_unavailable')) return "Cette offre n'est plus valable.";
  if (s.contains('invalid_price')) return 'Prix invalide.';
  return 'Une erreur est survenue. Réessayez.';
}

Future<List<Map<String, dynamic>>> offersFor(String rideId) async {
  final rows = await db.rpc('ride_offers_for_client', params: {'p_ride_id': rideId}) as List;
  return rows.cast<Map<String, dynamic>>();
}
