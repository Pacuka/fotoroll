// Dialogs for editing several selected photos at once (web: AssetSelectionChangeDateModal
// and the description modal). Location and tags reuse the info panel's dialogs.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../i18n.dart';

/// A new date for every photo ([iso], with the computer's UTC offset at that date),
/// or a shift of each photo's own date by [minutes].
typedef DateChange = ({String? iso, int? minutes});

Future<DateChange?> showChangeDateDialog(BuildContext context, {DateTime? initial}) =>
    showDialog<DateChange>(context: context, builder: (_) => _ChangeDateDialog(initial: initial ?? DateTime.now()));

/// "2026-10-09T14:30:00.000+02:00" for [local] in this computer's timezone.
String isoWithOffset(DateTime local) {
  final offset = local.timeZoneOffset;
  String two(int v) => v.abs().toString().padLeft(2, '0');
  final sign = offset.isNegative ? '-' : '+';
  return '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(local)}.000'
      '$sign${two(offset.inHours)}:${two(offset.inMinutes.remainder(60))}';
}

class _ChangeDateDialog extends StatefulWidget {
  final DateTime initial;
  const _ChangeDateDialog({required this.initial});

  @override
  State<_ChangeDateDialog> createState() => _ChangeDateDialogState();
}

class _ChangeDateDialogState extends State<_ChangeDateDialog> {
  bool _relative = false;
  late DateTime _date = widget.initial;
  final _days = TextEditingController(text: '0');
  final _hours = TextEditingController(text: '0');
  final _minutes = TextEditingController(text: '0');

  @override
  void dispose() {
    _days.dispose();
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  /// The offset in minutes, or null while a field isn't a whole number.
  int? get _offset {
    final d = int.tryParse(_days.text.trim()), h = int.tryParse(_hours.text.trim());
    final m = int.tryParse(_minutes.text.trim());
    return d == null || h == null || m == null ? null : d * 24 * 60 + h * 60 + m;
  }

  Future<void> _pick() async {
    final day = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(1800), lastDate: DateTime(2200));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (time == null) return;
    setState(() => _date = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Widget _number(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final offset = _offset;
    final ok = _relative ? offset != null && offset != 0 : true;
    return AlertDialog(
      title: Text(t('edit_date_and_time')),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('edit_date_and_time_by_offset')),
            value: _relative,
            onChanged: (v) => setState(() => _relative = v),
          ),
          const SizedBox(height: 8),
          if (_relative) ...[
            Text(t('offset'), style: Theme.of(context).textTheme.labelLarge),
            Row(children: [
              _number(_days, t('days')),
              const SizedBox(width: 12),
              _number(_hours, t('hours')),
              const SizedBox(width: 12),
              _number(_minutes, t('minutes')),
            ]),
            const SizedBox(height: 8),
            Text(t('linux_date_offset_hint'), style: Theme.of(context).textTheme.bodySmall),
          ] else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_calendar_outlined),
              title: Text(t('date_and_time')),
              subtitle: Text(DateFormat.yMMMd(i18n.dateLocale).add_Hm().format(_date)),
              onTap: _pick,
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          onPressed: !ok
              ? null
              : () => Navigator.pop<DateChange>(
                  context, _relative ? (iso: null, minutes: offset) : (iso: isoWithOffset(_date), minutes: null)),
          child: Text(t('confirm')),
        ),
      ],
    );
  }
}

/// One description for every selected photo.
Future<String?> showChangeDescriptionDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _DescriptionDialog());

class _DescriptionDialog extends StatefulWidget {
  const _DescriptionDialog();

  @override
  State<_DescriptionDialog> createState() => _DescriptionDialogState();
}

class _DescriptionDialogState extends State<_DescriptionDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(t('edit_description')),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: _text,
            autofocus: true,
            maxLines: 4,
            minLines: 1,
            decoration: InputDecoration(labelText: t('description'), hintText: t('add_a_description')),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: Text(t('confirm'))),
        ],
      );
}
