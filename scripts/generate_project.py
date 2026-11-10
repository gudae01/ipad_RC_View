#!/usr/bin/env python3
"""Generate a deterministic, dependency-free Xcode project from tracked source folders.

Windows: py -3 scripts/generate_project.py
macOS:   python3 scripts/generate_project.py
Pass --check to verify the checked-in project without writing anything.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def uid(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:24].upper()


def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def generate() -> dict[Path, str]:
    app_sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "RCView").rglob("*.swift"))
    test_sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Tests").rglob("*.swift"))
    project, app, tests = uid("project"), uid("app-target"), uid("test-target")
    objects: list[str] = []

    def obj(key: str, body: str) -> None:
        objects.append(f"\t\t{uid(key)} = {{\n{body}\n\t\t}};")

    def refs(keys: list[str]) -> str:
        return "(\n" + "".join(f"\t\t\t\t{uid(k)},\n" for k in keys) + "\t\t\t)"

    for path in app_sources + test_sources:
        obj("file:" + path, f"\t\t\tisa = PBXFileReference;\n\t\t\tlastKnownFileType = sourcecode.swift;\n\t\t\tpath = {quote(path)};\n\t\t\tsourceTree = SOURCE_ROOT;")
        obj("build:" + path, f"\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = {uid('file:' + path)};")
    for path, kind in [("RCView/Info.plist", "text.plist.xml"), ("RCView/Assets.xcassets", "folder.assetcatalog")]:
        obj("file:" + path, f"\t\t\tisa = PBXFileReference;\n\t\t\tlastKnownFileType = {kind};\n\t\t\tpath = {quote(path)};\n\t\t\tsourceTree = SOURCE_ROOT;")
    obj("build:assets", f"\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = {uid('file:RCView/Assets.xcassets')};")
    for key, path, kind in [("app-product", "RCView.app", "wrapper.application"), ("test-product", "RCViewTests.xctest", "wrapper.cfbundle")]:
        obj(key, f"\t\t\tisa = PBXFileReference;\n\t\t\texplicitFileType = {kind};\n\t\t\tincludeInIndex = 0;\n\t\t\tpath = {path};\n\t\t\tsourceTree = BUILT_PRODUCTS_DIR;")
    obj("root-group", "\t\t\tisa = PBXGroup;\n\t\t\tchildren = " + refs(["app-group", "test-group", "products-group"]) + ';\n\t\t\tsourceTree = "<group>";')
    obj("app-group", "\t\t\tisa = PBXGroup;\n\t\t\tchildren = " + refs(["file:" + p for p in app_sources] + ["file:RCView/Info.plist", "file:RCView/Assets.xcassets"]) + ';\n\t\t\tname = RCView;\n\t\t\tsourceTree = "<group>";')
    obj("test-group", "\t\t\tisa = PBXGroup;\n\t\t\tchildren = " + refs(["file:" + p for p in test_sources]) + ';\n\t\t\tname = Tests;\n\t\t\tsourceTree = "<group>";')
    obj("products-group", "\t\t\tisa = PBXGroup;\n\t\t\tchildren = " + refs(["app-product", "test-product"]) + ';\n\t\t\tname = Products;\n\t\t\tsourceTree = "<group>";')
    for target, sources in [("app", app_sources), ("test", test_sources)]:
        for phase, isa, files in [("sources", "PBXSourcesBuildPhase", ["build:" + p for p in sources]), ("frameworks", "PBXFrameworksBuildPhase", []), ("resources", "PBXResourcesBuildPhase", ["build:assets"] if target == "app" else [])]:
            obj(target + "-" + phase, f"\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = {refs(files)};\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    obj("test-proxy", f"\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {project};\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {app};\n\t\t\tremoteInfo = RCView;")
    obj("test-dependency", f"\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {app};\n\t\t\ttargetProxy = {uid('test-proxy')};")
    for target, name, product_type in [("app", "RCView", "com.apple.product-type.application"), ("test", "RCViewTests", "com.apple.product-type.bundle.unit-test")]:
        obj(target + "-target", f"\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {uid(target + '-config-list')};\n\t\t\tbuildPhases = {refs([target + '-sources', target + '-frameworks', target + '-resources'])};\n\t\t\tbuildRules = ();\n\t\t\tdependencies = {refs(['test-dependency'] if target == 'test' else [])};\n\t\t\tname = {name};\n\t\t\tproductName = {name};\n\t\t\tproductReference = {uid(target + '-product')};\n\t\t\tproductType = {quote(product_type)};")
    obj("project", f"\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = YES;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{app} = {{ CreatedOnToolsVersion = 16.0; }};\n\t\t\t\t\t{tests} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {app}; }};\n\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {uid('project-config-list')};\n\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n\t\t\tdevelopmentRegion = ko;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (ko, en, Base);\n\t\t\tmainGroup = {uid('root-group')};\n\t\t\tproductRefGroup = {uid('products-group')};\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = {refs(['app-target', 'test-target'])};")

    project_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "COPY_PHASE_STRIP": "NO", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
        "SWIFT_STRICT_CONCURRENCY": "minimal", "SWIFT_EMIT_LOC_STRINGS": "YES",
    }
    app_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "4", "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "RCView/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks", "MARKETING_VERSION": "1.2.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.rcview.personal", "PRODUCT_NAME": "$(TARGET_NAME)",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "TARGETED_DEVICE_FAMILY": "2",
    }
    test_settings = {
        "BUNDLE_LOADER": "$(TEST_HOST)", "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.rcview.personal.tests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "TARGETED_DEVICE_FAMILY": "2",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/RCView.app/RCView",
    }
    for owner, settings in [("project", project_settings), ("app", app_settings), ("test", test_settings)]:
        for mode in ["Debug", "Release"]:
            values = dict(settings)
            if owner == "project":
                values.update({"DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O", "ENABLE_TESTABILITY": "YES" if mode == "Debug" else "NO"})
                if mode == "Debug":
                    values.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "ONLY_ACTIVE_ARCH": "YES"})
                else:
                    values["SWIFT_COMPILATION_MODE"] = "wholemodule"
            serialized = "\n".join(f"\t\t\t\t{k} = {quote(v)};" for k, v in sorted(values.items()))
            obj(owner + "-" + mode, f"\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{serialized}\n\t\t\t}};\n\t\t\tname = {mode};")
        obj(owner + "-config-list", f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = {refs([owner + '-Debug', owner + '-Release'])};\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;")

    project_text = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {project};\n}}\n"
    app_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="RCView.app" BlueprintName="RCView" ReferencedContainer="container:RCView.xcodeproj"/>'
    test_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tests}" BuildableName="RCViewTests.xctest" BlueprintName="RCViewTests" ReferencedContainer="container:RCView.xcodeproj"/>'
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO">
    <BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    return {ROOT / "RCView.xcodeproj/project.pbxproj": project_text, ROOT / "RCView.xcodeproj/xcshareddata/xcschemes/RCView.xcscheme": scheme}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for path, content in generate().items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                stale.append(path.relative_to(ROOT).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
            print(f"Generated {path.relative_to(ROOT)}")
    if stale:
        print("Project is out of date. Run: py -3 scripts/generate_project.py")
        print("\n".join(stale))
        return 1
    if args.check:
        print("Project generation is up to date.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
