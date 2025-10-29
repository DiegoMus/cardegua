import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'productores_page.dart';
import 'parcelas_page.dart';

class SyncService {
  static Future<Box<T>> _openBox<T>(String name, TypeAdapter<T> adapter) async {
    try {
      if (!Hive.isAdapterRegistered(adapter.typeId))
        Hive.registerAdapter(adapter);
    } catch (_) {}
    if (!Hive.isBoxOpen(name)) return await Hive.openBox<T>(name);
    return Hive.box<T>(name);
  }

  static Future<void> syncAllPendingData() async {
    final supabase = Supabase.instance.client;
    final productorBox = await _openBox('productores', ProductorAdapter());
    final parcelaBox = await _openBox('parcelas', ParcelaAdapter());

    final Set<String> successfullySyncedProducers = {};

    // --- PASO 1: SINCRONIZAR PRODUCTORES ---
    final pendingProductores = productorBox.values
        .where((p) => p.status == 'pending' && p.operation == 'create')
        .toList();
    if (pendingProductores.isNotEmpty) {
      debugPrint(
        '[SyncService] Intentando sincronizar ${pendingProductores.length} productores nuevos...',
      );

      final List<Map<String, dynamic>> productoresToInsert = pendingProductores
          .map(
            (p) => {
              'nombre': p.nombre,
              'email': p.email,
              'telefono': p.telefono,
              'cui': p.cui,
              'uuid': p.uuid,
            },
          )
          .toList();

      try {
        final response = await supabase
            .from('productores')
            .insert(productoresToInsert)
            .select();

        for (final remoteProd in response) {
          final remoteUuid = remoteProd['uuid'] as String?;
          if (remoteUuid == null) continue;

          // Busca el productor local por el UUID que se ENVIÓ, no por el que se recibió.
          final localProd = pendingProductores.firstWhere(
            (p) =>
                p.uuid ==
                (productoresToInsert.firstWhere(
                  (m) => m['nombre'] == remoteProd['nombre'],
                ))['uuid'],
            orElse: () => throw Exception(
              'No se encontró el productor local correspondiente',
            ),
          );

          // ¡Corrección Clave! Actualiza el UUID local si el servidor lo cambió.
          if (localProd.uuid != remoteUuid) {
            debugPrint(
              '[SyncService] CORRECCIÓN DE UUID: El servidor cambió el UUID del productor "${localProd.nombre}" de ${localProd.uuid} a $remoteUuid',
            );
            localProd.uuid = remoteUuid;
          }

          localProd.serverId = remoteProd['id_productor'];
          localProd.status = 'synced';
          localProd.operation = null;
          await localProd.save();

          successfullySyncedProducers.add(remoteUuid);
          debugPrint(
            '[SyncService] Productor "${localProd.nombre}" sincronizado con éxito.',
          );
        }
      } catch (e) {
        debugPrint(
          '================================================================',
        );
        debugPrint('[SyncService] ¡¡¡ERROR CRÍTICO AL INSERTAR PRODUCTORES!!!');
        debugPrint('Error detallado: $e');
        debugPrint(
          '================================================================',
        );
        return;
      }
    }

    // --- PASO 2: SINCRONIZAR PARCELAS ---
    final pendingParcelas = parcelaBox.values
        .where((p) => p.status == 'pending' && p.operation == 'create')
        .toList();
    if (pendingParcelas.isNotEmpty) {
      debugPrint(
        '[SyncService] Intentando sincronizar ${pendingParcelas.length} parcelas nuevas...',
      );
      for (final parcela in pendingParcelas) {
        Productor? owner;
        try {
          owner = productorBox.values.firstWhere(
            (p) => p.uuid == parcela.productorUuid,
          );
        } catch (_) {
          owner = null;
        }

        final isOwnerSynced =
            (owner != null && owner.status == 'synced') ||
            successfullySyncedProducers.contains(parcela.productorUuid);

        if (!isOwnerSynced) {
          debugPrint(
            '[SyncService] OMITIENDO parcela "${parcela.nombre}", su productor dueño (uuid: ${parcela.productorUuid}) no está sincronizado.',
          );
          continue;
        }

        try {
          parcela.productorId = owner!.serverId;
          final res = await supabase
              .from('parcelas')
              .insert({
                'nombre': parcela.nombre,
                'area': parcela.area,
                'id_tipo_cultivo': parcela.idTipoCultivo,
                'id_municipio': parcela.idMunicipio,
                'uuid': parcela.uuid,
                'productor_uuid': parcela.productorUuid,
                'id_productor': parcela.productorId,
                'vigente': parcela.vigente,
              })
              .select()
              .single();

          parcela.serverId = res['id_parcela'];
          parcela.status = 'synced';
          parcela.operation = null;
          await parcela.save();
          debugPrint(
            '[SyncService] Parcela "${parcela.nombre}" sincronizada con éxito.',
          );
        } catch (e) {
          debugPrint(
            '[SyncService] ERROR sincronizando parcela "${parcela.nombre}": $e',
          );
        }
      }
    }
  }
}
