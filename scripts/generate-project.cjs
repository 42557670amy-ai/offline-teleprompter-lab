// Creates a small, dependency-free Xcode project; no package manager or credentials.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const sources = fs.readdirSync(path.join(root, 'App')).filter(f => f.endsWith('.swift')).sort();
let counter = 1;
const id = () => (counter++).toString(16).toUpperCase().padStart(24, '0');
const projectID = id(), mainGroup = id(), appGroup = id(), productsGroup = id(), target = id(), product = id();
const sourcePhase = id(), frameworkPhase = id(), resourcePhase = id(), projectConfigs = id(), targetConfigs = id();
const debugProject = id(), releaseProject = id(), debugTarget = id(), releaseTarget = id();
const records = [];
const add = (key, body) => records.push(`${key} = { ${body} };`);
const list = ids => `(${ids.join(',')}${ids.length ? ',' : ''})`;
const sourceRefs = [], sourceBuilds = [];
for (const source of sources) {
  const ref = id(), build = id(); sourceRefs.push(ref); sourceBuilds.push(build);
  add(ref, `isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "${source}"; sourceTree = "<group>";`);
  add(build, `isa = PBXBuildFile; fileRef = ${ref};`);
}
const jsRef = id(), jsBuild = id();
add(jsRef, 'isa = PBXFileReference; lastKnownFileType = sourcecode.javascript; path = matcher.js; sourceTree = "<group>";');
add(jsBuild, `isa = PBXBuildFile; fileRef = ${jsRef};`);
add(product, 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PromptLab.app; sourceTree = BUILT_PRODUCTS_DIR;');
add(mainGroup, `isa = PBXGroup; children = ${list([appGroup, productsGroup])}; sourceTree = "<group>";`);
add(appGroup, `isa = PBXGroup; children = ${list([...sourceRefs, jsRef])}; path = App; sourceTree = "<group>";`);
add(productsGroup, `isa = PBXGroup; children = ${list([product])}; name = Products; sourceTree = "<group>";`);
add(sourcePhase, `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ${list(sourceBuilds)}; runOnlyForDeploymentPostprocessing = 0;`);
add(frameworkPhase, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
add(resourcePhase, `isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ${list([jsBuild])}; runOnlyForDeploymentPostprocessing = 0;`);
add(target, `isa = PBXNativeTarget; buildConfigurationList = ${targetConfigs}; buildPhases = ${list([sourcePhase, frameworkPhase, resourcePhase])}; buildRules = (); dependencies = (); name = PromptLab; productName = PromptLab; productReference = ${product}; productType = "com.apple.product-type.application";`);
add(projectID, `isa = PBXProject; attributes = { LastUpgradeCheck = 1600; }; buildConfigurationList = ${projectConfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans",en,Base,); mainGroup = ${mainGroup}; productRefGroup = ${productsGroup}; projectDirPath = ""; projectRoot = ""; targets = ${list([target])};`);
const projectSettings = 'CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;';
const targetSettings = 'PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = org.example.offlinepromptlab; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Info.plist; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)","@executable_path/Frameworks",); SWIFT_STRICT_CONCURRENCY = minimal;';
add(debugProject, `isa = XCBuildConfiguration; buildSettings = { ${projectSettings} SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; }; name = Debug;`);
add(releaseProject, `isa = XCBuildConfiguration; buildSettings = { ${projectSettings} SWIFT_OPTIMIZATION_LEVEL = "-O"; }; name = Release;`);
add(debugTarget, `isa = XCBuildConfiguration; buildSettings = { ${targetSettings} }; name = Debug;`);
add(releaseTarget, `isa = XCBuildConfiguration; buildSettings = { ${targetSettings} }; name = Release;`);
add(projectConfigs, `isa = XCConfigurationList; buildConfigurations = ${list([debugProject, releaseProject])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;`);
add(targetConfigs, `isa = XCConfigurationList; buildConfigurations = ${list([debugTarget, releaseTarget])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;`);
const out = path.join(root, 'PromptLab.xcodeproj');
fs.mkdirSync(path.join(out, 'xcshareddata/xcschemes'), {recursive: true});
fs.writeFileSync(path.join(out, 'project.pbxproj'), `// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n${records.join('\n')}\n}; rootObject = ${projectID}; }\n`);
fs.writeFileSync(path.join(out, 'xcshareddata/xcschemes/PromptLab.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${target}" BuildableName="PromptLab.app" BlueprintName="PromptLab" ReferencedContainer="container:PromptLab.xcodeproj"/>
    </BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${target}" BuildableName="PromptLab.app" BlueprintName="PromptLab" ReferencedContainer="container:PromptLab.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
`);
console.log(`Generated PromptLab.xcodeproj: ${sources.length} Swift files, 1 JS resource, 0 external packages.`);
