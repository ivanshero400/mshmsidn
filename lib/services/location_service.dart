import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Search result from Nominatim forward geocoding
class SearchResult {
  final String name;
  final String displayName;
  final double lat;
  final double lng;
  final String? state;
  final String? country;

  const SearchResult({
    required this.name,
    required this.displayName,
    required this.lat,
    required this.lng,
    this.state,
    this.country,
  });
}

/// Manages location – either GPS (free) or manual city selection
/// Uses Nominatim (OpenStreetMap) for reverse geocoding – completely free
/// Extracts full hierarchical address: village → town → city → state → country
class LocationService extends ChangeNotifier {
  static const _keyLat = 'loc_lat';
  static const _keyLng = 'loc_lng';
  static const _keyVillage = 'loc_village';
  static const _keyTown = 'loc_town';
  static const _keyCity = 'loc_city';
  static const _keyState = 'loc_state';
  static const _keyCountry = 'loc_country';
  static const _keyUseGps = 'loc_use_gps';
  static const _keyDisplay = 'loc_display';
  static const _keySetupDone = 'loc_setup_done';
  static const _keyLastCity = 'loc_last_city'; // for travel detection

  // Default: Riyadh
  double _latitude = 24.7136;
  double _longitude = 46.6753;
  String _village = '';
  String _town = '';
  String _cityName = 'الرياض';
  String _state = 'منطقة الرياض';
  String _country = 'السعودية';
  String _displayName = 'الرياض، السعودية';
  bool _useGps = true;

  double get latitude => _latitude;
  double get longitude => _longitude;
  String get village => _village;
  String get town => _town;
  String get cityName => _cityName;
  String get state => _state;
  String get country => _country;

  /// Smart display: skips empty levels, shows most relevant
  /// e.g. "حي العقيق، المدينة المنورة، السعودية"
  String get displayName => _displayName;

  /// Fine-grained text for the header (one line compact)
  /// e.g. "المدينة المنورة · منطقة المدينة"
  String get compactName {
    final parts = <String>[];
    if (_cityName.isNotEmpty) parts.add(_cityName);
    if (_state.isNotEmpty && _state != _cityName) parts.add(_state);
    if (parts.isEmpty) parts.add(_country);
    return parts.join('، ');
  }

  bool get useGps => _useGps;

  /// Callback triggered when GPS auto-detection notices a city change
  VoidCallback? onCityChanged;

  /// Whether the user has completed initial location setup
  bool _setupDone = false;
  bool get setupDone => _setupDone;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _setupDone = p.getBool(_keySetupDone) ?? false;
    _useGps = p.getBool(_keyUseGps) ?? true;
    _latitude = p.getDouble(_keyLat) ?? 24.7136;
    _longitude = p.getDouble(_keyLng) ?? 46.6753;
    _village = p.getString(_keyVillage) ?? '';
    _town = p.getString(_keyTown) ?? '';
    _cityName = p.getString(_keyCity) ?? 'الرياض';
    _state = p.getString(_keyState) ?? '';
    _country = p.getString(_keyCountry) ?? 'السعودية';
    _displayName = p.getString(_keyDisplay) ?? 'الرياض، السعودية';

    // Remember previous city for travel detection
    final previousCity = p.getString(_keyLastCity) ?? '';

    // Always try to update GPS if GPS mode is enabled and setup is done
    if (_useGps && _setupDone) {
      await detectGps(); // silent update - doesn't block if fails

      // Check if city changed → notify travel prayer reminder
      if (_cityName.isNotEmpty && previousCity.isNotEmpty && _cityName != previousCity) {
        onCityChanged?.call();
      }
    }

    // Save current city for next comparison
    await p.setString(_keyLastCity, _cityName);

