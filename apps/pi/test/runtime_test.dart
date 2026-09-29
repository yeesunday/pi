import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';

class _Plugin implements PiPlugin {
  _Plugin(this.id, this.log);
  final String id; final List<String> log;
  @override PluginManifest get manifest => PluginManifest(id:id,name:id,description:'',icon:'',colorValue:0);
  @override Future<void> register(PluginContext c) async { c.contribute(UiContribution(id:'$id.ui',slot:'test',order:1,builder:(c,r)=>SizedBox())); }
  @override Future<void> start(PluginContext c) async { log.add('start:$id'); }
  @override Future<void> stop(PluginContext c) async { log.add('stop:$id'); }
}
void main() {
  test('runtime starts dependencies and cleans registrations in reverse order', () async {
    final log=<String>[]; final catalog=PluginCatalog([
      PluginDescriptor(manifest:const PluginManifest(id:'a',name:'a',description:'',icon:'',colorValue:0),create:()=>_Plugin('a',log)),
      PluginDescriptor(manifest:const PluginManifest(id:'b',name:'b',description:'',icon:'',colorValue:0,dependencies:{'a'}),create:()=>_Plugin('b',log)),
    ]); final runtime=PiRuntime(catalog:catalog);
    await runtime.install('b'); expect(runtime.activePlugins.map((x)=>x.id),['a','b']); expect(log,['start:a','start:b']); expect(runtime.ui.contributions('test'),hasLength(2));
    await runtime.uninstall('b'); expect(runtime.ui.contributions('test'),hasLength(1)); await runtime.uninstall('a'); expect(runtime.ui.contributions('test'),isEmpty); expect(log,['start:a','start:b','stop:b','stop:a']); await runtime.shutdown();
  });
  test('entity store enforces optimistic revision', () async {
    final store=InMemoryDataStore(); final first=await store.upsert(PiEntity(id:'1',pluginId:'p',type:'x',data:{'title':'one'}));
    expect(first.revision,1); await expectLater(store.upsert(first.copyWith(data:{'title':'two'}),expectedRevision:0),throwsA(isA<DataConflict>()));
    final next=await store.upsert(first.copyWith(data:{'title':'two'}),expectedRevision:1); expect(next.revision,2);
  });

  test('profile upgrades ignore plugins removed from the catalog', () async {
    final data = InMemoryDataStore();
    await data.writeSetting('runtime/profile/personal', {'plugins': ['removed.plugin']});
    final runtime = PiRuntime(catalog: PluginCatalog(const []), data: data);
    await runtime.installDefaults(const []);
    expect(runtime.activePlugins, isEmpty);
  });
}
