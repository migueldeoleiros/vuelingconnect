// Date utility functions

String formatDateTime(String? isoString) {
  if (isoString == null) return 'Unknown';

  try {
    final dateTime = DateTime.parse(isoString);
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  } catch (e) {
    return isoString;
  }
}
