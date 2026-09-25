import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:csc_picker_plus/csc_picker_plus.dart';
import '../services/location_service.dart';

/// Reusable bottom-sheet that wraps the hierarchical CSC picker.
///
/// Usage:
/// ```dart
/// final picked = await showModalBottomSheet<bool>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => CityPickerSheet(
///     loc: locationService,
///     isNight: isNight,
///   ),
/// );
/// if (picked == true) { /* location updated */ }
/// ```
class CityPickerSheet extends StatefulWidget {
  final LocationService loc;
  final bool isNight;

  const CityPickerSheet({
    super.key,
    required this.loc,
    required this.isNight,
  });

  @override
  State<CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<CityPickerSheet> {
  String _country = '';
  String _state = '';
  String _city = '';
  bool _saving = false;

  bool get n => widget.isNight;
  Color get bg => const Color(0xFF0D1330);
  Color get gold => const Color(0xFFD4A853);

  bool get _canConfirm => _country.isNotEmpty && _city.isNotEmpty;

  Future<void> _confirm() async {
    if (!_canConfirm || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.loc.setManualByNames(
      country: _country,
      state: _state,
      city: _city,
    );
    setState(() => _saving = false);
    if (mounted) {
      if (ok) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر تحديد الإحداثيات، جرّب مدينة أخرى'),
            backgroundColor: gold.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'اختيار الموقع يدوياً',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'اختر الدولة ثم المنطقة ثم المدينة',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // CSC Picker
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CSCPickerPlus(
              countryStateLanguage: CountryStateLanguage.arabic,
              layout: Layout.vertical,
              flagState: CountryFlag.DISABLE,
              dropdownDialogRadius: 18,
              searchBarRadius: 18,
              dropdownDecoration: BoxDecoration(
                color: const Color(0xFF141C3A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              disabledDropdownDecoration: BoxDecoration(
                color: const Color(0xFF141C3A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              selectedItemStyle: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
              ),
              dropdownItemStyle: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              dropdownHeadingStyle: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: gold,
              ),
              onCountryChanged: (value) {
                setState(() => _country = value);
              },
              onStateChanged: (value) {
                setState(() => _state = value ?? '');
              },
              onCityChanged: (value) {
                setState(() => _city = value ?? '');
              },
            ),
          ),
          const SizedBox(height: 24),
          // Confirm button
          Padding(
            padding: EdgeInsets.fromLTRB(
              24, 0, 24, MediaQuery.of(context).viewPadding.bottom + 16,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _canConfirm && !_saving ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canConfirm ? gold : Colors.white.withValues(alpha: 0.08),
                  foregroundColor: _canConfirm ? Colors.black : Colors.white38,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on_rounded, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            _city.isNotEmpty
                                ? 'تأكيد: $_city'
                                : 'اختر الدولة والمدينة أولاً',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
