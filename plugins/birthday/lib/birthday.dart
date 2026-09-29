import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';
const birthdayManifest = PluginManifest(id:'dev.pi.birthday',name:'生日',description:'记住那些值得被好好庆祝的日子。',icon:'cake',colorValue:0xFFFF8B7B,permissions:{Permission.notifications,Permission.contacts});
class BirthdayPlugin implements PiPlugin {
 @override PluginManifest get manifest=>birthdayManifest;
 @override Future<void> register(PluginContext context) async { final repo=_BirthdayRepo(context); registerCollection(context,repo,icon:Icons.cake_rounded,fields:const [EntryField('title','姓名',required:true),EntryField('date','生日',date:true,required:true)],empty:'把重要的人记在这里。',order:20,subtitle:(e)=>e.data['date'] as String? ?? ''); }
 @override Future<void> start(PluginContext context) async { final r=_BirthdayRepo(context); if((await r.list()).isEmpty) { await r.save({'title':'爸爸','date':'1970-10-18'}); await r.save({'title':'小满','date':'2026-09-13'}); } }
 @override Future<void> stop(PluginContext context) async {}
}
class _BirthdayRepo extends EntryRepository { _BirthdayRepo(PluginContext c):super(c,'birthday'); }
