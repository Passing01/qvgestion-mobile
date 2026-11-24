import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qvgestion_mobile/core/theme/app_colors.dart';
import 'package:qvgestion_mobile/core/widgets/feedback/app_snackbar.dart';
import 'package:qvgestion_mobile/features/admin/presentation/providers/admin_providers.dart';
import 'package:qvgestion_mobile/features/places/data/models/category_model.dart';
import 'package:qvgestion_mobile/features/places/data/models/place_model.dart';
import 'package:qvgestion_mobile/features/places/presentation/providers/places_providers.dart';

/// Boîte de dialogue Admin pour modifier un lieu, le valider/rejeter et gérer ses images.
class AdminEditPlaceDialog extends ConsumerStatefulWidget {
  final PlaceModel place;

  const AdminEditPlaceDialog({super.key, required this.place});

  static Future<bool?> show(BuildContext context, PlaceModel place) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AdminEditPlaceDialog(place: place),
    );
  }

  @override
  ConsumerState<AdminEditPlaceDialog> createState() =>
      _AdminEditPlaceDialogState();
}

class _AdminEditPlaceDialogState extends ConsumerState<AdminEditPlaceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _villeCtrl;
  late final TextEditingController _quartierCtrl;
  late final TextEditingController _adresseCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _horairesCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _photoUrlCtrl;

  late int _categorieId;
  late bool _estValide;
  late bool _isAnchor;
  late int _importance;
  late List<String> _photos;

  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    final p = widget.place;
    _nameCtrl = TextEditingController(text: p.nom);
    _villeCtrl = TextEditingController(text: p.ville);
    _quartierCtrl = TextEditingController(text: p.quartier ?? '');
    _adresseCtrl = TextEditingController(text: p.adresse ?? '');
    _telCtrl = TextEditingController(text: p.telephone ?? '');
    _horairesCtrl = TextEditingController(text: p.horaires ?? '');
    _descCtrl = TextEditingController(text: p.description ?? '');
    _photoUrlCtrl = TextEditingController();
    _categorieId = p.categorieId;
    _estValide = p.estValide;
    _isAnchor = p.isAnchor;
    _importance = p.importance.clamp(1, 5);
    _photos = List<String>.from(p.photos);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _villeCtrl.dispose();
    _quartierCtrl.dispose();
    _adresseCtrl.dispose();
    _telCtrl.dispose();
    _horairesCtrl.dispose();
    _descCtrl.dispose();
    _photoUrlCtrl.dispose();
    super.dispose();
  }

  void _invalidateAllPlaces() {
    ref.invalidate(pendingPlacesProvider);
    ref.invalidate(adminPlacesProvider);
    ref.invalidate(adminDashboardStatsProvider);
    ref.invalidate(neighborhoodsGeoJsonProvider);
    ref.invalidate(featuredPlacesWithPhotosProvider);
    ref.invalidate(placeDetailProvider(widget.place.id.toString()));
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);
      final bytes = await picked.readAsBytes();
      final updated = await ref.read(adminRepositoryProvider).uploadPlacePhoto(
            placeId: widget.place.id,
            bytes: bytes,
            filename: picked.name.isNotEmpty ? picked.name : 'photo.jpg',
          );
      if (!mounted) return;
      setState(() {
        _photos = List<String>.from(updated.photos);
        _isUploadingPhoto = false;
      });
      _invalidateAllPlaces();
      AppSnackbar.showSuccess(context, message: 'Image ajoutée au lieu !');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      AppSnackbar.showError(
        context,
        title: 'Erreur image',
        message: 'Téléversement impossible : $e',
      );
    }
  }

  void _addPhotoUrl() {
    final url = _photoUrlCtrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      AppSnackbar.showWarning(
        context,
        message: 'Veuillez saisir une URL commençant par http:// ou https://',
      );
      return;
    }
    setState(() {
      if (!_photos.contains(url)) _photos.add(url);
      _photoUrlCtrl.clear();
    });
  }

  Future<void> _removePhoto(String url) async {
    setState(() => _photos.remove(url));
    try {
      await ref.read(adminRepositoryProvider).deletePlacePhoto(
            placeId: widget.place.id,
            photoUrl: url,
          );
      _invalidateAllPlaces();
    } catch (_) {
      // S'il s'agissait d'une URL ajoutée localement avant sauvegarde, déjà retirée
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(adminRepositoryProvider).updatePlace(widget.place.id, {
        'nom': _nameCtrl.text.trim(),
        'categorie_id': _categorieId,
        'ville': _villeCtrl.text.trim().isEmpty
            ? 'Burkina Faso'
            : _villeCtrl.text.trim(),
        'quartier': _quartierCtrl.text.trim().isEmpty
            ? null
            : _quartierCtrl.text.trim(),
        'adresse': _adresseCtrl.text.trim().isEmpty
            ? null
            : _adresseCtrl.text.trim(),
        'telephone': _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'horaires': _horairesCtrl.text.trim().isEmpty
            ? null
            : _horairesCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'est_valide': _estValide,
        'status': _estValide ? 'validated' : 'pending',
        'is_anchor': _isAnchor,
        'importance': _importance,
        'photos': _photos,
      });
      _invalidateAllPlaces();
      if (!mounted) return;
      AppSnackbar.showSuccess(
        context,
        message: 'Lieu "${_nameCtrl.text.trim()}" mis à jour !',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnackbar.showError(
        context,
        title: 'Erreur sauvegarde',
        message: 'Impossible de modifier ce lieu : $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).value ?? const <CategoryModel>[];
    final hasCurrentCat = cats.any((c) => c.id == _categorieId);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_location_alt_rounded, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modifier : ${widget.place.nom}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom du lieu *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Nom requis' : null,
                ),
                const SizedBox(height: 10),
                if (cats.isNotEmpty)
                  DropdownButtonFormField<int>(
                    initialValue: hasCurrentCat ? _categorieId : cats.first.id,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie',
                      border: OutlineInputBorder(),
                    ),
                    items: cats
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: c.id,
                            child: Text(c.nom),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _categorieId = v);
                    },
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _villeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ville',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _quartierCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Quartier',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _adresseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adresse / Rue',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _telCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Téléphone',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _horairesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Horaires',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Validé et visible sur la carte',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  value: _estValide,
                  onChanged: (v) => setState(() => _estValide = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Utilisable comme repère vocal (Guidage)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  value: _isAnchor,
                  onChanged: (v) => setState(() => _isAnchor = v),
                ),
                const Divider(height: 20),
                const Text(
                  'Photos du lieu',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_photos.isNotEmpty)
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) {
                        final url = _photos[idx];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                url,
                                width: 108,
                                height: 86,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 108,
                                  height: 86,
                                  color: const Color(0xFFF1F5F9),
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => _removePhoto(url),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Color(0xCC0F172A),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                  icon: _isUploadingPhoto
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_rounded, size: 18),
                  label: Text(
                    _isUploadingPhoto
                        ? 'Envoi de l\'image...'
                        : 'Téléverser une photo (Galerie / PC)',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _photoUrlCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Ou coller une URL d\'image',
                          hintText: 'https://...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addPhotoUrl,
                      child: const Text('+ URL'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded, size: 18),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

