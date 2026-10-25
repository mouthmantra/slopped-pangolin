import 'package:pangolin/services/tray/item.dart';
import 'package:pangolin/widgets/tray/tray_icon.dart';
import 'package:pangolin/widgets/tray/tray_item_area.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// A tray item in quick settings: its icon and title.
class QsTrayMenuItem extends StatelessWidget {
  final TrayItem item;

  const QsTrayMenuItem({required this.item, super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).surfaceColor,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      child: TrayItemArea(
        item: item,
        inPopup: true,
        builder: (context, menuOpen, actions) => InkWell(
          onTapUp: (details) => actions.primary(details.globalPosition),
          onSecondaryTapUp: (details) =>
              actions.secondary(details.globalPosition),
          child: ListenableBuilder(
            listenable: item,
            builder: (context, _) {
              final String title = item.title.isNotEmpty ? item.title : item.label;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrayIconImage.item(item, size: 16),
                    if (title.isNotEmpty) const SizedBox(width: 8),
                    if (title.isNotEmpty)
                      Text(title, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
