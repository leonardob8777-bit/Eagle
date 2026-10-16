#!/usr/bin/env python3
"""Verify approved Core, adapter and app-service sources using project metadata only.

This gate does not invoke Xcode, read source contents, or run project build phases.
It intentionally supports the current synchronized-root layout and fails when
new metadata would require a broader interpretation of source membership.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path, PurePosixPath
import stat
import subprocess
import tempfile


APP_CORE_RELATIVE_PATHS = (
    "lara/EagleCore/AuraStudio/EagleAuraStudioProgressSchedule.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioRequestCapture.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioResultConsumption.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioStepProgress.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioStepFlow.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioSessionAdmission.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioResultAdmission.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioRequestPreparation.swift",
    "lara/EagleCore/Gallery/EagleGalleryPosition.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioRequestAdmission.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioApplyGate.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioNativeContract.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioDisplayGeometry.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioModePolicy.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioDraftModes.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioColors.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioProfileState.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioProfileStatus.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioReconciliation.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioEntryFlow.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioOperationUI.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioResultFeedback.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioCompletion.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioPreflightFailure.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioVerifiedRollback.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioUnverifiedFailure.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticsReport.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioOperationPlan.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioPreview.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioCapability.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioTarget.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticsPresentation.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticLog.swift",
    "lara/EagleCore/AuraStudio/EagleAuraStudioColorPresentation.swift",
    "lara/EagleCore/IslandGallery/EagleIslandGalleryCatalog.swift",
    "lara/EagleCore/IslandGallery/EagleIslandGalleryFilter.swift",
    "lara/EagleCore/IslandGallery/EagleIslandGalleryFavorites.swift",
    "lara/EagleCore/IslandGallery/EagleIslandGallerySelection.swift",
    "lara/EagleCore/IslandGallery/EagleIslandGalleryCollection.swift",
    "lara/EagleCore/IslandGallery/EagleIslandGalleryRecovery.swift",
    "lara/EagleCore/IslandGallery/EagleIslandGalleryLoadFlow.swift",
    "lara/EagleCore/IslandGallery/EagleIslandGalleryActionFlow.swift",
    "lara/EagleCore/Localization/EagleLocalization.swift",
    "lara/EagleCore/Archives/EagleZIPArchive.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInTheme.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryCore.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryApplyFlow.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInApplyFlow.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryRestoreFlow.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryPackageInventory.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryPackageValidation.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryFrameDimensions.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryCatalog.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryCatalogResponse.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryCatalogLoader.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryPackageDownloader.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryPackageArchive.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryCacheDirectory.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryCachedFrames.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryStagingDirectory.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryFrameWriter.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryCacheCommit.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryMediaFilter.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryFavorites.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryCollection.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySelection.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryVisitOrder.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySelectionMemory.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySession.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySynchronization.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryInteractions.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryLifecycle.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryStoredSelection.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryPreviewReadiness.swift",
)
APP_ADAPTER_RELATIVE_PATHS = (
    "lara/views/new/EagleTouchPoint.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioProgressScheduler.swift",
    "lara/EagleAdapters/Gallery/EagleGalleryPositionStorage.swift",
    "lara/EagleAdapters/Appearance/EagleApplyButtonStyle.swift",
    "lara/EagleAdapters/Appearance/EagleVisualTheme.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioDisplayMetrics.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioAccessNote.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioSurfacePicker.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioApplyButton.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioRestoreButton.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioColorBinding.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioButtonStyles.swift",
    "lara/EagleAdapters/AuraStudio/EagleAuraStudioPreviewStyles.swift",
    "lara/EagleAdapters/IslandGallery/EagleIslandGalleryCatalogLoader.swift",
    "lara/EagleAdapters/IslandGallery/EagleIslandGalleryPackage.swift",
    "lara/EagleAdapters/Diagnostics/EagleDiagnosticDelivery.swift",
    "lara/EagleAdapters/Diagnostics/EagleLogHistory.swift",
    "lara/EagleAdapters/DockGallery/EagleDockGalleryFrameImage.swift",
    "lara/EagleAdapters/DockGallery/EagleDockGalleryPackagePreparer.swift",
    "lara/EagleAdapters/DockGallery/EagleDockGalleryPackageCache.swift",
    "lara/EagleAdapters/DockGallery/EagleDockGalleryPackagePreparation.swift",
    "lara/EagleAdapters/DockGallery/EagleDockGalleryStore.swift",
    "lara/EagleAdapters/EagleRemoteMediaLoader.swift",
    "lara/EagleAdapters/EagleRemoteMediaPreview.swift",
)
APP_SERVICE_RELATIVE_PATHS = (
    "lara/config/EagleGalleryServices.swift",
    "lara/config/EagleAppDiagnostics.swift",
    "lara/EagleServices/Diagnostics/EagleDiagnosticLogger.swift",
)
APP_VALIDATION_RELATIVE_PATHS = APP_CORE_RELATIVE_PATHS + APP_ADAPTER_RELATIVE_PATHS + APP_SERVICE_RELATIVE_PATHS

PROJECT_RELATIVE_PATH = "lara.xcodeproj/project.pbxproj"
APPLICATION_PRODUCT_TYPE = "com.apple.product-type.application"


def _repository_root(repo: Path) -> Path:
    repo = Path(repo).absolute()
    if repo.is_symlink():
        raise ValueError(f"Repository root must not be a symbolic link: {repo}")
    try:
        resolved = repo.resolve(strict=True)
    except OSError as error:
        raise ValueError(f"Repository root is unavailable: {repo}") from error
    if not resolved.is_dir():
        raise ValueError(f"Repository root is not a directory: {repo}")
    return resolved


def _regular_relative_file(repo: Path, relative: str) -> Path:
    """Check metadata without opening any source file."""
    parts = PurePosixPath(relative).parts
    if not parts or relative.startswith("/") or any(part in (".", "..") for part in parts):
        raise ValueError(f"Unsupported repository-relative source path: {relative}")
    current = repo
    for index, part in enumerate(parts):
        current = current / part
        try:
            metadata = current.lstat()
        except OSError as error:
            raise ValueError(f"Required file or parent is missing: {relative}") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise ValueError(f"Required file or parent is a symbolic link: {relative}")
        if index < len(parts) - 1:
            if not stat.S_ISDIR(metadata.st_mode):
                raise ValueError(f"Required source parent is not a directory: {relative}")
        elif not stat.S_ISREG(metadata.st_mode):
            raise ValueError(f"Required source is not a regular file: {relative}")
    try:
        current.resolve(strict=True).relative_to(repo)
    except (OSError, ValueError) as error:
        raise ValueError(f"Required source escapes the repository: {relative}") from error
    return current


def load_project(repo: Path) -> dict:
    """Read the OpenStep project through macOS's read-only plist converter."""
    root = _repository_root(repo)
    project_file = _regular_relative_file(root, PROJECT_RELATIVE_PATH)
    try:
        converted = subprocess.run(
            ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(project_file)],
            check=False,
            capture_output=True,
            text=True,
            timeout=55,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError("Project metadata conversion is unavailable or timed out") from error
    if converted.returncode:
        detail = converted.stderr.strip() or converted.stdout.strip()
        raise ValueError(f"Project metadata could not be parsed: {detail}")
    try:
        project = json.loads(converted.stdout)
    except json.JSONDecodeError as error:
        raise ValueError("Project metadata conversion returned invalid JSON") from error
    if not isinstance(project, dict):
        raise ValueError("Project metadata must be a dictionary")
    return project


