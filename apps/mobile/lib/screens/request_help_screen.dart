import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/api.dart';
import '../core/request_submission.dart';
import '../core/volunteer_auth_service.dart';
import '../widgets/form_assistant.dart';
import 'explore_screen.dart';
import 'location_picker_screen.dart';
import 'my_requests_screen.dart';
import 'volunteer_login_screen.dart';

class RequestHelpScreen extends StatefulWidget {
  const RequestHelpScreen({super.key});

  @override
  State<RequestHelpScreen> createState() => _RequestHelpScreenState();
}

class _RequestHelpScreenState extends State<RequestHelpScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _quantityControllers = [
    TextEditingController(),
  ];
  final _affectedPeopleController = TextEditingController();
  final _contactController = TextEditingController();
  final _requesterNameController = TextEditingController();
  final List<String?> _resourceCategories = [null];
  final List<bool> _categoryErrors = [false];
  LatLng? _location;
  LatLng? _currentLocation;
  bool _locationAllowed = false;
  bool _locationServiceEnabled = true;
  bool _locationError = false;
  bool _isSubmitting = false;

  static const _categoryOptions = [
    'Food',
    'Drinking Water',
    'Medicine',
    'Clothing',
    'Temporary Shelter',
  ];

  @override
  void initState() {
    super.initState();
    _prefillVolunteer();
    _requestLiveLocation();
  }

  Future<void> _prefillVolunteer() async {
    if (!VolunteerAuthService.hasSession) return;
    try {
      final account = await VolunteerAuthService.currentVolunteer();
      if (!mounted) return;
      setState(() {
        _requesterNameController.text = account.name;
        _contactController.text = account.phone;
      });
    } catch (_) {
      // Public request forms remain available if a saved session has expired.
      await VolunteerAuthService.signOut();
      await clearSavedRequests();
      if (mounted) setState(() {});
    }
  }

  Future<void> _requestLiveLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _locationServiceEnabled = false;
        _locationAllowed = false;
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final allowed = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    if (!mounted) return;
    setState(() {
      _locationServiceEnabled = true;
      _locationAllowed = allowed;
    });
    if (!allowed) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // The live map layer can still receive a position when a fix is ready.
    }
  }

  Future<void> _chooseLocationOnMap() async {
    final selectedLocation = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        builder: (_) => LocationPickerScreen(
          initialLocation: _location ?? _currentLocation,
        ),
      ),
    );
    if (selectedLocation == null || !mounted) return;
    setState(() {
      _location = selectedLocation;
      _locationError = false;
    });
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers) {
      controller.dispose();
    }
    _affectedPeopleController.dispose();
    _contactController.dispose();
    _requesterNameController.dispose();
    super.dispose();
  }

  void _addResourceNeed() {
    setState(() {
      _resourceCategories.add(null);
      _categoryErrors.add(false);
      _quantityControllers.add(TextEditingController());
    });
  }

  void _removeResourceNeed(int index) {
    if (_resourceCategories.length <= 1) return;
    setState(() {
      _resourceCategories.removeAt(index);
      _categoryErrors.removeAt(index);
      _quantityControllers.removeAt(index).dispose();
    });
  }

  Future<void> _chooseValue({
    required String title,
    required List<String> values,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: appPaper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: const TextStyle(
                  color: appNavy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...values.map(
              (value) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(appText(value)),
                trailing: value == selectedValue
                    ? const Icon(Icons.check_rounded, color: appTeal)
                    : null,
                onTap: () => Navigator.of(context).pop(value),
              ),
            ),
          ],
        ),
      ),
    );
    if (value != null && mounted) onSelected(value);
  }

  void _applyFormSuggestions(Map<String, dynamic> values) {
    setState(() {
      final name = values['requester_name']?.toString() ?? '';
      final phone = values['requester_phone']?.toString() ?? '';
      if (name.isNotEmpty) _requesterNameController.text = name;
      if (phone.isNotEmpty) _contactController.text = phone;
      if (values['affected_people'] != null) {
        _affectedPeopleController.text = '${values['affected_people']}';
      }
      final items = values['items'];
      if (items is List && items.isNotEmpty) {
        for (final controller in _quantityControllers) {
          controller.dispose();
        }
        _quantityControllers
          ..clear()
          ..addAll(items.map((_) => TextEditingController()));
        _resourceCategories
          ..clear()
          ..addAll(items.map((item) => item['category'] as String?));
        _categoryErrors
          ..clear()
          ..addAll(List<bool>.filled(items.length, false));
        for (var index = 0; index < items.length; index++) {
          _quantityControllers[index].text = '${items[index]['quantity']}';
        }
      }
    });
  }

  Future<void> _submitRequest() async {
    final fieldsValid = _formKey.currentState!.validate();
    final categoriesValid = _resourceCategories.every((value) => value != null);
    final locationValid = _location != null;
    setState(() {
      for (var i = 0; i < _resourceCategories.length; i++) {
        _categoryErrors[i] = _resourceCategories[i] == null;
      }
      _locationError = !locationValid;
    });
    if (!fieldsValid || !categoriesValid || !locationValid) return;
    setState(() => _isSubmitting = true);
    final items = List.generate(_resourceCategories.length, (index) {
      return {
        'item_type': resourceItemType(_resourceCategories[index]!)!,
        'qty': int.parse(_quantityControllers[index].text.trim()),
        'unit': 'kit',
      };
    });
    final payload = <String, dynamic>{
      'kind': 'resource_request',
      'requester_name': _requesterNameController.text.trim(),
      'requester_phone': normalizeNepalPhone(_contactController.text)!,
      'lat': _location!.latitude,
      'lng': _location!.longitude,
      'urgency': 'normal',
      'notes':
          'Estimated affected people: ${_affectedPeopleController.text.trim()}',
      'items': items,
    };
    final result = await Api.submitRequest(payload);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (!result.ok || result.data == null) {
      showSubmissionError(context, result);
      return;
    }
    await saveSubmittedRequest(response: result.data!, payload: payload);
    if (!mounted) return;
    await showSubmissionSuccessDialog(context, result.data!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
        valueListenable: AppLanguageController.language,
        builder: (context, language, child) => Scaffold(
        backgroundColor: appPaper,
        body: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          appText('Request Help'),
                          style: const TextStyle(
                            color: appNavy,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const AppLanguageToggle(),
                      const Icon(
                        Icons.verified_user_outlined,
                        color: appTeal,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    appText('Tell us what you need.'),
                    style: TextStyle(
                      color: appNavy,
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FormAssistantButton(
                    formType: 'resource_request',
                    prompt: appText('Describe what you need in English, नेपाली, or both.'),
                    onApply: _applyFormSuggestions,
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel('Contact information'),
                  const SizedBox(height: 8),
                  _textField(
                    controller: _contactController,
                    hint: 'Phone number for responders to reach you',
                    keyboardType: TextInputType.phone,
                    validator: validateNepalPhone,
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('Requester name'),
                  const SizedBox(height: 8),
                  _textField(
                    controller: _requesterNameController,
                    hint: 'Your full name',
                    validator: validateRequesterName,
                  ),
                  const SizedBox(height: 30),
                  ...List.generate(
                    _resourceCategories.length,
                    (index) => Padding(
                      padding: EdgeInsets.only(
                        bottom:
                            index == _resourceCategories.length - 1 ? 0 : 18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _fieldLabel('Resource category')),
                              if (_resourceCategories.length > 1)
                                IconButton(
                                  onPressed: () => _removeResourceNeed(index),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Remove resource',
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: appMuted,
                                    size: 19,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _choiceField(
                            value:
                                _resourceCategories[index] ?? 'Select category',
                            error: _categoryErrors[index],
                            onTap: () => _chooseValue(
                              title: 'Resource category',
                              values: _categoryOptions,
                              selectedValue: _resourceCategories[index] ?? '',
                              onSelected: (value) => setState(() {
                                _resourceCategories[index] = value;
                                _categoryErrors[index] = false;
                              }),
                            ),
                          ),
                          if (_categoryErrors[index]) ...[
                            const SizedBox(height: 6),
                            Text(
                              appText('Choose a resource category.'),
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _fieldLabel('Required quantity'),
                          const SizedBox(height: 8),
                          _textField(
                            controller: _quantityControllers[index],
                            hint: 'Enter a number',
                            keyboardType: TextInputType.number,
                            suffixText: 'kit',
                            validator: (value) {
                              final quantity =
                                  int.tryParse(value?.trim() ?? '');
                              return quantity == null || quantity < 1
                                  ? 'Enter a valid quantity'
                                  : null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addResourceNeed,
                      style: TextButton.styleFrom(
                        foregroundColor: appTeal,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(
                        appText('Add another resource'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    appText('Food · Drinking Water · Medicine\nClothing · Temporary Shelter'),
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    appText('Where is help needed?'),
                    style: const TextStyle(
                      color: appNavy,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  LiveLocationMapPreview(
                    locationAllowed: _locationAllowed,
                    locationServiceEnabled: _locationServiceEnabled,
                    currentLocation: _currentLocation,
                    selectedLocation: _location,
                    onTap: _chooseLocationOnMap,
                  ),
                  const SizedBox(height: 18),
                  _choiceField(
                    value: _location == null
                        ? 'Choose location on map'
                        : '${_location!.latitude.toStringAsFixed(5)}, ${_location!.longitude.toStringAsFixed(5)}',
                    error: _locationError,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: appTeal,
                      size: 20,
                    ),
                    onTap: _chooseLocationOnMap,
                  ),
                  if (_locationError) ...[
                    const SizedBox(height: 6),
                    Text(
                      appText('Choose a location for the request.'),
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _fieldLabel('Estimated number of affected people'),
                  const SizedBox(height: 8),
                  _textField(
                    controller: _affectedPeopleController,
                    hint: 'e.g. 8 people',
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final count = int.tryParse(value?.trim() ?? '');
                      if (count == null || count < 1) {
                        return 'Enter a valid number of affected people';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submitRequest,
                      child: Text(appText(
                          _isSubmitting ? 'Submitting…' : 'Submit request')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: _requestNavigationBar(context),
      ));

  Widget _fieldLabel(String text) => Text(
        appText(text),
        style: const TextStyle(
          color: Color(0xFF263746),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );

  Widget _choiceField({
    required String value,
    required VoidCallback onTap,
    Widget? leading,
    bool error = false,
  }) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: error ? Colors.redAccent : const Color(0xFFE0E6EC),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    appText(value),
                    style: const TextStyle(color: appMuted, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    String? suffixText,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: appNavy, fontSize: 14),
        decoration: InputDecoration(
          hintText: appText(hint),
          hintStyle: const TextStyle(color: appMuted, fontSize: 13),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          suffixText: suffixText,
          errorStyle: const TextStyle(fontSize: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE0E6EC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE0E6EC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: appTeal, width: 1.4),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
        ),
      );
}

Widget _requestNavigationBar(BuildContext context) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E6EC))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              _RequestNavigationItem(
                icon: Icons.home_outlined,
                label: appText('Home'),
                selected: false,
                onTap: () => Navigator.of(context).popUntil(
                  (route) => route.isFirst,
                ),
              ),
              _RequestNavigationItem(
                icon: Icons.map_outlined,
                label: appText('Explore'),
                selected: false,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExploreScreen(),
                  ),
                ),
              ),
              _RequestNavigationItem(
                icon: Icons.inventory_2_outlined,
                label: appText('Requests'),
                selected: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MyRequestsScreen(),
                  ),
                ),
              ),
              _RequestNavigationItem(
                icon: Icons.person_outline_rounded,
                label: appText(VolunteerAuthService.hasSession ? 'Profile' : 'Join'),
                selected: false,
                onTap: () => openVolunteerLogin(context),
              ),
            ],
          ),
        ),
      ),
    );

class _RequestNavigationItem extends StatelessWidget {
  const _RequestNavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 54,
                height: 27,
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFE7F0F4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 21, color: appNavy),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: appNavy,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
}
