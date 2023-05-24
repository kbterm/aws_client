import '../../model/api.dart';
import '../../model/descriptor.dart';
import '../../model/operation.dart';
import '../../model/shape.dart';
import 'service_builder.dart';

class QueryServiceBuilder extends ServiceBuilder {
  final Api api;

  QueryServiceBuilder(this.api);

  @override
  String constructor() {
    final isRegionRequired = !api.isGlobalService;
    return '''
  final _s.QueryProtocol _protocol;
  final Map<String, _s.Shape> shapes;

  ${api.metadata.className}({
    ${isRegionRequired ? 'required String' : 'String?'} region,
    _s.AwsClientCredentials? credentials,
    _s.AwsClientCredentialsProvider? credentialsProvider,
    _s.Client? client, String? endpointUrl,
    })
  : _protocol = _s.QueryProtocol(
      client: client,
      service: ${buildServiceMetadata(api)},
      region: region,
      credentials: credentials,
      credentialsProvider: credentialsProvider,
      endpointUrl: endpointUrl,
    ),
  shapes = shapesJson.map((key, value) => MapEntry(key, _s.Shape.fromJson(value)));
  ''';
  }

  @override
  String imports() => "import '${api.fileBasename}.meta.dart';";

  @override
  String operationContent(Operation operation) {
    final parameterShape = api.shapes[operation.parameterType];

    final buf = StringBuffer();
    buf.writeln('    final \$request = <String, dynamic>{};');
    for (var member in parameterShape?.members ?? <Member>[]) {
      member.shapeClass!.markUsed(true);
      final idempotency =
          member.idempotencyToken ? '?? _s.generateIdempotencyToken()' : '';

      if (member.isRequired || member.idempotencyToken) {
        final code = encodeQueryCode(member.shapeClass!, member.fieldName,
            member: member, maybeNull: false);
        buf.writeln("\$request['${member.name}'] = $code$idempotency;");
      } else {
        final code = encodeQueryCode(member.shapeClass!, 'arg',
            member: member, maybeNull: false);
        buf.writeln(
            "${member.fieldName}?.also((arg) => \$request['${member.name}'] = $code);");
      }
    }
    final params = StringBuffer([
      '\$request, ',
      "action: '${operation.name}',",
      "version: '${api.metadata.apiVersion}',",
      'method: \'${operation.http.method}\', ',
      'requestUri: \'${operation.http.requestUri}\', ',
      'exceptionFnMap: _exceptionFns, ',
      if (operation.authtype == 'none') 'signed: false, ',
      if (operation.input?.shape != null)
        "shape: shapes['${operation.input!.shape}'], ",
      'shapes: shapes,',
    ].join());
    if (operation.output?.resultWrapper != null) {
      params.write('resultWrapper: \'${operation.output!.resultWrapper}\',');
    }
    if (operation.hasReturnType) {
      buf.writeln('    final \$result = await _protocol.send($params);');
      buf.writeln('    return ${operation.returnType}.fromXml(\$result);');
    } else {
      buf.writeln('    await _protocol.send($params);');
    }
    return buf.toString();
  }
}

String encodeQueryCode(Shape shape, String variable,
    {Member? member, Descriptor? descriptor, bool? maybeNull}) {
  maybeNull ??= true;
  if (member?.jsonvalue == true || descriptor?.jsonvalue == true) {
    return 'jsonEncode($variable)';
  } else if (shape.enumeration != null) {
    shape.isTopLevelInputEnum = true;
    return '$variable${maybeNull ? '?' : ''}.toValue()${maybeNull ? "??''" : ''}';
  } else if (shape.type == 'list') {
    final code = encodeQueryCode(shape.member!.shapeClass!, 'e',
        maybeNull: false, descriptor: shape.member!);
    if (code != 'e') {
      final nullAware = maybeNull ? '?' : '';
      return '$nullAware$variable$nullAware.map((e) => $code)$nullAware.toList()';
    }
  } else if (shape.type == 'map') {
    final keyCode = encodeQueryCode(shape.key!.shapeClass!, 'k',
        maybeNull: false, descriptor: shape.key!);
    final valueCode = encodeQueryCode(shape.value!.shapeClass!, 'v',
        maybeNull: false, descriptor: shape.value!);
    if (keyCode != 'k' || valueCode != 'v') {
      final nullAware = maybeNull ? '?' : '';
      return '$variable$nullAware.map((k, v) => MapEntry($keyCode, $valueCode))';
    }
  } else if (shape.type == 'timestamp') {
    final timestampFormat =
        member?.timestampFormat ?? shape.timestampFormat ?? 'iso8601';
    variable =
        '_s.${timestampFormat}ToJson($variable)${timestampFormat == 'unixTimestamp' ? '.toString()' : ''}';
  }

  return variable;
}
