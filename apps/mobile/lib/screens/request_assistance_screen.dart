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

class RequestAssistanceScreen extends StatefulWidget {
  const RequestAssistanceScreen({super.key});

  @override
  State<RequestAssistanceScreen> createState() =>
      _RequestAssistanceScreenState();
}

class _RequestAssistanceScreenState extends State<RequestAssistanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contactController = TextEditingController();
  final _requesterNameController = TextEditingController();
  final _affectedPeopleController = TextEditingController();
  final List<TextEditingController> _numberControllers = [
    TextEditingController(),
  ];
  final List<String?> _assistanceTypes = [null];
  final List<bool> _typeErrors = [false];
  LatLng? _location;
  LatLng? _currentLocation;
  bool _locationAllowed = false;
  bool _locationServiceEnabled = true;
  bool _locationError = false;
  bool _isSubmitting = false;

  static const _assistanceOptions = [
    'Health Worker',
    'Transport Manpower',
    'Human Manpower',
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
      // The live map layer can receive a fix when one becomes available.
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
    _contactController.dispose();
    _requesterNameController.dispose();
    _affectedPeopleController.dispose();
    for (final controller in _numberControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addAssistanceType() => setState(() {
        _assistanceTypes.add(null);
        _typeErrors.add(false);
        _numberControllers.add(TextEditingController());
      });

  void _removeAssistanceType(int index) {
    if (_assistanceTypes.length <= 1) return;
    setState(() {
      _assistanceTypes.removeAt(index);
      _typeErrors.removeAt(index);
      _numberControllers.removeAt(index).dispose();
    });
  }

  Future<void> _chooseValue({
    required String title,
    required List<String> values,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) async {
    final selected = await showModalBottomSheet<String>(
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
    if (selected != null && mounted) onSelected(selected);
  }

  String? _validatePositiveInteger(String? value, String fieldName) {
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null || number < 1) return 'Enter a valid $fieldName';
    return null;
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
      if (values['assistance_type'] is String) {
        _assistanceTypes[0] = values['assistance_type'] as String;
      }
      if (values['volunteers_needed'] != null) {
        _numberControllers[0].text = '${values['volunteers_needed']}';
      }
    });
  }

  Future<void> _submitRequest() async {
    final fieldsValid = _formKey.currentState!.validate();
    final typesValid = _assistanceTypes.every((type) => type != null);
    final locationValid = _location != null;
    setState(() {
      for (var i = 0; i < _assistanceTypes.length; i++) {
        _typeErrors[i] = _assistanceTypes[i] == null;
      }
      _locationError = !locationValid;
    });
    if (!fieldsValid || !typesValid || !locationValid) return;
    if (_assistanceTypes.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The current API supports one assistance type per request. Select one type to continue.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final payload = <String, dynamic>{
      'kind': assistanceRequestKind(_assistanceTypes.single!)!,
      'requester_name': _requesterNameController.text.trim(),
      'requester_phone': normalizeNepalPhone(_contactController.text)!,
      'lat': _location!.latitude,
      'lng': _location!.longitude,
      'urgency': 'normal',
      'volunteers_needed': int.parse(_numberControllers.single.text.trim()),
      'notes':
          'Estimated affected people: ${_affectedPeopleController.text.trim()}',
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
                          appText('Request assistance'),
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
                  const SizedBox(height: 24),
                  Text(
                    appText('What kind of human\nassistance do you need?'),
                    style: TextStyle(
                      color: appNavy,
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FormAssistantButton(
                    formType: 'health',
                    prompt: appText('Describe the assistance needed in English, नेपाली, or both.'),
                    onApply: _applyFormSuggestions,
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel('Contact number'),
                  const SizedBox(height: 8),
                  _textField(
                    controller: _contactController,
                    hint: '+977 9841 234 567',
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
                  const SizedBox(height: 26),
                  ...List.generate(
                    _assistanceTypes.length,
                    (index) => Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _assistanceTypes.length - 1 ? 0 : 18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _fieldLabel('Human Assistance type'),
                              ),
                              if (_assistanceTypes.length > 1)
                                IconButton(
                                  onPressed: () => _removeAssistanceType(index),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Remove assistance type',
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
                            value: _assistanceTypes[index] ?? 'Select a type',
                            error: _typeErrors[index],
                            onTap: () => _chooseValue(
                              title: 'Human Assistance type',
                              values: _assistanceOptions,
                              selectedValue: _assistanceTypes[index] ?? '',
                              onSelected: (value) => setState(() {
                                _assistanceTypes[index] = value;
                                _typeErrors[index] = false;
                              }),
                            ),
                          ),
                          if (_typeErrors[index]) ...[
                            const SizedBox(height: 6),
                            Text(
                              appText('Choose an assistance type.'),
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _fieldLabel('Required Number'),
                          const SizedBox(height: 8),
                          _textField(
                            controller: _numberControllers[index],
                            hint: 'e.g. 8',
                            keyboardType: TextInputType.number,
                            validator: (value) =>
                                _validatePositiveInteger(value, 'number'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addAssistanceType,
                      style: TextButton.styleFrom(
                        foregroundColor: appTeal,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(
                        appText('Add another assistance type'),
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
                    validator: (value) =>
                        _validatePositiveInteger(value, 'number of people'),
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
        bottomNavigationBar: _assistanceNavigationBar(context),
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

Widget _assistanceNavigationBar(BuildContext context) => Container(
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
              _AssistanceNavigationItem(
                icon: Icons.home_outlined,
                label: appText('Home'),
                selected: false,
                onTap: () => Navigator.of(context).popUntil(
                  (route) => route.isFirst,
                ),
              ),
              _AssistanceNavigationItem(
                icon: Icons.map_outlined,
                label: appText('Explore'),
                selected: false,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExploreScreen(),
                  ),
                ),
              ),
              _AssistanceNavigationItem(
                icon: Icons.inventory_2_outlined,
                label: appText('Requests'),
                selected: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MyRequestsScreen(),
                  ),
                ),
              ),
              _AssistanceNavigationItem(
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

class _AssistanceNavigationItem extends StatelessWidget {
  const _AssistanceNavigationItem({
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
