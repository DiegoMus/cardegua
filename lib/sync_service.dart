import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Asegúrate de que las importaciones a tus modelos sean correctas
import 'productores_page.dart';
import 'parcelas_page.dart';
import 'visita_parcela.dart';

class SyncService {
  // ======================================================
  // FUNCIÓN PÚBLICA #1: Descargar todo desde el servidor
  // ======================================================
  static Future<void> syncDownAllDataFromServer() async {
    debugPrint(
      '[SyncService] Iniciando descarga completa de datos del servidor...',
    );
    final supabase = Supabase.instance.client;

    try {
      // 1. Descargar Productores
      final productoresData = await supabase.from('productores').select();
      await _syncDownEntity<Productor>(
        remoteData: List<Map<String, dynamic>>.from(productoresData),
        box: await _openBox('productores', ProductorAdapter()),
        fromJson: (json) => Productor.fromJson(json),
      );

      // 2. Descargar Parcelas
      final parcelasData = await supabase.from('parcelas').select();
      await _syncDownEntity<Parcela>(
        remoteData: List<Map<String, dynamic>>.from(parcelasData),
        box: await _openBox('parcelas', ParcelaAdapter()),
        fromJson: (json) => Parcela.fromJson(json),
      );

      // 3. Descargar Visitas
      final visitasData = await supabase.from('visitas_monitoreo').select();
      await _syncDownEntity<VisitaMonitoreo>(
        remoteData: List<Map<String, dynamic>>.from(visitasData),
        box: await _openBox('visitas_monitoreo', VisitaMonitoreoAdapter()),
        fromJson: (json) => VisitaMonitoreo.fromJson(json),
      );

      debugPrint(
        '[SyncService] Descarga completa de datos finalizada con éxito.',
      );
    } catch (e) {
      debugPrint(
        '[SyncService] ¡¡¡ERROR CRÍTICO durante la descarga de datos!!!: $e',
      );
      throw Exception('No se pudieron sincronizar los datos iniciales.');
    }
  }

  // ==============================================================
  // FUNCIÓN PÚBLICA #2: Enviar cambios pendientes hacia el servidor
  // ==============================================================
  static Future<void> syncAllPendingData() async {
    final productorBox = await _openBox('productores', ProductorAdapter());
    final parcelaBox = await _openBox('parcelas', ParcelaAdapter());
    final visitaBox = await _openBox(
      'visitas_monitoreo',
      VisitaMonitoreoAdapter(),
    );

    // Sincroniza Productores (C-U-D)
    await _syncEntity<Productor>(
      box: productorBox,
      supabaseTable: 'productores',
      toMap: (p) => p.toMap(),
      onSuccess: (p, remoteData) => p.serverId = remoteData['id_productor'],
    );

    // Sincroniza Parcelas (C-U-D)
    await _syncEntity<Parcela>(
      box: parcelaBox,
      supabaseTable: 'parcelas',
      preSyncAction: (parcela) {
        try {
          final owner = productorBox.values.firstWhere(
            (p) => p.uuid == parcela.productorUuid,
          );
          if (owner.status != 'synced' || owner.serverId == null) {
            debugPrint(
              '[SyncService] OMITIENDO parcela "${parcela.nombre}" porque su productor no está sincronizado.',
            );
            return false;
          }
          parcela.productorId = owner.serverId;
          return true;
        } catch (_) {
          return false;
        }
      },
      toMap: (p) => p.toMap(),
      onSuccess: (p, remoteData) => p.serverId = remoteData['id_parcela'],
    );

    // Sincroniza Visitas (C-U-D)
    await _syncEntity<VisitaMonitoreo>(
      box: visitaBox,
      supabaseTable: 'visitas_monitoreo',
      preSyncAction: (visita) {
        try {
          final owner = parcelaBox.values.firstWhere(
            (p) => p.uuid == visita.parcelaUuid,
          );
          if (owner.status != 'synced' || owner.serverId == null) {
            debugPrint(
              '[SyncService] OMITIENDO visita (uuid: ${visita.uuid}) porque su parcela no está sincronizada.',
            );
            return false;
          }
          visita.parcelaId = owner.serverId;
          return true;
        } catch (_) {
          return false;
        }
      },
      toMap: (v) => v
          .toMap(), // Necesitarás añadir un .toMap() a tu clase VisitaMonitoreo
      onSuccess: (v, remoteData) => v.serverId = remoteData['id_visita'],
    );
  }

  // =====================================
  // FUNCIONES DE AYUDA PRIVADAS (HELPERS)
  // =====================================

  static Future<Box<T>> _openBox<T>(String name, TypeAdapter<T> adapter) async {
    try {
      if (!Hive.isAdapterRegistered(adapter.typeId))
        Hive.registerAdapter(adapter);
    } catch (_) {}
    if (!Hive.isBoxOpen(name)) return await Hive.openBox<T>(name);
    return Hive.box<T>(name);
  }

  static Future<void> _syncDownEntity<T extends HiveObject>({
    required List<Map<String, dynamic>> remoteData,
    required Box<T> box,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    for (final json in remoteData) {
      final uuid = json['uuid'] as String?;
      if (uuid == null) continue;

      T? localItem;
      try {
        localItem = box.values.firstWhere(
          (item) => (item as dynamic).uuid == uuid,
        );
      } catch (_) {
        localItem = null;
      }

      if (localItem != null && (localItem as dynamic).status == 'pending') {
        continue;
      }

      final newItem = fromJson(json);
      if (localItem != null) {
        await box.put(localItem.key, newItem);
      } else {
        await box.add(newItem);
      }
    }
  }

  static Future<void> _syncEntity<T extends HiveObject>({
    required Box<T> box,
    required String supabaseTable,
    required Map<String, dynamic> Function(T) toMap,
    required void Function(T, Map<String, dynamic>) onSuccess,
    bool Function(T)? preSyncAction,
  }) async {
    final supabase = Supabase.instance.client;
    final pendingItems = box.values
        .where((item) => (item as dynamic).status == 'pending')
        .toList();

    // CREATES
    for (final item in pendingItems.where(
      (i) => (i as dynamic).operation == 'create',
    )) {
      if (preSyncAction != null && !preSyncAction(item)) continue;
      try {
        final response = await supabase
            .from(supabaseTable)
            .insert(toMap(item))
            .select()
            .single();
        onSuccess(item, response);
        (item as dynamic).status = 'synced';
        (item as dynamic).operation = null;
        await item.save();
      } catch (e) {
        debugPrint('[SyncService] ERROR creando en "$supabaseTable": $e');
      }
    }

    // UPDATES
    for (final item in pendingItems.where(
      (i) => (i as dynamic).operation == 'update',
    )) {
      if (preSyncAction != null && !preSyncAction(item)) continue;
      try {
        await supabase
            .from(supabaseTable)
            .update(toMap(item))
            .eq('uuid', (item as dynamic).uuid);
        (item as dynamic).status = 'synced';
        (item as dynamic).operation = null;
        await item.save();
      } catch (e) {
        debugPrint('[SyncService] ERROR actualizando en "$supabaseTable": $e');
      }
    }

    // DELETES
    for (final item in pendingItems.where(
      (i) => (i as dynamic).operation == 'delete',
    )) {
      try {
        await supabase
            .from(supabaseTable)
            .delete()
            .eq('uuid', (item as dynamic).uuid);
        await item.delete();
      } catch (e) {
        debugPrint('[SyncService] ERROR eliminando en "$supabaseTable": $e');
      }
    }
  }
}
