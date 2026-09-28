import 'package:intl/intl.dart';

/// "40 000 FCFA" — plain space as thousands separator (safe in PDF fonts).
String formatMontant(int value) => '${formatNombre(value)} FCFA';

String formatNombre(int value) {
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return value < 0 ? '-$buf' : buf.toString();
}

final _dateFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
final _timeFmt = DateFormat('HH:mm');

String formatDate(DateTime d) => _dateFmt.format(d);
String formatDateTime(DateTime d) => _dateTimeFmt.format(d);
String formatTime(DateTime d) => _timeFmt.format(d);

/// Parses a montant typed by the user ("40 000", "40000") into whole FCFA.
int? parseMontant(String text) {
  final cleaned = text.replaceAll(RegExp(r'[\s  ]'), '');
  return int.tryParse(cleaned);
}

/// "4,2 Mo" / "850 Ko" for file sizes.
String formatTaille(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
  return '${(bytes / 1024).round()} Ko';
}
