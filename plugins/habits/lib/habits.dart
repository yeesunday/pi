import 'package:flutter/material.dart';
import 'package:pi_core/pi_core.dart';
import 'package:pi_runtime/pi_runtime.dart';
import 'package:pi_ui/pi_ui.dart';
const habitsManifest=PluginManifest(id:'dev.pi.habits',name:'习惯',description:'坚持每天的小步进展。',icon:'repeat',colorValue:0xFF63D6A8);
class HabitsPlugin implements PiPlugin { @override PluginManifest get manifest=>habitsManifest; @override Future<void> register(PluginContext c) async { final r=_Repo(c); registerCollection(c,r,icon:Icons.repeat_rounded,fields:const [EntryField('title','名称',required:true),EntryField('body','详情',multiline:true)],empty:'还没有习惯记录。',order:70); } @override Future<void> start(PluginContext c) async{} @override Future<void> stop(PluginContext c) async{} }
class _Repo extends EntryRepository { _Repo(PluginContext c):super(c,'habits'); }
