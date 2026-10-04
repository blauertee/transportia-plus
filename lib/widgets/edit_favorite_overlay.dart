import 'package:flutter/widgets.dart';

import '../services/favorites_service.dart';
import '../utils/favorite_icons.dart';
import 'name_icon_dialog.dart';

/// Renames a favourite and changes its icon, or removes it.
class EditFavoriteOverlay extends StatelessWidget {
  final FavoritePlace favorite;
  final VoidCallback onSaved;

  /// Offered alongside the rename, since a place you no longer keep and a
  /// place you renamed are the same thought a moment apart.
  final VoidCallback? onDeleted;

  const EditFavoriteOverlay({
    super.key,
    required this.favorite,
    required this.onSaved,
    this.onDeleted,
  });

  /// Writes the alias rather than the name.
  ///
  /// The searched name stays underneath, so clearing the field restores it
  /// instead of leaving the place nameless — and a rider who calls a station
  /// "Home" has not forgotten what it is really called.
  Future<void> _save(String alias, String iconName) async {
    final updatedFavorite = favorite.copyWith(
      label: alias,
      clearLabel: alias.isEmpty || alias == favorite.name,
      iconName: iconName,
    );
    await FavoritesService.updateFavorite(updatedFavorite);
    onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return NameIconDialog(
      title: 'Edit Favourite',
      name: favorite.name,
      iconName: favorite.iconName,
      suggestions: favoriteIconSuggestions,
      pickerTitle: 'Favourite icon',
      onSaved: _save,
      deleteLabel: onDeleted == null ? null : 'Remove favourite',
      onDeleted: onDeleted,
    );
  }
}
