import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';

class ClientHome extends StatefulWidget {
  const ClientHome({super.key});

  @override
  State<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<ClientHome> {
  final _map = MapController();
  final _offer = TextEditingController();
  Timer? _poll;
  LatLng? _me;
  LatLng? _dest;
  int _radius = defaultRadiusM;
  List<NearbyDriver> _drivers = [];
  String? _rideId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _offer.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final p = await currentPosition();
    if (!mounted) return;
    setState(() => _me = LatLng(p.lat, p.lng));
    if (!p.real) _toast('Localisation indisponible : position approximative (Cotonou).');
    _map.move(_me!, 15);
    await _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_me == null || _rideId != null) return;
    try {
      final d = await nearbyDrivers(_me!.latitude, _me!.longitude, _radius);
      if (mounted) setState(() => _drivers = d);
    } catch (_) {/* réseau instable : on réessaie au prochain cycle */}
  }

  double get _km => _dest == null
      ? 0
      : const Distance().as(LengthUnit.Kilometer, _me!, _dest!) * roadFactor;

  /// Prix indicatif moyen des conducteurs proches (null si aucun).
  int? get _suggested {
    if (_dest == null || _drivers.isEmpty) return null;
    final sum = _drivers.fold<int>(0, (a, d) => a + d.estimate(_km));
    return roundPrice(sum / _drivers.length);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _request() async {
    final price = int.tryParse(_offer.text.trim());
    if (_dest == null || price == null || price <= 0) {
      _toast('Choisissez une destination sur la carte et indiquez votre prix.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await createRide(
        pickupLat: _me!.latitude,
        pickupLng: _me!.longitude,
        dropLat: _dest!.latitude,
        dropLng: _dest!.longitude,
        distanceKm: double.parse(_km.toStringAsFixed(2)),
        price: price,
        pickupLabel: 'Ma position',
        dropLabel: 'Destination choisie',
      );
      setState(() => _rideId = id);
    } catch (e) {
      _toast(errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _endRide() {
    setState(() {
      _rideId = null;
      _dest = null;
      _offer.clear();
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zemi'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => db.auth.signOut(),
          ),
        ],
      ),
      body: me == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: me,
                    initialZoom: 15,
                    onTap: _rideId != null ? null : (_, p) => setState(() => _dest = p),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'bj.zemi.app',
                    ),
                    CircleLayer(circles: [
                      CircleMarker(
                        point: me,
                        radius: _radius.toDouble(),
                        useRadiusInMeter: true,
                        color: Colors.green.withValues(alpha: 0.08),
                        borderColor: Colors.green,
                        borderStrokeWidth: 1.5,
                      ),
                    ]),
                    MarkerLayer(markers: [
                      Marker(
                          point: me,
                          child: const Icon(Icons.my_location, color: Colors.blue, size: 30)),
                      if (_dest != null)
                        Marker(
                            point: _dest!,
                            child: const Icon(Icons.location_on, color: Colors.red, size: 36)),
                      for (final d in _drivers)
                        Marker(
                          point: LatLng(d.lat, d.lng),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.two_wheeler, color: Colors.black87, size: 30),
                        ),
                    ]),
                  ],
                ),
              ),
              _rideId != null ? _tracker() : _requestPanel(),
            ]),
    );
  }

  Widget _requestPanel() {
    final suggested = _suggested;
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(_drivers.isEmpty
                  ? 'Aucun zémidjan libre dans ce rayon'
                  : '${_drivers.length} zémidjan(s) libre(s) à proximité'),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: smallRadiusM, label: Text('500 m')),
                ButtonSegment(value: defaultRadiusM, label: Text('1 km')),
              ],
              selected: {_radius},
              onSelectionChanged: (s) {
                setState(() => _radius = s.first);
                _refresh();
              },
            ),
          ]),
          const SizedBox(height: 8),
          Text(_dest == null
              ? 'Touchez la carte pour choisir votre destination.'
              : 'Distance estimée : ${_km.toStringAsFixed(1)} km'
                  '${suggested != null ? ' · prix indicatif : $suggested FCFA' : ''}'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _offer,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Votre prix (FCFA)', isDense: true),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : _request,
              child: const Text('Appeler un zémidjan'),
            ),
          ]),
          if (suggested != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _offer.text = '$suggested',
                child: Text('Utiliser le prix indicatif ($suggested FCFA)'),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _tracker() => _RideTracker(rideId: _rideId!, onDone: _endRide);
}

