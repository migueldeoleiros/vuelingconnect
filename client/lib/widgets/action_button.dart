import 'package:flutter/material.dart';

/// A custom action button with icon and label for the Bluetooth interface.
///
/// Displays an icon above text label with visual styles for active/inactive states.
class ActionButton extends StatelessWidget {
  /// The context for theming
  final BuildContext context;

  /// Icon to display in the button
  final IconData icon;

  /// Text label displayed below the icon
  final String label;

  /// Whether the button is in active state (changes appearance)
  final bool isActive;

  /// Function called when the button is tapped
  final VoidCallback onPressed;

  /// Optional color to highlight the button (used for special buttons like alerts)
  final Color? highlightColor;

  /// Creates an action button.
  const ActionButton({
    super.key,
    required this.context,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final surfaceColor = theme.colorScheme.surface;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 110,
        constraints: const BoxConstraints(minHeight: 90, maxHeight: 110),
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        decoration: BoxDecoration(
          color:
              isActive
                  ? primaryColor.withOpacity(0.2)
                  : (highlightColor != null
                      ? highlightColor!.withOpacity(0.1)
                      : surfaceColor),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isActive
                    ? primaryColor
                    : (highlightColor ?? theme.colorScheme.outline),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color:
                  isActive
                      ? primaryColor
                      : (highlightColor ?? theme.colorScheme.onSurface),
              size: 28,
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                style: theme.textTheme.labelLarge?.copyWith(
                  color:
                      isActive
                          ? primaryColor
                          : (highlightColor ?? theme.colorScheme.onSurface),
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
