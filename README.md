# Zemi : mise en relation clients / zémidjans (Bénin)

MVP d'une application mobile et web (Flutter) reposant sur Supabase (PostgreSQL + PostGIS + temps réel).

## Fonctions du MVP
- Inscription / connexion (e-mail + mot de passe) avec deux rôles : client ou zémidjan.
- Le conducteur passe « en ligne » : sa position est envoyée toutes les 25 m environ.
- Le client voit sur la carte les zémidjans libres dans un rayon de 500 m ou 1 km.
- Tarification : le client propose un prix (un prix indicatif est calculé à partir des tarifs des conducteurs proches). Le conducteur accepte (attribution immédiate, premier arrivé) ou contre-propose. Le client choisit parmi les contre-propositions.
- Chaque conducteur fixe sa prise en charge et son prix au km.
- Paiement en espèces uniquement. Suivi de course : acceptée, en cours, terminée, annulée.

## Mise en route
1. Créer un projet Supabase, puis exécuter `supabase/migrations/0001_init.sql` (SQL Editor ou `supabase db push`).
2. Dans Authentication, désactiver la confirmation d'e-mail pour les tests (l'inscription suppose une session immédiate).
3. Générer les dossiers de plateforme, puis lancer :
   ```
   cd app && flutter create . --project-name zemi --org bj.zemi
   flutter pub get
   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
   ```
4. Permissions de localisation à ajouter après `flutter create` :
   - Android : `ACCESS_FINE_LOCATION` et `ACCESS_COARSE_LOCATION` dans `AndroidManifest.xml`.
   - iOS : `NSLocationWhenInUseUsageDescription` dans `Info.plist`.

## État de vérification
Ce code n'a **pas** été compilé ni exécuté : Flutter et PostGIS n'étaient pas disponibles dans l'environnement de rédaction. Premier travail à faire : `flutter analyze`, appliquer la migration sur un projet Supabase de test, puis essayer un parcours client/conducteur avec deux appareils.

## Limites connues et prochaines étapes
- Le conducteur peut modifier sa propre ligne `drivers` (dont `is_busy`) : à restreindre avec un trigger avant la production.
- Le conducteur n'est découvert que si sa position date de moins de 2 minutes ; le suivi en arrière-plan demande un service Android dédié (non inclus).
- Les demandes sont actualisées par interrogation toutes les 3 à 5 s ; à passer en temps réel si la charge le justifie.
- La distance utilisée est à vol d'oiseau multipliée par 1,3 (approximation), pas un itinéraire routier.
- Connexion par numéro de téléphone (OTP SMS), Mobile Money (phase 2), notes et avis, vérification des conducteurs, adresses par recherche de lieu : non inclus.
- Les tuiles OpenStreetMap publiques ne conviennent pas à une forte charge : prévoir un fournisseur de tuiles dédié.
- Cadre légal du transport de personnes et protection des données de localisation au Bénin : à vérifier avant lancement.
