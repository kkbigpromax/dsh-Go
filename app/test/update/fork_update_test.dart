import 'dart:convert';

import 'package:dsh_app/update/checker.dart';
import 'package:dsh_app/update/release.dart';
import 'package:dsh_app/update/update_config.dart';
import 'package:dsh_app/update/version.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Map<String, Object?> release(String version, {bool draft = false}) => {
  'tag_name': 'v$version',
  'html_url': 'https://github.com/kkbigpromax/dsh-Go/releases/tag/v$version',
  'draft': draft,
  'prerelease': true,
  'assets': [
    {
      'name': 'dsh-go-$version-arm64.apk',
      'browser_download_url':
          'https://github.com/kkbigpromax/dsh-Go/releases/download/v$version/dsh-go-$version-arm64.apk',
      'size': 100,
      'digest': 'sha256:${'a' * 64}',
    },
  ],
};

void main() {
  test('fork checks select the newest published APK, including fork pre-releases', () async {
    final http = FakeHttp({
      githubReleasesApi.toString(): (_, _) => textResponse(
        jsonEncode([
          release('2.0.0', draft: true),
          release('1.0.16-fork.1'),
          {'tag_name': 'source-only', 'draft': false, 'assets': []},
          release('1.0.16-fork.3'),
          release('1.0.16-fork.2'),
        ]),
      ),
    });
    final result = await UpdateChecker(
      http: http,
      sources: defaultUpdateSources(),
    ).check(installed: AppVersion.tryParse('1.0.16-fork.1')) as CheckFound;
    expect(result.release.version.name, '1.0.16-fork.3');
    expect(result.release.apkFor(ApkFlavor.arm64)!.url.path, contains('/kkbigpromax/dsh-Go/releases/download/'));
    expect(http.urls, ['https://api.github.com/repos/kkbigpromax/dsh-Go/releases?per_page=30']);
  });

  test('a fork without releases has no original-source fallback', () async {
    final http = FakeHttp({githubReleasesApi.toString(): (_, _) => textResponse('[]')});
    final result = await UpdateChecker(http: http, sources: defaultUpdateSources()).check() as CheckFailed;
    expect(result.failure, CheckFailure.noRelease);
    expect(http.urls, [githubReleasesApi.toString()]);
  });
}
