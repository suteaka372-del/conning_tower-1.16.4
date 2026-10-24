import 'dart:developer';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class PathUtil {
  late Directory appDocumentsDirectory;

  late String objectBoxPath;
  late String objectBoxDataDBPath;

  late String localAkashiSchedulePath;
  late String localKcWikiDataPath;
  late String localKcQuestsPath;
  late String localKcanotifyQuestsPath;
  late String localEoQuestTrackersPath;
  late String localEoQuestsMetadataPath;
  late String localDevStatsPath;

  late String localL10nSlotItemPath;
  late String localL10nUseItemInImprovePath;
  late String localL10nEquipmentTypeWithoutIdPath;

  late String customTaskDataJsonPath;
  late String customTaskDataYamlPath;

  static Future<PathUtil> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    log("docsDir: $docsDir");
    return PathUtil._create(docsDir);
  }

  PathUtil._create(Directory docsDir) {
    appDocumentsDirectory = docsDir;

    objectBoxPath = p.join(docsDir.path, "obx");
    objectBoxDataDBPath = p.join(objectBoxPath, 'data.mdb');

    final providersDir = p.join(docsDir.path, "providers");
    localAkashiSchedulePath = p.join(providersDir, "akashi_schedule.json");
    localKcWikiDataPath = p.join(providersDir, "kcwiki_data.json");
    localKcQuestsPath = p.join(providersDir, "quest_tree", "kcquests_scn.json");
    localKcanotifyQuestsPath = p.join(providersDir, "quest_tree", "kcanotify_quests_jp.json");
    localEoQuestTrackersPath = p.join(providersDir, "quest_tracker", "eo_quest_trackers.json");
    localEoQuestsMetadataPath = p.join(providersDir, "quest_tracker", "eo_quests_metadata.json");
    localDevStatsPath = p.join(providersDir, "dev_stats", "latest.json");

    final tasksDir = p.join(providersDir, "task");
    customTaskDataJsonPath = p.join(tasksDir, "tasks.json");
    customTaskDataYamlPath = p.join(tasksDir, "tasks.yaml");

    final localizationDir = p.join(docsDir.path, "l10n");
    localL10nSlotItemPath = p.join(localizationDir, "slotitem_l10n.json");
    localL10nUseItemInImprovePath =
        p.join(localizationDir, "useitem_in_improve_l10n.json");
    localL10nEquipmentTypeWithoutIdPath =
        p.join(localizationDir, "equipment_type_l10n_without_id.json");
  }

  String getKcCacheDataPath(String path) {
    final gameDataDir =
        p.join(appDocumentsDirectory.path, "kancolle", "kcsapi");
    final split = path.split("/");
    split.remove("");
    final fileName = "${split.last}.json";
    final dirName = split.sublist(0, split.length - 1).join("/");
    return p.join(gameDataDir, dirName, fileName);
  }
}
