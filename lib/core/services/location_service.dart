import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/models/car_record_model.dart';

class LocationDetails {
  final double latitude;
  final double longitude;
  final String district;
  final String street;
  final String gpsUrl;

  const LocationDetails({
    required this.latitude,
    required this.longitude,
    required this.district,
    required this.street,
    required this.gpsUrl,
  });
}

class LocationService {
  static final LocationService instance = LocationService._init();
  LocationService._init();

  final Geocoding _geocoding = Geocoding();

  /// Resolves the device's real GPS position (using last-known fallback only
  /// when a fresh fix times out). Never injects fake static city coordinates.
  Future<LocationDetails?> getCurrentLocationDetails() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        return null;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (position == null) return null;

      String district = 'غير محدد';
      String street = 'غير محدد';

      try {
        final placemarks = await _geocoding
            .placemarkFromCoordinates(position.latitude, position.longitude)
            .timeout(const Duration(seconds: 4));

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          district = place.subLocality?.isNotEmpty == true
              ? place.subLocality!
              : (place.locality?.isNotEmpty == true
                  ? place.locality!
                  : (place.administrativeArea ?? 'غير محدد'));

          street = place.thoroughfare?.isNotEmpty == true
              ? place.thoroughfare!
              : (place.street?.isNotEmpty == true ? place.street! : 'غير محدد');
        }
      } catch (e) {
        debugPrint('Geocoding error/timeout: $e');
      }

      final gpsUrl = CarRecord.buildGpsUrl(position.latitude, position.longitude);

      return LocationDetails(
        latitude: position.latitude,
        longitude: position.longitude,
        district: district,
        street: street,
        gpsUrl: gpsUrl,
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }
}