def _object(objects: dict, reference: object, expected: str | tuple[str, ...], label: str) -> dict:
    if not isinstance(reference, str) or reference not in objects:
        raise ValueError(f"Missing or dangling {label} reference")
    value = objects[reference]
    kinds = (expected,) if isinstance(expected, str) else expected
    if not isinstance(value, dict) or value.get("isa") not in kinds:
        raise ValueError(f"Unsupported {label} object type")
    return value


def _references(value: object, label: str, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ValueError(f"Unsupported {label} reference list")
    if not value and not allow_empty:
        raise ValueError(f"Missing {label} references")
    if len(value) != len(set(value)):
        raise ValueError(f"Duplicate {label} references")
    return value


def _configurations(objects: dict, owner: dict, label: str) -> list[dict]:
    config_list = _object(
        objects, owner.get("buildConfigurationList"), "XCConfigurationList", f"{label} configuration list"
    )
    references = _references(config_list.get("buildConfigurations"), f"{label} configuration")
    summaries = []
    names = set()
    summary_settings = (
        "SWIFT_VERSION",
        "SWIFT_DEFAULT_ACTOR_ISOLATION",
        "SWIFT_APPROACHABLE_CONCURRENCY",
        "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY",
        "SWIFT_OPTIMIZATION_LEVEL",
        "SWIFT_COMPILATION_MODE",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
        "IPHONEOS_DEPLOYMENT_TARGET",
    )
    for reference in references:
        config = _object(objects, reference, "XCBuildConfiguration", f"{label} configuration")
        name = config.get("name")
        if not isinstance(name, str) or not name or name in names:
            raise ValueError(f"Missing or duplicate {label} configuration name")
        names.add(name)
        if "baseConfigurationReference" in config:
            raise ValueError(f"Unsupported external configuration in {label} {name}")
        settings = config.get("buildSettings")
        if not isinstance(settings, dict):
            raise ValueError(f"Unsupported build settings in {label} {name}")
        for key in settings:
            if not isinstance(key, str):
                raise ValueError(f"Unsupported build setting key in {label} {name}")
            if key.split("[", 1)[0] in ("EXCLUDED_SOURCE_FILE_NAMES", "INCLUDED_SOURCE_FILE_NAMES"):
                raise ValueError(f"Unsupported source inclusion or exclusion setting in {label} {name}: {key}")
        summary = {"name": name}
        summary.update({key: settings[key] for key in summary_settings if key in settings})
        summaries.append(summary)
    return summaries


def _exception_path(value: object) -> PurePosixPath:
    if not isinstance(value, str) or not value:
        raise ValueError("Unsupported empty membership exception path")
    if any(character in value for character in "*?[]$\\"):
        raise ValueError(f"Unsupported membership exception pattern: {value}")
    parts = value.rstrip("/").split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError(f"Unsupported membership exception path: {value}")
    return PurePosixPath(*parts)


def inspect_membership(project: dict, repo: Path) -> dict:
    """Verify the approved files' synchronized membership, without building."""
    if not isinstance(project, dict) or not isinstance(project.get("objects"), dict):
        raise ValueError("Project metadata is missing its object dictionary")
    objects = project["objects"]
    project_object = _object(objects, project.get("rootObject"), "PBXProject", "project root")
    if project_object.get("projectDirPath", "") or project_object.get("projectRoot", ""):
        raise ValueError("Unsupported external project root or directory")
    main_group = _object(objects, project_object.get("mainGroup"), "PBXGroup", "main group")
    if main_group.get("sourceTree") != "<group>" or main_group.get("path", ""):
        raise ValueError("Unsupported main group source tree or path")
    children = _references(main_group.get("children"), "main group child")
    target_references = _references(project_object.get("targets"), "project target")
    applications = []
    for reference in target_references:
        target = _object(
            objects, reference, ("PBXNativeTarget", "PBXAggregateTarget", "PBXLegacyTarget"), "project target"
        )
        if target.get("productType") == APPLICATION_PRODUCT_TYPE:
            if target.get("isa") != "PBXNativeTarget":
                raise ValueError("Unsupported application target object type")
            applications.append((reference, target))
    if len(applications) != 1:
        raise ValueError(f"Expected exactly one application target, found {len(applications)}")
    target_reference, target = applications[0]
    if not isinstance(target.get("name"), str) or not target["name"]:
        raise ValueError("Application target is missing its name")
    product = _object(objects, target.get("productReference"), "PBXFileReference", "application product")
    if product.get("sourceTree") != "BUILT_PRODUCTS_DIR" or not isinstance(product.get("path"), str):
        raise ValueError("Unsupported application product reference")
    roots = _references(target.get("fileSystemSynchronizedGroups"), "attached synchronized root")
    if len(roots) != 1:
        raise ValueError("Unsupported multiple attached synchronized roots")
    root_reference = roots[0]
    synchronized_root = _object(
        objects, root_reference, "PBXFileSystemSynchronizedRootGroup", "synchronized root"
    )
    if root_reference not in children:
        raise ValueError("Synchronized root is detached from the main group")
    if synchronized_root.get("path") != "lara" or synchronized_root.get("sourceTree") != "<group>":
        raise ValueError("Unsupported synchronized root path or source tree; expected lara")
    supported_root_keys = {"isa", "path", "sourceTree", "exceptions", "name"}
    unexpected_root_keys = set(synchronized_root) - supported_root_keys
    if unexpected_root_keys:
        raise ValueError(f"Unsupported synchronized root metadata: {sorted(unexpected_root_keys)}")

    phases = _references(target.get("buildPhases"), "application build phase")
    source_phases = []
    for reference in phases:
        phase = objects.get(reference)
        if not isinstance(phase, dict) or not isinstance(phase.get("isa"), str):
            raise ValueError("Missing or dangling application build phase reference")
        if phase["isa"] == "PBXSourcesBuildPhase":
            source_phases.append(phase)
    if len(source_phases) != 1:
        raise ValueError("Expected exactly one application sources build phase")
    source_phase = source_phases[0]
    if source_phase.get("files") != []:
        raise ValueError("Unsupported explicit application source build entries")
    if str(source_phase.get("buildActionMask")) != "2147483647" or str(
        source_phase.get("runOnlyForDeploymentPostprocessing")
    ) != "0":
        raise ValueError("Unsupported application sources build phase activation")
    if target.get("buildRules") != []:
        raise ValueError("Unsupported application source build rules")

    relative_sources = [PurePosixPath(path).relative_to("lara") for path in APP_VALIDATION_RELATIVE_PATHS]
    exceptions = _references(synchronized_root.get("exceptions", []), "membership exception", allow_empty=True)
    for reference in exceptions:
        exception = _object(
            objects, reference, "PBXFileSystemSynchronizedBuildFileExceptionSet", "membership exception"
        )
        if set(exception) - {"isa", "target", "membershipExceptions"}:
            raise ValueError("Unsupported membership exception metadata")
        if exception.get("target") != target_reference:
            raise ValueError("Unsupported membership exception target")
        memberships = exception.get("membershipExceptions")
        if not isinstance(memberships, list):
            raise ValueError("Unsupported membership exception paths")
        for membership in memberships:
            excluded_path = _exception_path(membership)
            for source in relative_sources:
                if source == excluded_path or excluded_path in source.parents:
                    raise ValueError(f"Required validation source is excluded: {source} by {membership}")

    configurations = {
        "project": _configurations(objects, project_object, "project"),
        "target": _configurations(objects, target, "target"),
    }
    if {item["name"] for item in configurations["project"]} != {
        item["name"] for item in configurations["target"]
    }:
        raise ValueError("Project and application configuration names differ")
    root = _repository_root(repo)
    for relative in APP_VALIDATION_RELATIVE_PATHS:
        _regular_relative_file(root, relative)
    return {
        "target_name": target["name"],
        "product_path": product["path"],
        "synchronized_root": synchronized_root["path"],
        "core_count": len(APP_CORE_RELATIVE_PATHS),
        "adapter_count": len(APP_ADAPTER_RELATIVE_PATHS),
        "service_count": len(APP_SERVICE_RELATIVE_PATHS),
        "source_count": len(APP_VALIDATION_RELATIVE_PATHS),
        "source_paths": list(APP_VALIDATION_RELATIVE_PATHS),
        "configurations": configurations,
    }


def _negative_regressions(project: dict, repo: Path) -> int:
    """Mutate deep copies and temporary empty files, never checkout sources."""
    project = copy.deepcopy(project)
    objects = project["objects"]
    project_reference = project["rootObject"]
    project_object = objects[project_reference]
    target_reference = next(
        reference for reference in project_object["targets"]
        if objects[reference].get("productType") == APPLICATION_PRODUCT_TYPE
    )
    target = objects[target_reference]
    root_reference = target["fileSystemSynchronizedGroups"][0]
    if not objects[root_reference].get("exceptions"):
        # A valid synchronized root can have no exceptions. Add an inert
        # exception only to the in-memory regression fixture in that case.
        fixture_exception = "REGRESSION_EMPTY_EXCEPTION"
        objects[fixture_exception] = {
            "isa": "PBXFileSystemSynchronizedBuildFileExceptionSet",
            "target": target_reference,
            "membershipExceptions": [],
        }
        objects[root_reference]["exceptions"] = [fixture_exception]
    exception_reference = objects[root_reference]["exceptions"][0]
    target_configuration_list = target["buildConfigurationList"]
    target_configuration = objects[target_configuration_list]["buildConfigurations"][0]
    project_configuration_list = project_object["buildConfigurationList"]
    project_configuration = objects[project_configuration_list]["buildConfigurations"][0]
    main_group_reference = project_object["mainGroup"]
    source_phase_reference = next(
        reference for reference in target["buildPhases"] if objects[reference]["isa"] == "PBXSourcesBuildPhase"
    )
    cache_commit = "lara/EagleCore/DockGallery/EagleDockGalleryCacheCommit.swift"
    assert APP_CORE_RELATIVE_PATHS.count(cache_commit) == 1
    source_exception = str(PurePosixPath(cache_commit).relative_to("lara"))
    remove = object()

    def expect_failure(label: str, fixture: dict, fixture_repo: Path, expected: str) -> None:
        try:
            inspect_membership(fixture, fixture_repo)
        except ValueError as error:
            if expected not in str(error):
                raise AssertionError(f"{label}: unexpected failure: {error}") from error
        else:
            raise AssertionError(f"{label}: invalid membership was accepted")

    cases = (
        ("detached target root", ("objects", target_reference, "fileSystemSynchronizedGroups"), [], "Missing attached"),
        ("detached main group root", ("objects", main_group_reference, "children"),
         [reference for reference in objects[main_group_reference]["children"] if reference != root_reference], "detached"),
        ("changed root path", ("objects", root_reference, "path"), "renamed-lara", "root path"),
        ("source membership exception", ("objects", exception_reference, "membershipExceptions"), [source_exception], "source is excluded"),
        ("directory membership exception", ("objects", exception_reference, "membershipExceptions"), ["EagleCore/DockGallery"], "source is excluded"),
        ("core membership exception", ("objects", exception_reference, "membershipExceptions"), ["EagleCore"], "source is excluded"),
        ("adapter directory membership exception", ("objects", exception_reference, "membershipExceptions"), ["EagleAdapters/DockGallery"], "source is excluded"),
        ("adapter membership exception", ("objects", exception_reference, "membershipExceptions"), ["EagleAdapters"], "source is excluded"),
        ("missing exception object", ("objects", exception_reference), remove, "dangling membership exception"),
        ("dangling target configuration", ("objects", target_configuration_list, "buildConfigurations"), ["MISSING_CONFIGURATION"], "dangling target configuration"),
        ("dangling project configuration", ("objects", project_configuration_list, "buildConfigurations"), ["MISSING_CONFIGURATION"], "dangling project configuration"),
        ("external target configuration", ("objects", target_configuration, "baseConfigurationReference"), "EXTERNAL_CONFIG", "external configuration"),
        ("external project configuration", ("objects", project_configuration, "baseConfigurationReference"), "EXTERNAL_CONFIG", "external configuration"),
        ("conditional target exclusion", ("objects", target_configuration, "buildSettings", "EXCLUDED_SOURCE_FILE_NAMES[sdk=iphonesimulator*]"), "Eagle*", "inclusion or exclusion"),
        ("conditional project inclusion", ("objects", project_configuration, "buildSettings", "INCLUDED_SOURCE_FILE_NAMES[arch=arm64]"), "Other.swift", "inclusion or exclusion"),
        ("unsupported explicit file types", ("objects", root_reference, "explicitFileTypes"), {source_exception: "text"}, "root metadata"),
        ("unsupported explicit folders", ("objects", root_reference, "explicitFolders"), ["EagleCore"], "root metadata"),
        ("unsupported exception metadata", ("objects", exception_reference, "platformFilters"), ["ios"], "exception metadata"),
        ("unsupported exception pattern", ("objects", exception_reference, "membershipExceptions"), ["EagleCore/*"], "exception pattern"),
        ("wrong exception target", ("objects", exception_reference, "target"), "OTHER_TARGET", "exception target"),
        ("unsupported explicit sources", ("objects", source_phase_reference, "files"), ["EXPLICIT_SOURCE"], "explicit application source"),
        ("inactive source phase", ("objects", source_phase_reference, "runOnlyForDeploymentPostprocessing"), "1", "phase activation"),
        ("unsupported build rules", ("objects", target_reference, "buildRules"), ["CUSTOM_RULE"], "source build rules"),
    )
    for label, path, value, expected in cases:
        fixture = copy.deepcopy(project)
        container = fixture
        for component in path[:-1]:
            container = container[component]
        if value is remove:
            del container[path[-1]]
        else:
            container[path[-1]] = copy.deepcopy(value)
        expect_failure(label, fixture, repo, expected)
    count = len(cases)

    built_in_theme = "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInTheme.swift"
    media_filter = "lara/EagleCore/DockGallery/EagleDockGalleryMediaFilter.swift"
    favorites = "lara/EagleCore/DockGallery/EagleDockGalleryFavorites.swift"
    collection = "lara/EagleCore/DockGallery/EagleDockGalleryCollection.swift"
    selection = "lara/EagleCore/DockGallery/EagleDockGallerySelection.swift"
    visit_order = "lara/EagleCore/DockGallery/EagleDockGalleryVisitOrder.swift"
    selection_memory = "lara/EagleCore/DockGallery/EagleDockGallerySelectionMemory.swift"
    session = "lara/EagleCore/DockGallery/EagleDockGallerySession.swift"
    apply_flow = "lara/EagleCore/DockGallery/EagleDockGalleryApplyFlow.swift"
    builtin_apply_flow = "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInApplyFlow.swift"
    restore_flow = "lara/EagleCore/DockGallery/EagleDockGalleryRestoreFlow.swift"
    island_catalog = "lara/EagleCore/IslandGallery/EagleIslandGalleryCatalog.swift"
    island_filter = "lara/EagleCore/IslandGallery/EagleIslandGalleryFilter.swift"
    island_favorites = "lara/EagleCore/IslandGallery/EagleIslandGalleryFavorites.swift"
    island_selection = "lara/EagleCore/IslandGallery/EagleIslandGallerySelection.swift"
    island_collection = "lara/EagleCore/IslandGallery/EagleIslandGalleryCollection.swift"
    island_recovery = "lara/EagleCore/IslandGallery/EagleIslandGalleryRecovery.swift"
    island_load = "lara/EagleCore/IslandGallery/EagleIslandGalleryLoadFlow.swift"
    island_actions = "lara/EagleCore/IslandGallery/EagleIslandGalleryActionFlow.swift"
    aura_mode = "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"
    aura_policy = "lara/EagleCore/AuraStudio/EagleAuraStudioModePolicy.swift"
    aura_drafts = "lara/EagleCore/AuraStudio/EagleAuraStudioDraftModes.swift"
    aura_colors = "lara/EagleCore/AuraStudio/EagleAuraStudioColors.swift"
    aura_profiles = "lara/EagleCore/AuraStudio/EagleAuraStudioProfileState.swift"
    aura_status = "lara/EagleCore/AuraStudio/EagleAuraStudioProfileStatus.swift"
    aura_reconciliation = "lara/EagleCore/AuraStudio/EagleAuraStudioReconciliation.swift"
    aura_entry = "lara/EagleCore/AuraStudio/EagleAuraStudioEntryFlow.swift"
    aura_operation_ui = "lara/EagleCore/AuraStudio/EagleAuraStudioOperationUI.swift"
    aura_feedback = "lara/EagleCore/AuraStudio/EagleAuraStudioResultFeedback.swift"
    aura_completion = "lara/EagleCore/AuraStudio/EagleAuraStudioCompletion.swift"
    aura_preflight = "lara/EagleCore/AuraStudio/EagleAuraStudioPreflightFailure.swift"
    aura_rollback = "lara/EagleCore/AuraStudio/EagleAuraStudioVerifiedRollback.swift"
    aura_unverified = "lara/EagleCore/AuraStudio/EagleAuraStudioUnverifiedFailure.swift"
    aura_report = "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticsReport.swift"
    aura_plan = "lara/EagleCore/AuraStudio/EagleAuraStudioOperationPlan.swift"
    aura_preview = "lara/EagleCore/AuraStudio/EagleAuraStudioPreview.swift"
    aura_capability = "lara/EagleCore/AuraStudio/EagleAuraStudioCapability.swift"
    aura_target = "lara/EagleCore/AuraStudio/EagleAuraStudioTarget.swift"
    aura_diagnostic_text = "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticsPresentation.swift"
    aura_diagnostic_log = "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticLog.swift"
    aura_color_presentation = "lara/EagleCore/AuraStudio/EagleAuraStudioColorPresentation.swift"
    assert APP_CORE_RELATIVE_PATHS.count(built_in_theme) == 1
    assert APP_CORE_RELATIVE_PATHS.count(media_filter) == 1
    assert APP_CORE_RELATIVE_PATHS.count(favorites) == 1
    assert APP_CORE_RELATIVE_PATHS.count(collection) == 1
    assert APP_CORE_RELATIVE_PATHS.count(selection) == 1
    assert APP_CORE_RELATIVE_PATHS.count(visit_order) == 1
    assert APP_CORE_RELATIVE_PATHS.count(selection_memory) == 1
    assert APP_CORE_RELATIVE_PATHS.count(session) == 1
    assert APP_CORE_RELATIVE_PATHS.count(apply_flow) == 1
    assert APP_CORE_RELATIVE_PATHS.count(builtin_apply_flow) == 1
    assert APP_CORE_RELATIVE_PATHS.count(restore_flow) == 1
    assert APP_CORE_RELATIVE_PATHS.count(island_catalog) == 1
    assert APP_CORE_RELATIVE_PATHS.count(island_filter) == 1
    assert APP_CORE_RELATIVE_PATHS.count(island_favorites) == 1
    assert APP_CORE_RELATIVE_PATHS.count(island_selection) == 1
    assert APP_CORE_RELATIVE_PATHS.count(island_collection) == 1
    assert APP_CORE_RELATIVE_PATHS.count(island_recovery) == 1
    assert APP_CORE_RELATIVE_PATHS.count(island_load) == 1
    assert APP_CORE_RELATIVE_PATHS.count(island_actions) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_mode) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_policy) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_drafts) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_colors) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_profiles) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_status) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_reconciliation) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_entry) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_operation_ui) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_feedback) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_completion) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_preflight) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_rollback) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_unverified) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_report) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_plan) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_preview) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_capability) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_target) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_diagnostic_text) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_diagnostic_log) == 1
    assert APP_CORE_RELATIVE_PATHS.count(aura_color_presentation) == 1
    for relative in (*APP_ADAPTER_RELATIVE_PATHS, *APP_SERVICE_RELATIVE_PATHS, built_in_theme, media_filter, favorites, collection, selection, visit_order, selection_memory, session, apply_flow, builtin_apply_flow, restore_flow, island_catalog, island_filter, island_favorites, island_selection, island_collection, island_recovery, island_load, island_actions, aura_mode, aura_policy, aura_drafts, aura_colors, aura_profiles, aura_status, aura_reconciliation, aura_entry, aura_operation_ui, aura_feedback, aura_completion, aura_preflight, aura_rollback, aura_unverified, aura_report, aura_plan, aura_preview, aura_capability, aura_target, aura_diagnostic_text, aura_diagnostic_log, aura_color_presentation,
                     "lara/EagleCore/AuraStudio/EagleAuraStudioApplyGate.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioNativeContract.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioDisplayGeometry.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioRequestAdmission.swift",
                     "lara/EagleCore/Gallery/EagleGalleryPosition.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioRequestPreparation.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioSessionAdmission.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioResultAdmission.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioStepProgress.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioStepFlow.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioResultConsumption.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioRequestCapture.swift",
                     "lara/EagleCore/AuraStudio/EagleAuraStudioProgressSchedule.swift"):
        fixture = copy.deepcopy(project)
        source_path_exception = str(PurePosixPath(relative).relative_to("lara"))
        fixture["objects"][exception_reference]["membershipExceptions"] = [source_path_exception]
        expect_failure(f"validation source membership exception: {relative}", fixture, repo, "source is excluded")
        count += 1

    fixture = copy.deepcopy(project)
    duplicate_reference = "REGRESSION_DUPLICATE_APPLICATION"
    fixture["objects"][duplicate_reference] = copy.deepcopy(target)
    fixture["objects"][project_reference]["targets"].append(duplicate_reference)
    expect_failure("multiple application targets", fixture, repo, "exactly one application target")
    count += 1

    with tempfile.TemporaryDirectory(prefix="eagle-core-membership-") as temporary:
        for kind, missing_relative in (
            ("core", cache_commit),
            ("core-built-in-theme", built_in_theme),
            ("core-media-filter", media_filter),
            ("core-favorites", favorites),
            ("core-collection", collection),
            ("core-selection", selection),
            ("core-visit-order", visit_order),
            ("core-selection-memory", selection_memory),
            ("core-session", session),
            ("core-apply-flow", apply_flow),
            ("core-builtin-apply-flow", builtin_apply_flow),
            ("core-restore-flow", restore_flow),
            ("core-island-catalog", island_catalog),
            ("core-island-filter", island_filter),
            ("core-island-favorites", island_favorites),
            ("core-island-selection", island_selection),
            ("core-island-collection", island_collection),
            ("core-island-recovery", island_recovery),
            ("core-island-load", island_load),
            ("core-island-actions", island_actions),
            ("core-aura-mode", aura_mode),
            ("core-aura-policy", aura_policy),
            ("core-aura-drafts", aura_drafts),
            ("core-aura-colors", aura_colors),
            ("core-aura-profiles", aura_profiles),
            ("core-aura-status", aura_status),
            ("core-aura-reconciliation", aura_reconciliation),
            ("core-aura-entry", aura_entry),
            ("core-aura-operation-ui", aura_operation_ui),
            ("core-aura-feedback", aura_feedback),
            ("core-aura-completion", aura_completion),
            ("core-aura-preflight", aura_preflight),
            ("core-aura-rollback", aura_rollback),
            ("core-aura-unverified", aura_unverified),
            ("core-aura-report", aura_report),
            ("core-aura-plan", aura_plan),
            ("core-aura-preview", aura_preview),
            ("core-aura-capability", aura_capability),
            ("core-aura-target", aura_target),
            ("core-aura-diagnostic-text", aura_diagnostic_text),
            ("core-aura-diagnostic-log", aura_diagnostic_log),
            ("core-aura-color-presentation", aura_color_presentation),
            *((f"adapter-{index}", relative) for index, relative in enumerate(APP_ADAPTER_RELATIVE_PATHS)),
            *((f"service-{index}", relative) for index, relative in enumerate(APP_SERVICE_RELATIVE_PATHS)),
        ):
            fixture_repo = Path(temporary) / kind
            for relative in APP_VALIDATION_RELATIVE_PATHS:
                if relative == missing_relative:
                    continue
                source = fixture_repo / relative
                source.parent.mkdir(parents=True, exist_ok=True)
                source.touch()
            missing_source = fixture_repo / missing_relative
            missing_source.parent.mkdir(parents=True, exist_ok=True)
            expect_failure(f"missing {kind} source file", copy.deepcopy(project), fixture_repo, "file or parent is missing")
            count += 1
            missing_source.symlink_to(fixture_repo / APP_VALIDATION_RELATIVE_PATHS[0])
            expect_failure(f"symbolic link {kind} source", copy.deepcopy(project), fixture_repo, "symbolic link")
            count += 1
    with tempfile.TemporaryDirectory(prefix="eagle-core-membership-parent-") as temporary:
        for directory in ("EagleCore", "EagleAdapters", "EagleServices"):
            fixture_repo = Path(temporary) / directory
            for relative in APP_VALIDATION_RELATIVE_PATHS:
                if PurePosixPath(relative).parts[1] == directory:
                    continue
                source = fixture_repo / relative
                source.parent.mkdir(parents=True, exist_ok=True)
                source.touch()
            outside = fixture_repo / "source-fixture"
            outside.mkdir()
            (fixture_repo / "lara" / directory).symlink_to(outside, target_is_directory=True)
            expect_failure(f"symbolic link {directory} source parent", copy.deepcopy(project), fixture_repo, "symbolic link")
            count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    arguments = parser.parse_args()
    try:
        project = load_project(arguments.repo)
        membership = inspect_membership(project, arguments.repo)
        regression_count = _negative_regressions(project, arguments.repo)
    except (ValueError, AssertionError) as error:
        parser.exit(1, f"Eagle validation project membership failed: {error}\n")
    names = ", ".join(item["name"] for item in membership["configurations"]["target"])
    print(
        f"PASS: {membership['source_count']} approved sources "
        f"({membership['core_count']} Core, {membership['adapter_count']} adapters, "
        f"{membership['service_count']} app services) belong to "
        f"{membership['target_name']} ({membership['product_path']}) through synchronized "
        f"root {membership['synchronized_root']}; configurations: {names}."
    )
    print(f"PASS: {regression_count} invalid membership and filesystem cases were rejected.")


if __name__ == "__main__":
    main()
