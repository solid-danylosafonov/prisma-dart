import 'dart:io';

import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:orm/generator_helper.dart';
import 'package:path/path.dart';

import '../utils/find_project.dart';
import 'client_builder.dart';
import 'generator_options.dart';
import 'model_delegate_builder.dart';
import 'schema_builder.dart';

/// Resolve output.
String _resolveOutput(EnvValue? output, String schemaPath) {
  if (output == null || output.value.isEmpty) {
    return joinRelativePaths(['lib', 'src', 'generated']);
  }

  return relative(join(dirname(schemaPath), output.value));
}

/// Get generated file.
File _getGeneratedFile(GeneratorOptions options) {
  final String directory =
      _resolveOutput(options.config.output, options.schemaPath);

  final String output =
      directory.substring(directory.length - 5).toLowerCase() == '.dart'
          ? directory
          : join(directory, 'prisma_client.dart');

  final File file = File(output);
  if (file.existsSync()) {
    file.deleteSync();
  }

  return file..createSync(recursive: true);
}

final List<String> _ignores = [
  'constant_identifier_names',
  'non_constant_identifier_names',
  'depend_on_referenced_packages',
]..sort();

/// Run Dart client generator
Future<void> generator(GeneratorOptions options) async {
  // Get output file.
  final File output = _getGeneratedFile(options);

  final Library library = Library((LibraryBuilder updates) {
    updates.name = 'prisma.client';

    // Add header comment.
    updates.body.add(Code('''\n
part '${basenameWithoutExtension(output.path)}.g.dart';
// GENERATED CODE - DO NOT MODIFY BY HAND
//
// ignore_for_file: ${_ignores.join(', ')}
//
${'//'.padRight(80, '*')}
// This file was generated by Prisma
// GitHub: https://github.com/odroe/prisma-dart
${'//'.padRight(80, '*')} \n
'''));

    // Exports
    updates.directives.add(Directive.export(
      'package:orm/orm.dart',
      show: [
        'Datasource',
        'PrismaNull',
        'PrismaUnion',
      ]..sort(),
    ));

    // Inport `package:json_annotation/json_annotation.dart`
    // 临时修复👉https://github.com/google/json_serializable.dart/issues/1115
    // 等待 https://github.com/google/json_serializable.dart/pull/1116 并发布新版本
    updates.directives.add(Directive.import(
      'package:json_annotation/json_annotation.dart',
      show: [
        r'$enumDecodeNullable',
        r'$enumDecode',
      ]..sort(),
    ));

    // Build schema.
    SchemaBuilder(options, updates).build();

    // Build model delegates.
    ModelDelegateBuilder(options, updates).build();

    // Build prisma client.
    ClientBuilder(options, updates).build();
  });
  final DartEmitter emitter = DartEmitter.scoped();
  final StringSink sink = library.accept(emitter);
  final DartFormatter formatter = DartFormatter();
  final String formatted = formatter.format(sink.toString());

  // Write to file.
  output.writeAsStringSync(formatted);
}
