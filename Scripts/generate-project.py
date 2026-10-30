"""Generate the committed, macOS-only Xcode project without third-party tools."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile
import plistlib

ROOT = Path(__file__).resolve().parent.parent
# The Swift catalog is the source of truth for menus, recognition and Finder types.
with tempfile.TemporaryDirectory(prefix='ya7-formats-') as tmp:
    exporter = str(Path(tmp) / 'export-formats')
    subprocess.run(['swiftc', str(ROOT/'Sources/YA7/ArchiveFormat.swift'), str(ROOT/'Scripts/ExportArchiveFormats.swift'), '-o', exporter], check=True)
    formats = json.loads(subprocess.check_output([exporter]))
imports = []
for row in formats:
    for ext, identifier in zip(row['extensions'], row['types']):
        imports.append({'UTTypeIdentifier': identifier, 'UTTypeDescription': row['title'],
                        'UTTypeConformsTo': ['public.data', 'public.archive'],
                        'UTTypeTagSpecification': {'public.filename-extension': [ext]}})
# Merge aliases of the same UTI instead of declaring a type more than once.
merged = {}
for item in imports:
    identifier = item['UTTypeIdentifier']
    if identifier not in merged: merged[identifier] = item
    else: merged[identifier]['UTTypeTagSpecification']['public.filename-extension'] += item['UTTypeTagSpecification']['public.filename-extension']
for file in ['Info.plist', 'ExtractAction-Info.plist', 'CheckAction-Info.plist']:
    path = ROOT/'Bundle'/file
    info = plistlib.loads(path.read_bytes())
    info['UTImportedTypeDeclarations'] = list(merged.values())
    if file != 'Info.plist':
        conditions = ' OR '.join('ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "' + identifier + '"' for identifier in merged)
        info['NSExtension']['NSExtensionAttributes']['NSExtensionActivationRule'] = 'SUBQUERY(extensionItems, $extensionItem, $extensionItem.attachments.@count == 1 AND SUBQUERY($extensionItem.attachments, $attachment, (' + conditions + ')).@count == $extensionItem.attachments.@count).@count == 1'
    path.write_bytes(plistlib.dumps(info, sort_keys=False))
objects = {}

def uid(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()

def obj(label, isa, **values):
    key = uid(label)
    objects[key] = dict(isa=isa, **values)
    return key

def configuration_list(label, settings):
    configs = []
    for name in ('Debug', 'Release'):
        options = dict(settings)
        if name == 'Debug':
            options.update(SWIFT_OPTIMIZATION_LEVEL='-Onone', ENABLE_TESTABILITY='YES', DEBUG_INFORMATION_FORMAT='dwarf')
        else:
            options.update(SWIFT_OPTIMIZATION_LEVEL='-O', DEBUG_INFORMATION_FORMAT='dwarf', CODE_SIGN_INJECT_BASE_ENTITLEMENTS='NO')
        configs.append(obj(label + name, 'XCBuildConfiguration', name=name, buildSettings=options))
    return obj(label + 'configs', 'XCConfigurationList', buildConfigurations=configs,
               defaultConfigurationIsVisible='0', defaultConfigurationName='Release')

files = {}
source_paths = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Sources/YA7').glob('*.swift'))
source_paths += ['Extensions/QuickActionViewController.swift', 'Tests/YA7Tests/ArchiveEngineTests.swift']
other_paths = ['Bundle/Info.plist', 'Bundle/Credits.rtf', 'Bundle/YA7.icns', 'Bundle/QuickAction.entitlements', 'Bundle/Helper.entitlements']
other_paths += [f'Bundle/{name}-Info.plist' for name in ('PackAction', 'ExtractAction', 'CheckAction')]
other_paths += ['Bundle/ActionIcons.xcassets']
other_paths += ['Scripts/build-dmg.sh', 'Scripts/copy-7zip.sh', 'Scripts/register-finder-actions.sh', 'Scripts/GenerateQuickActionIcons.swift', 'build-app.sh', 'README.md', 'NOTARISIERUNG.md', 'Vendor/7zip/License.txt', 'ThirdParty/NOTICE.txt', 'ThirdParty/LGPL-2.1.txt', 'Vendor/7zip/Source-Provenance.json', 'Vendor/7zip/7z2605-src.tar.xz', 'Scripts/verify-release.py', 'Scripts/notarize.sh', 'Scripts/ExportArchiveFormats.swift', 'Tests/YA7Tests/Fixtures']
for path in source_paths + other_paths:
    kind = 'folder' if path.endswith('/Fixtures') else 'sourcecode.swift' if path.endswith('.swift') else 'folder.assetcatalog' if path.endswith('.xcassets') else 'image.icns' if path.endswith('.icns') else 'image.png' if path.endswith('.png') else 'text.plist.xml' if path.endswith(('.plist', '.entitlements')) else 'text'
    files[path] = obj('file:'+path, 'PBXFileReference', path=path, sourceTree='<group>', lastKnownFileType=kind)

source_group = obj('sources', 'PBXGroup', name='Swift-Quellen', children=[files[x] for x in source_paths], sourceTree='<group>')
config_group = obj('configuration', 'PBXGroup', name='Konfiguration und Ressourcen', children=[files[x] for x in other_paths], sourceTree='<group>')
products = []
targets = []
target_ids = {name: uid('target:'+name) for name in ('YA7', 'PackAction', 'ExtractAction', 'CheckAction', 'YA7Tests')}
shared = ['ArchiveEntry.swift', 'ArchiveEngine.swift', 'SharedControls.swift', 'FinderAction.swift', 'ArchiveFormat.swift']
extension_sources = ['Sources/YA7/'+x for x in shared] + ['Extensions/QuickActionViewController.swift']

for name in target_ids:
    app = name == 'YA7'
    test = name == 'YA7Tests'
    extension = not app and not test
    suffix = 'app' if app else 'xctest' if test else 'appex'
    product_type = 'application' if app else 'bundle.unit-test' if test else 'app-extension'
    file_type = 'wrapper.application' if app else 'wrapper.cfbundle' if test else 'wrapper.app-extension'
    product = obj('product:'+name, 'PBXFileReference', path=name+'.'+suffix, explicitFileType=file_type, sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    paths = [x for x in source_paths if x.startswith('Sources/')] if app else ['Tests/YA7Tests/ArchiveEngineTests.swift'] if test else extension_sources
    build_files = [obj('build:'+name+':'+p, 'PBXBuildFile', fileRef=files[p]) for p in paths]
    phases = [obj(name+'sources', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=build_files, runOnlyForDeploymentPostprocessing='0')]
    phases.append(obj(name+'frameworks', 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[], runOnlyForDeploymentPostprocessing='0'))
    resources = [obj(name+'icons', 'PBXBuildFile', fileRef=files['Bundle/ActionIcons.xcassets']),
                 obj(name+'bundleicon', 'PBXBuildFile', fileRef=files['Bundle/YA7.icns'])] if extension else []
    if test:
        resources = [obj(name+'fixtures', 'PBXBuildFile', fileRef=files['Tests/YA7Tests/Fixtures'])]
    if app:
        resources = [obj(name+'credits', 'PBXBuildFile', fileRef=files['Bundle/Credits.rtf']),
                     obj(name+'appicon', 'PBXBuildFile', fileRef=files['Bundle/YA7.icns'])]
    phases.append(obj(name+'resources', 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=resources, runOnlyForDeploymentPostprocessing='0'))
    dependencies = []
    if app:
        embed = []
        for child in ('PackAction', 'ExtractAction', 'CheckAction'):
            embed.append(obj('embed:'+child, 'PBXBuildFile', fileRef=uid('product:'+child), settings={'ATTRIBUTES':['CodeSignOnCopy','RemoveHeadersOnCopy']}))
            proxy = obj('proxy:'+child, 'PBXContainerItemProxy', containerPortal=uid('project'), proxyType='1', remoteGlobalIDString=target_ids[child], remoteInfo=child)
            dependencies.append(obj('dep:'+child, 'PBXTargetDependency', target=target_ids[child], targetProxy=proxy))
        phases.append(obj('embed', 'PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath='', dstSubfolderSpec='13', files=embed, name='Finder-Schnellaktionen einbetten', runOnlyForDeploymentPostprocessing='0'))
    if not test:
        phases.append(obj(name+'7zip', 'PBXShellScriptBuildPhase', buildActionMask='2147483647', files=[],
            inputPaths=['$(SRCROOT)/Vendor/7zip/7zz', '$(SRCROOT)/Vendor/7zip/License.txt', '$(SRCROOT)/Scripts/copy-7zip.sh', '$(SRCROOT)/Bundle/Helper.entitlements', '$(SRCROOT)/ThirdParty/NOTICE.txt', '$(SRCROOT)/ThirdParty/LGPL-2.1.txt', '$(SRCROOT)/Vendor/7zip/Source-Provenance.json', '$(SRCROOT)/Vendor/7zip/7z2605-src.tar.xz'],
            outputPaths=['$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/7zz', '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/7zip-Lizenz.txt', '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Legal/NOTICE.txt', '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Legal/LGPL-2.1.txt', '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Legal/7zip-License.txt'] + (['$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Legal/7z2605-src.tar.xz', '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Legal/Source-Provenance.json'] if app else []),
            name='7-Zip einbetten und lokal signieren', shellPath='/bin/sh', shellScript='"$SRCROOT/Scripts/copy-7zip.sh"', runOnlyForDeploymentPostprocessing='0'))
    settings = dict(PRODUCT_NAME=name, PRODUCT_MODULE_NAME=name, SWIFT_VERSION='5.0', MACOSX_DEPLOYMENT_TARGET='14.0',
        SDKROOT='macosx', SUPPORTED_PLATFORMS='macosx', CODE_SIGN_STYLE='Manual', CODE_SIGN_IDENTITY='-',
        DEVELOPMENT_TEAM='', ENABLE_USER_SCRIPT_SANDBOXING='NO', ENABLE_HARDENED_RUNTIME='YES',
        COMBINE_HIDPI_IMAGES='YES', ENABLE_DEBUG_DYLIB='NO', LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/../Frameworks'])
    if app:
        settings.update(INFOPLIST_FILE='Bundle/Info.plist', PRODUCT_BUNDLE_IDENTIFIER='de.local.archiv.prototype', ENABLE_APP_SANDBOX='NO')
    elif test:
        settings.update(GENERATE_INFOPLIST_FILE='YES', PRODUCT_BUNDLE_IDENTIFIER='de.local.archiv.prototype.tests',
            TEST_HOST='$(BUILT_PRODUCTS_DIR)/YA7.app/Contents/MacOS/YA7', BUNDLE_LOADER='$(TEST_HOST)')
        proxy = obj('test-proxy', 'PBXContainerItemProxy', containerPortal=uid('project'), proxyType='1', remoteGlobalIDString=target_ids['YA7'], remoteInfo='YA7')
        dependencies.append(obj('test-dep', 'PBXTargetDependency', target=target_ids['YA7'], targetProxy=proxy))
    else:
        action = {'PackAction':'pack','ExtractAction':'extract','CheckAction':'check'}[name]
        settings.update(INFOPLIST_FILE=f'Bundle/{name}-Info.plist', PRODUCT_BUNDLE_IDENTIFIER='de.local.archiv.prototype.'+action,
            CODE_SIGN_ENTITLEMENTS='Bundle/QuickAction.entitlements', APPLICATION_EXTENSION_API_ONLY='YES',
            ENABLE_APP_SANDBOX='YES', SKIP_INSTALL='YES', OTHER_LDFLAGS=['$(inherited)','-e','_NSExtensionMain'],
            LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks','@executable_path/../../../../Frameworks'])
    target = obj('target:'+name, 'PBXNativeTarget', name=name, productName=name,
        productReference=product, productType='com.apple.product-type.'+product_type,
        buildConfigurationList=configuration_list(name,settings), buildPhases=phases, buildRules=[], dependencies=dependencies)
    targets.append(target)

product_group = obj('products', 'PBXGroup', name='Products', children=products, sourceTree='<group>')
main_group = obj('main', 'PBXGroup', children=[source_group,config_group,product_group], sourceTree='<group>')
project = obj('project', 'PBXProject', attributes={'LastUpgradeCheck':'1600','BuildIndependentTargetsInParallel':'YES'},
    buildConfigurationList=configuration_list('project',{'CLANG_ENABLE_MODULES':'YES','MACOSX_DEPLOYMENT_TARGET':'14.0'}),
    compatibilityVersion='Xcode 14.0', developmentRegion='de', knownRegions=['de','Base'], mainGroup=main_group,
    productRefGroup=product_group, projectDirPath='', projectRoot='', targets=targets)

def encode(value, indent=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t'*(indent+1)+json.dumps(k)+' = '+encode(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
    if isinstance(value,list):
        return '(\n'+''.join('\t'*(indent+1)+encode(x,indent+1)+',\n' for x in value)+'\t'*indent+')'
    return json.dumps(value, ensure_ascii=False)

project_path=ROOT/'YA7.xcodeproj'
project_path.mkdir(exist_ok=True)
(project_path/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project})+'\n')
schemes=project_path/'xcshareddata/xcschemes'
schemes.mkdir(parents=True,exist_ok=True)
def reference(name):
    suffix='xctest' if name=='YA7Tests' else 'app' if name=='YA7' else 'appex'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids[name]}" BuildableName="{name}.{suffix}" BlueprintName="{name}" ReferencedContainer="container:YA7.xcodeproj"/>'
for name in ('YA7','PackAction','ExtractAction','CheckAction'):
    entries=''.join(f'<BuildActionEntry buildForTesting="YES" buildForRunning="{"NO" if x == "YA7Tests" else "YES"}" buildForProfiling="{"NO" if x == "YA7Tests" else "YES"}" buildForArchiving="{"NO" if x == "YA7Tests" else "YES"}" buildForAnalyzing="{"NO" if x == "YA7Tests" else "YES"}">{reference(x)}</BuildActionEntry>' for x in (['YA7','YA7Tests'] if name=='YA7' else ['YA7',name]))
    launch=f'<BuildableProductRunnable runnableDebuggingMode="0">{reference("YA7")}</BuildableProductRunnable>' if name=='YA7' else '<RemoteRunnable runnableDebuggingMode="2" BundleIdentifier="com.apple.finder" RemotePath="/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"/>'
    xml=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>{entries}</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference('YA7Tests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="YES" debugDocumentVersioning="YES" allowLocationSimulation="NO">{launch}</LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('YA7')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
    (schemes/(name+'.xcscheme')).write_text(xml)
print(project_path)