    notifyListeners();
  }

  /// Check if user is in a European country (for defaulting to French method)
  bool get isInEurope {
    const euCountries = [
      'فرنسا', 'ألمانيا', 'بريطانيا', 'إنجلترا', 'إيطاليا', 'إسبانيا',
      'هولندا', 'بلجيكا', 'سويسرا', 'النمسا', 'السويد', 'النرويج',
      'الدنمارك', 'فنلندا', 'بولندا', 'البرتغال', 'اليونان', 'أيرلندا',
      'France', 'Germany', 'United Kingdom', 'England', 'Italy', 'Spain',
      'Netherlands', 'Belgium', 'Switzerland', 'Austria', 'Sweden', 'Norway',
      'Denmark', 'Finland', 'Poland', 'Portugal', 'Greece', 'Ireland',
      'UK', 'DE', 'FR', 'IT', 'ES', 'NL', 'BE', 'CH', 'AT', 'SE', 'NO',
    ];
    return euCountries.any((c) =>
        _country.contains(c) || _state.contains(c));
  }

  /// GPS detection with full hierarchical reverse geocoding
  Future<bool> detectGps() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }
      if (permission == LocationPermission.deniedForever) return false;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _latitude = pos.latitude;
      _longitude = pos.longitude;

      // Reverse geocode via free Nominatim API (OpenStreetMap)
      await _reverseGeocode(pos.latitude, pos.longitude);

      _useGps = true;
      await _save();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reverse geocode coordinates into full hierarchical address
  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&accept-language=ar'
        '&zoom=14&addressdetails=1',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'AuraAdhanApp/1.0 (azan@mshmsidn.com)',
      });
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final address = data['address'] as Map<String, dynamic>?;
      if (address == null) return;

      // Extract all levels from Nominatim
      _village = (address['village'] ??
              address['hamlet'] ??
              address['suburb'] ??
              address['neighbourhood'] ??
              '')
          .toString();
      _town = (address['town'] ?? address['city_district'] ?? '').toString();
      _cityName =
          (address['city'] ?? address['municipality'] ?? '').toString();
      _state = (address['state'] ?? address['region'] ?? address['county'] ?? '')
          .toString();
      _country = (address['country'] ?? '').toString();

      // Build smart display name
      _displayName = _buildDisplayName();
    } catch (_) {/* keep previous values */}
  }

  /// Build hierarchical display string, skipping empty levels
  String _buildDisplayName() {
    final parts = <String>[];

    // Include village/suburb if distinctive
    if (_village.isNotEmpty && _village != _town && _village != _cityName) {
      parts.add(_village);
    }

    if (_town.isNotEmpty && _town != _cityName) {
      parts.add(_town);
    }

    if (_cityName.isNotEmpty) {
      parts.add(_cityName);
    }

    if (_state.isNotEmpty && _state != _cityName) {
      parts.add(_state);
    }

    if (_country.isNotEmpty && parts.isEmpty) {
      parts.add(_country);
    } else if (_country.isNotEmpty) {
      // Add country only if it's not already the only entry
      if (parts.length <= 2) parts.add(_country);
    }

    return parts.isNotEmpty ? parts.join('، ') : 'غير معروف';
  }

  /// Manually set a city (from predefined list)
  Future<void> setManualLocation({
    required double lat,
    required double lng,
    required String city,
    String state = '',
    String country = '',
  }) async {
    _latitude = lat;
    _longitude = lng;
    _cityName = city;
    _state = state;
    _country = country;
    _village = '';
    _town = '';
    _useGps = false;

    // Also reverse geocode for better detail even for manual cities
    await _reverseGeocode(lat, lng);

    // Prefer the user-chosen city name over reverse geocode
    if (_cityName.isEmpty || city.isNotEmpty) {
      _cityName = city;
    }
    _displayName = _buildDisplayName();

    await _save();
    notifyListeners();
  }

  /// Pick a location by country/state/city names (from hierarchical picker).
  /// Geocodes the address via Nominatim, then persists.
  /// Returns true if coordinates were found and saved.
  Future<bool> setManualByNames({
    required String country,
    String state = '',
    required String city,
  }) async {
    try {
      // Build a forward geocode query from the hierarchical names
      final parts = [city, state, country].where((s) => s.isNotEmpty).toList();
      final query = parts.join('، ');
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&format=json&accept-language=ar'
        '&limit=1&addressdetails=1',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'AuraAdhanApp/1.0 (azan@mshmsidn.com)',
      });
      if (res.statusCode != 200) return false;
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) return false;

      final item = list[0];
      final lat = double.parse(item['lat'].toString());
      final lng = double.parse(item['lon'].toString());

      await setManualLocation(lat: lat, lng: lng, city: city, state: state, country: country);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Search cities by name via Nominatim forward geocoding
  Future<List<SearchResult>> searchCities(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&format=json&accept-language=ar'
        '&limit=15&addressdetails=1',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'AuraAdhanApp/1.0 (azan@mshmsidn.com)',
      });
      if (res.statusCode != 200) return [];

      final list = jsonDecode(res.body) as List;
      return list.map((item) {
        final addr = item['address'] as Map<String, dynamic>? ?? {};
        final name = (addr['city'] ??
                addr['town'] ??
                addr['village'] ??
                addr['state'] ??
                item['name'] ??
                '')
            .toString();
        return SearchResult(
          name: name,
          displayName: item['display_name']?.toString() ?? name,
          lat: double.parse(item['lat'].toString()),
          lng: double.parse(item['lon'].toString()),
          state: addr['state']?.toString(),
          country: addr['country']?.toString(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Mark initial setup as complete
  Future<void> markSetupDone() async {
    _setupDone = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keySetupDone, true);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_keyLat, _latitude);
    await p.setDouble(_keyLng, _longitude);
    await p.setString(_keyVillage, _village);
    await p.setString(_keyTown, _town);
    await p.setString(_keyCity, _cityName);
    await p.setString(_keyState, _state);
    await p.setString(_keyCountry, _country);
    await p.setString(_keyDisplay, _displayName);
    await p.setBool(_keyUseGps, _useGps);
  }
}

// ── Pre-defined cities list for manual selection ──
class CityData {
  final String name;
  final double lat;
  final double lng;

  const CityData(this.name, this.lat, this.lng);

  static const List<CityData> popular = [
    CityData('مكة المكرمة', 21.3891, 39.8579),
    CityData('المدينة المنورة', 24.5247, 39.5693),
    CityData('الرياض', 24.7136, 46.6753),
    CityData('جدة', 21.4858, 39.1925),
    CityData('الدمام', 26.4207, 50.0888),
    CityData('أبها', 18.2164, 42.5046),
    CityData('تبوك', 28.3835, 36.5662),
    CityData('بريدة', 26.3260, 43.9750),
    CityData('الطائف', 21.2703, 40.4155),
    CityData('حائل', 27.5219, 41.6907),
    CityData('جازان', 16.8892, 42.5511),
    CityData('نجران', 17.4934, 44.1277),
    CityData('الباحة', 20.0129, 41.4677),
    CityData('سكاكا', 29.9697, 40.2008),
    CityData('عرعر', 30.9836, 41.0397),
    CityData('القاهرة', 30.0444, 31.2357),
    CityData('الإسكندرية', 31.2001, 29.9187),
    CityData('دبي', 25.2048, 55.2708),
    CityData('أبو ظبي', 24.4539, 54.3773),
    CityData('الدوحة', 25.2854, 51.5310),
    CityData('الكويت', 29.3759, 47.9774),
    CityData('مسقط', 23.5880, 58.3829),
    CityData('المنامة', 26.2285, 50.5860),
    CityData('عمّان', 31.9454, 35.9284),
    CityData('إسطنبول', 41.0082, 28.9784),
    CityData('لندن', 51.5074, -0.1278),
    CityData('باريس', 48.8566, 2.3522),
    CityData('برلين', 52.5200, 13.4050),
    CityData('كوالالمبور', 3.1390, 101.6870),
    CityData('جاكرتا', -6.2088, 106.8456),
  ];
}