class _RideTracker extends StatefulWidget {
  const _RideTracker({required this.rideId, required this.onDone});
  final String rideId;
  final VoidCallback onDone;

  @override
  State<_RideTracker> createState() => _RideTrackerState();
}

class _RideTrackerState extends State<_RideTracker> {
  List<Map<String, dynamic>> _offers = [];
  Map<String, dynamic>? _driver;
  Timer? _poll;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _loadOffers());
    _loadOffers();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadOffers() async {
    try {
      final o = await offersFor(widget.rideId);
      if (mounted) setState(() => _offers = o);
    } catch (_) {}
  }

  Future<void> _loadDriver(String driverId) async {
    if (_loadedFor == driverId) return;
    _loadedFor = driverId;
    final p = await db.from('profiles').select('full_name, phone').eq('id', driverId).single();
    final d = await db.from('drivers').select('plate').eq('id', driverId).single();
    if (mounted) setState(() => _driver = {...p, ...d});
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        elevation: 8,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: db.from('rides').stream(primaryKey: ['id']).eq('id', widget.rideId),
          builder: (context, snap) {
            final ride = (snap.data?.isNotEmpty ?? false) ? snap.data!.first : null;
            if (ride == null) {
              return const Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator());
            }
            final status = ride['status'] as String;
            if (ride['driver_id'] != null) _loadDriver(ride['driver_id'] as String);
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._body(ride, status),
              ]),
            );
          },
        ),
      );

  List<Widget> _body(Map<String, dynamic> ride, String status) {
    switch (status) {
      case 'requested':
        return [
          Text('Demande envoyée aux zémidjans proches · ${ride['offered_price']} FCFA'),
          const SizedBox(height: 8),
          if (_offers.isEmpty) const LinearProgressIndicator(),
          for (final o in _offers)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${o['driver_name']} · ${o['price']} FCFA'),
              subtitle: Text('Moto ${o['plate']}'),
              trailing: FilledButton(
                onPressed: () => _run(() => acceptOffer(o['offer_id'] as String)),
                child: const Text('Accepter'),
              ),
            ),
          TextButton(
            onPressed: () => _run(() async {
              await cancelRide(widget.rideId);
              widget.onDone();
            }),
            child: const Text('Annuler la demande'),
          ),
        ];
      case 'assigned':
      case 'in_progress':
        return [
          Text(status == 'assigned' ? 'Votre zémidjan arrive' : 'Course en cours',
              style: Theme.of(context).textTheme.titleMedium),
          if (_driver != null)
            Text('${_driver!['full_name']} · moto ${_driver!['plate']} · ${_driver!['phone']}'),
          Text('Prix convenu : ${ride['agreed_price']} FCFA (paiement en espèces)'),
          if (status == 'assigned')
            TextButton(
              onPressed: () => _run(() async {
                await cancelRide(widget.rideId);
                widget.onDone();
              }),
              child: const Text('Annuler la course'),
            ),
        ];
      case 'completed':
        return [
          Text('Course terminée · ${ride['agreed_price']} FCFA', style: Theme.of(context).textTheme.titleMedium),
          FilledButton(onPressed: widget.onDone, child: const Text('Nouvelle course')),
        ];
      default:
        return [
          const Text('Demande annulée.'),
          FilledButton(onPressed: widget.onDone, child: const Text('Nouvelle course')),
        ];
    }
  }
}
