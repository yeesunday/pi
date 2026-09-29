import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';
const todoManifest = PluginManifest(id:'dev.pi.todo',name:'待办',description:'把今天真正重要的几件事放在手边。',icon:'check_circle',colorValue:0xFF6C63FF,permissions:{Permission.notifications});
class TodoPlugin implements PiPlugin {
 @override PluginManifest get manifest=>todoManifest;
 @override Future<void> register(PluginContext context) async { final repo=_TodoRepo(context); registerCollection(context,repo,icon:Icons.check_circle_rounded,fields:const [EntryField('title','要做什么？',required:true),EntryField('body','备注',multiline:true)],empty:'今天还没有待办，享受一点留白。',order:10,subtitle:(e)=>e.data['body'] as String? ?? '',checkable:true); }
 @override Future<void> start(PluginContext context) async { final r=_TodoRepo(context); if((await r.list()).isEmpty) await r.save({'title':'欢迎使用 Pi','body':'点击右侧 + 添加一件小事','completed':false}); }
 @override Future<void> stop(PluginContext context) async {}
}
class _TodoRepo extends EntryRepository { _TodoRepo(PluginContext c):super(c,'todo'); }
