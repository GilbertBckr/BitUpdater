import 'dart:convert';
import 'dart:io';

import 'package:bit_updater/const/enums.dart';
import 'package:bit_updater/cubit/bit_updater_cubit.dart';
import 'package:bit_updater/models/device_version_model.dart';
import 'package:bit_updater/models/server_version_model.dart';
import 'package:bit_updater/models/update_model.dart';
import 'package:bit_updater/services/locator_service.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class BitUpdaterService {
  ServerVersionModel serverVersion = ServerVersionModel(
      minVersion: "", updateUrl: "", platform: "", latestVersion: "");
  DeviceVersionModel deviceVersion =
      DeviceVersionModel(version: "", buildNumber: "");
  var token = CancelToken();

  /// Get the apps versioning info from server and create a ServerVersionModel object.
  Future<void> getServerVersionInfo(String url) async {
    String _endpoint = Platform.isAndroid ? "android" : "ios";
    var response = await http.get(Uri.parse(url + _endpoint), headers: {
      "Accept": "application/json",
      "Content-Type": "application/json"
    });

    ///TODO: Make sure that the server versioning includes major minor and patch versioning as 3.0.0

    serverVersion = ServerVersionModel.fromJson(jsonDecode(response.body));
    // RegExp versioningPattern = RegExp(r"\d\.\d\.\d");
    // if (versioningPattern.hasMatch(serverVersion.minVersion) &&
    //     versioningPattern.hasMatch(serverVersion.latestVersion)) {
    //   throw FlutterError("Wrong versioning info from server. \n"
    //       "Versioning does not match. Make sure versioning is formatted with MAJOR, MINOR and PATCH. Exp: 3.0.0");
    // }
  }

  /// Get device info from packageInfo package and create a DeviceVersionModel object.
  Future<void> getDeviceVersionInfo() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String buildNumber = packageInfo.buildNumber;
    String version = packageInfo.version;

    deviceVersion =
        DeviceVersionModel(version: version, buildNumber: buildNumber);
  }

  Future<void> downloadApp() async {
    Directory tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;
    String downloadUrl = serverVersion.updateUrl;

    try {
      bitUpdaterGetIt<BitUpdaterCubit>()
          .changeUpdateStatus(UpdateStatus.downloading);
      await Dio().download(
        downloadUrl,
        "$tempPath/app.apk",
        cancelToken: token,
        options: Options(
          receiveDataWhenStatusError: false,
        ),
        onReceiveProgress: (progress, totalProgress) {
          bitUpdaterGetIt<BitUpdaterCubit>()
              .updateDownloadProgress(progress, totalProgress);
          if (progress == totalProgress) {
            OpenFile.open('$tempPath/app.apk');
          }
        },
        deleteOnError: true,
      ).whenComplete(() => bitUpdaterGetIt<BitUpdaterCubit>()
          .changeUpdateStatus(UpdateStatus.completed));
    } catch (error) {
      if (error is DioError) {
        bitUpdaterGetIt<BitUpdaterCubit>()
            .changeUpdateStatus(UpdateStatus.cancelled);
      } else {
        bitUpdaterGetIt<BitUpdaterCubit>()
            .changeUpdateStatus(UpdateStatus.failed);
      }

      debugPrint(error.toString());
    }
  }

  Future<bool> checkServerUpdate(String url, BuildContext context) async {
    bitUpdaterGetIt<BitUpdaterCubit>()
        .changeUpdateStatus(UpdateStatus.checking);
    bitUpdaterGetIt<BitUpdaterCubit>().getDismissedVersionFromShared();

    int dismissedVersion = bitUpdaterGetIt<BitUpdaterCubit>().dismissedVersion;
    bool _isUpdateAvailable = false;

    await getServerVersionInfo(url);

    await getDeviceVersionInfo();

    try {
      int minSupportVersion =
          int.parse(serverVersion.minVersion.replaceAll(".", ""));
      int latestVersion =
          int.parse(serverVersion.latestVersion.replaceAll(".", ""));
      int deviceBuildVersion =
          int.parse(deviceVersion.version.replaceAll(".", ""));

      if (minSupportVersion > deviceBuildVersion ||
          (deviceBuildVersion < latestVersion &&
              dismissedVersion != latestVersion)) {
        _isUpdateAvailable = true;
      } else {
        _isUpdateAvailable = false;
      }

      bitUpdaterGetIt<BitUpdaterCubit>().setUpdateModel(UpdateModel(
        isUpdateAvailable: _isUpdateAvailable,
        isUpdateForced: minSupportVersion > deviceBuildVersion,
        platform: serverVersion.platform,
        minSupportVersion: serverVersion.minVersion,
        latestVersion: serverVersion.latestVersion,
        deviceVersion: deviceVersion.version,
        downloadUrl: serverVersion.updateUrl,
      ));

      bitUpdaterGetIt<BitUpdaterCubit>().changeUpdateStatus(
          dismissedVersion == latestVersion
              ? UpdateStatus.availableButDismissed
              : UpdateStatus.available);

      return _isUpdateAvailable;
    } catch (error) {
      bitUpdaterGetIt<BitUpdaterCubit>().setError(FlutterError(
          "Wrong versioning info from server. \n"
          "Versioning does not match. Make sure versioning is formatted with MAJOR, MINOR and PATCH. Exp: 3.0.0"));
      return false;
    }
  }
}
