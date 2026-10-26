import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  bool _online = false;
  int _base = 200;
  int _perKm = 100;
  List<OpenRide> _rides = [];
  Map<String, dynamic>? _active; // course assignée / en cours
  Timer? _poll;
  StreamSubscription<Position>? _gps;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _gps?.cancel();
    super.dispose();
  }

  String get _uid => db.auth.currentUser!.id;

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    final d = await db.from('drivers').select('base_fare, price_per_km').eq('id', _uid).single();
    if (!mounted) return;
    setState(() {
      _base = d['base_fare'] as int;
      _perKm = d['price_per_km'] as int;
    });
  }

  Future<void> _pushLocation(double lat, double lng) => db.from('drivers').update({
        'location': 'SRID=4326;POINT($lng $lat)',
        'location_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _uid);

  Future<void> _toggle(bool on) async {
    if (on) {
      final p = await currentPosition();
      if (!p.real) {
        _toast('Activez la localisation pour recevoir des courses.');
        return;
      }
      await db.from('drivers').update({'is_online': true}).eq('id', _uid);
      await _pushLocation(p.lat, p.lng);
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25),
      ).listen((pos) => _pushLocation(pos.latitude, pos.longitude));
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
      setState(() => _online = true);
      _refresh();
    } else {
      _poll?.cancel();
      await _gps?.cancel();
      await db.from('drivers').update({'is_online': false}).eq('id', _uid);
      setState(() {
        _online = false;
        _rides = [];
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final active = await db
          .from('rides')
          .select()
          .eq('driver_id', _uid)
          .inFilter('status', ['assigned', 'in_progress'])
          .maybeSingle();
      final rides = active == null ? await openRides(defaultRadiusM) : <OpenRide>[];
      if (mounted) setState(() {
        _active = active;
        _rides = rides;
      });
    } catch (_) {/* réessai au prochain cycle */}
  }

  Future<void> _answer(OpenRide r, int price) async {
    try {
      final res = await makeOffer(r.id, price);
      _toast(res == 'assigned' ? 'Course acceptée !' : 'Contre-proposition envoyée.');
      _refresh();
    } catch (e) {
      _toast(errorText(e));
      _refresh();
    }
  }

  Future<void> _counter(OpenRide r) async {
    final c = TextEditingController(text: '${r.offeredPrice}');
    final price = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Votre prix (FCFA)'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('Envoyer')),
        ],
      ),
    );
    c.dispose();
    if (price != null && price > 0) _answer(r, price);
  }

  Future<void> _editTariff() async {
    final b = TextEditingController(text: '$_base');
    final k = TextEditingController(text: '$_perKm');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mon tarif'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: b, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prise en charge (FCFA)')),
          TextField(controller: k, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix par km (FCFA)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    final nb = int.tryParse(b.text.trim()), nk = int.tryParse(k.text.trim());
    b.dispose();
    k.dispose();
    if (ok == true && nb != null && nk != null && nb >= 0 && nk >= 0) {
      await db.from('drivers').update({'base_fare': nb, 'price_per_km': nk}).eq('id', _uid);
      setState(() {
        _base = nb;
        _perKm = nk;
      });
    }
  }

  Future<void> _step(Future<void> Function(String) f) async {
    await f(_active!['id'] as String);
    _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Zemi · Zémidjan'), actions: [
          IconButton(
              tooltip: 'Se déconnecter',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                if (_online) await _toggle(false);
                await db.auth.signOut();
              }),
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SwitchListTile(
            title: Text(_online ? 'Vous êtes en ligne' : 'Vous êtes hors ligne'),
            subtitle: const Text('En ligne, les clients à moins de 1 km vous voient.'),
            value: _online,
            onChanged: _toggle,
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text('Mon tarif : $_base FCFA + $_perKm FCFA/km'),
            subtitle: const Text('Utilisé pour le prix indicatif montré aux clients.'),
            trailing: const Icon(Icons.edit),
            onTap: _editTariff,
          ),
          const Divider(),
          if (_active != null) ..._activeCard() else if (_online) ..._requests(),
        ]),
      );

  List<Widget> _activeCard() {
    final a = _active!;
    final started = a['status'] == 'in_progress';
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(started ? 'Course en cours' : 'Course acceptée', style: Theme.of(context).textTheme.titleMedium),
            Text('Prix convenu : ${a['agreed_price']} FCFA (espèces)'),
            Text('Distance estimée : ${a['distance_km']} km'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (!started) FilledButton(onPressed: () => _step(startRide), child: const Text('Démarrer')),
              if (started) FilledButton(onPressed: () => _step(completeRide), child: const Text('Terminer')),
              if (!started) OutlinedButton(onPressed: () => _step(cancelRide), child: const Text('Annuler')),
            ]),
          ]),
        ),
      ),
    ];
  }

  List<Widget> _requests() {
    if (_rides.isEmpty) return [const Padding(padding: EdgeInsets.all(16), child: Text('Aucune demande à proximité pour le moment.'))];
    return [
      for (final r in _rides)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.clientName} · à ${r.distanceM.round()} m', style: Theme.of(context).textTheme.titleSmall),
              Text('Trajet ≈ ${r.distanceKm.toStringAsFixed(1)} km · prix proposé : ${r.offeredPrice} FCFA'),
              if (r.myOfferPrice != null) Text('Votre contre-proposition : ${r.myOfferPrice} FCFA (en attente)'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: () => _answer(r, r.offeredPrice), child: Text('Accepter ${r.offeredPrice}')),
                OutlinedButton(onPressed: () => _counter(r), child: const Text('Contre-proposer')),
              ]),
            ]),
          ),
        ),
    ];
  }
}
