import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Asegúrate de que las importaciones a tus modelos sean correctas
import 'productores_page.dart';
import 'parcelas_page.dart';
import 'visita_parcela.dart';

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
    final visitaBox = await _openBox(
      'visitas_monitoreo',
      VisitaMonitoreoAdapter(),
    );

    // --- PASO 1: SINCRONIZAR PRODUCTORES ---
    final pendingProductores = productorBox.values
        .where((p) => p.status == 'pending' && p.operation == 'create')
        .toList();
    if (pendingProductores.isNotEmpty) {
      debugPrint(
        '[SyncService] Intentando sincronizar ${pendingProductores.length} productores nuevos...',
      );
      try {
        final List<Map<String, dynamic>> productoresToInsert =
            pendingProductores
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
        final response = await supabase
            .from('productores')
            .insert(productoresToInsert)
            .select();
        for (final remoteProd in response) {
          final localProd = productorBox.values.firstWhere(
            (p) => p.uuid == remoteProd['uuid'],
          );
          localProd.serverId = remoteProd['id_productor'];
          localProd.status = 'synced';
          localProd.operation = null;
          await localProd.save();
          debugPrint(
            '[SyncService] Productor "${localProd.nombre}" sincronizado con éxito.',
          );
        }
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          debugPrint(
            '[SyncService] Aviso: Se intentó re-sincronizar un productor que ya existía. Esto es normal. Resolviendo...',
          );
          // Si hay duplicados, los buscamos uno a uno para marcarlos como sincronizados
          for (final p in pendingProductores) {
            try {
              final remote = await supabase
                  .from('productores')
                  .select('id_productor')
                  .eq('uuid', p.uuid)
                  .single();
              p.serverId = remote['id_productor'];
              p.status = 'synced';
              p.operation = null;
              await p.save();
            } catch (_) {}
          }
        } else {
          debugPrint('[SyncService] ERROR CRÍTICO AL INSERTAR PRODUCTORES: $e');
        }
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
        try {
          final ownerProductor = productorBox.values.firstWhere(
            (p) => p.uuid == parcela.productorUuid,
          );
          if (ownerProductor.status != 'synced' ||
              ownerProductor.serverId == null) {
            debugPrint(
              '[SyncService] OMITIENDO parcela "${parcela.nombre}" porque su productor no está sincronizado.',
            );
            continue;
          }
          parcela.productorId = ownerProductor.serverId;
          final response = await supabase
              .from('parcelas')
              .insert(parcela.toMap())
              .select()
              .single();
          parcela.serverId = response['id_parcela'];
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

    // --- PASO 3: SINCRONIZAR VISITAS (¡AHORA COMPLETO!) ---
    final pendingVisitas = visitaBox.values
        .where((v) => v.status == 'pending' && v.operation == 'create')
        .toList();
    if (pendingVisitas.isNotEmpty) {
      debugPrint(
        '[SyncService] Intentando sincronizar ${pendingVisitas.length} visitas nuevas...',
      );
      for (final visita in pendingVisitas) {
        try {
          final ownerParcela = parcelaBox.values.firstWhere(
            (p) => p.uuid == visita.parcelaUuid,
          );
          if (ownerParcela.status != 'synced' ||
              ownerParcela.serverId == null) {
            debugPrint(
              '[SyncService] OMITIENDO visita (uuid: ${visita.uuid}) porque su parcela no está sincronizada.',
            );
            continue;
          }
          visita.parcelaId = ownerParcela.serverId;
          final insertData = {
            'id_parcela': visita.parcelaId,
            'fecha_visita': visita.fechaVisita,
            'observaciones': visita.observaciones,
            'recomendaciones': visita.recomendaciones,
            'ep': visita.ep,
            'ap': visita.ap,
            'mp': visita.mp,
            'bp': visita.bp,
            'cp': visita.cp,
            'monitoreo_plantas': jsonDecode(visita.monitoreoPlantasJson),
            'usuario_registro_id': visita.usuarioRegistroId,
            'usuario_registro_email': visita.usuarioRegistroEmail,
            'uuid': visita.uuid,
            'uuid_parcelas': visita.parcelaUuid,
          };
          await supabase.from('visitas_monitoreo').insert(insertData);
          visita.status = 'synced';
          visita.operation = null;
          await visita.save();
          debugPrint(
            '[SyncService] Visita para parcela "${ownerParcela.nombre}" sincronizada con éxito.',
          );
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            debugPrint(
              '[SyncService] La visita (uuid: ${visita.uuid}) ya existía. Marcando como sincronizada.',
            );
            visita.status = 'synced';
            visita.operation = null;
            await visita.save();
          } else {
            debugPrint(
              '[SyncService] ERROR de BD sincronizando visita (uuid: ${visita.uuid}): $e',
            );
          }
        } catch (e) {
          debugPrint(
            '[SyncService] ERROR GENERAL sincronizando visita (uuid: ${visita.uuid}): $e',
          );
        }
      }
    }
  }
}
