class NearbyDriver {
  NearbyDriver.fromJson(Map<String, dynamic> j)
      : id = j['driver_id'] as String,
        name = j['full_name'] as String,
        plate = j['plate'] as String,
        lat = (j['lat'] as num).toDouble(),
        lng = (j['lng'] as num).toDouble(),
        distanceM = (j['distance_m'] as num).toDouble(),
        baseFare = j['base_fare'] as int,
        pricePerKm = j['price_per_km'] as int;

  final String id, name, plate;
  final double lat, lng, distanceM;
  final int baseFare, pricePerKm;

  /// Prix indicatif de ce conducteur pour une distance donnée (arrondi à 50 FCFA).
  int estimate(double km) => roundPrice(baseFare + pricePerKm * km);
}

class OpenRide {
  OpenRide.fromJson(Map<String, dynamic> j)
      : id = j['ride_id'] as String,
        clientName = j['client_name'] as String,
        pickupLabel = j['pickup_label'] as String?,
        dropoffLabel = j['dropoff_label'] as String?,
        distanceKm = (j['distance_km'] as num).toDouble(),
        offeredPrice = j['offered_price'] as int,
        distanceM = (j['distance_m'] as num).toDouble(),
        myOfferPrice = j['my_offer_price'] as int?;

  final String id, clientName;
  final String? pickupLabel, dropoffLabel;
  final double distanceKm, distanceM;
  final int offeredPrice;
  final int? myOfferPrice;
}

int roundPrice(num v) => ((v / 50).round() * 50).clamp(100, 1000000).toInt();

/// Facteur appliqué à la distance à vol d'oiseau pour approcher la distance routière.
const roadFactor = 1.3;
