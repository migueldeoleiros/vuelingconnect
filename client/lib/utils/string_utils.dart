// String utility functions

String capitalizeFirstLetter(String? text) {
  if (text == null || text.isEmpty) return text ?? '';
  return text[0].toUpperCase() + text.substring(1);
}
