// Starting other programs (file manager, desktop tools). In the AppImage and the
// AUR package, AppRun points LD_LIBRARY_PATH and GDK_PIXBUF_MODULE_FILE at the
// bundled Ubuntu 22.04 libraries, which a newer distro's programs can't load
// ("symbol lookup error": the file manager never opens). They get the
// environment without those.
import 'dart:io';

/// [env] without what AppRun set for the bundle next to [executable]
/// (`<dir>/usr/bin/fotoroll`, libraries in `<dir>/usr/lib`).
Map<String, String> hostEnvironment([Map<String, String>? env, String? executable]) {
  env ??= Platform.environment;
  final bundleLib = '${File(executable ?? Platform.resolvedExecutable).parent.parent.path}/lib';
  final out = Map.of(env)..remove('LIBMPV_LIBRARY_PATH');
  final ld = (env['LD_LIBRARY_PATH'] ?? '').split(':').where((p) => p.isNotEmpty && p != bundleLib).join(':');
  if (ld.isEmpty) {
    out.remove('LD_LIBRARY_PATH');
  } else {
    out['LD_LIBRARY_PATH'] = ld;
  }
  if (env['GDK_PIXBUF_MODULE_FILE']?.endsWith('/fotoroll-pixbuf-loaders.cache') ?? false) {
    out.remove('GDK_PIXBUF_MODULE_FILE');
  }
  return out;
}

/// [Process.run] with the [hostEnvironment].
Future<ProcessResult> runHost(String executable, List<String> args) =>
    Process.run(executable, args, environment: hostEnvironment(), includeParentEnvironment: false);
