#!/usr/bin/env python3
"""Add XCTest target to BangumiTracker Xcode project using JSON plist manipulation."""

import json, uuid, hashlib, subprocess

def make_uuid(seed):
    return uuid.UUID(hashlib.md5(seed.encode()).hexdigest()).hex[:24].upper()

# --- Convert pbxproj to JSON ---
subprocess.run([
    'plutil', '-convert', 'json',
    '-o', '/tmp/bangumi_project.json',
    'BangumiTracker.xcodeproj/project.pbxproj'
], check=True)

with open('/tmp/bangumi_project.json') as f:
    data = json.load(f)

objects = data['objects']

# --- Generate UUIDs ---
uuids = {
    'target':      make_uuid('test-target-v2'),
    'configList':  make_uuid('test-config-list-v2'),
    'srcPhase':    make_uuid('test-src-phase-v2'),
    'fwPhase':     make_uuid('test-fw-phase-v2'),
    'resPhase':    make_uuid('test-res-phase-v2'),
    'productRef':  make_uuid('test-product-ref-v2'),
    'debugCfg':    make_uuid('test-debug-cfg-v2'),
    'releaseCfg':  make_uuid('test-release-cfg-v2'),
    'dep':         make_uuid('test-dep-v2'),
    'proxy':       make_uuid('test-proxy-v2'),
    'group':       make_uuid('test-group-v2'),
}

# --- 1. Add Debug build configuration ---
objects[uuids['debugCfg']] = {
    "isa": "XCBuildConfiguration",
    "buildSettings": {
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "Z9PVKSMZVW",
        "GENERATE_INFOPLIST_FILE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "z.zy.BangumiTrackerTests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/BangumiTracker.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/BangumiTracker",
    },
    "name": "Debug",
}

# --- 2. Add Release build configuration ---
objects[uuids['releaseCfg']] = {
    "isa": "XCBuildConfiguration",
    "buildSettings": {
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "Z9PVKSMZVW",
        "GENERATE_INFOPLIST_FILE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "z.zy.BangumiTrackerTests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/BangumiTracker.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/BangumiTracker",
    },
    "name": "Release",
}

# --- 3. Add build phases ---
objects[uuids['srcPhase']] = {
    "isa": "PBXSourcesBuildPhase",
    "buildActionMask": 2147483647,
    "files": [],
    "runOnlyForDeploymentPostprocessing": 0,
}

objects[uuids['fwPhase']] = {
    "isa": "PBXFrameworksBuildPhase",
    "buildActionMask": 2147483647,
    "files": [],
    "runOnlyForDeploymentPostprocessing": 0,
}

objects[uuids['resPhase']] = {
    "isa": "PBXResourcesBuildPhase",
    "buildActionMask": 2147483647,
    "files": [],
    "runOnlyForDeploymentPostprocessing": 0,
}

# --- 4. Add group for test files ---
objects[uuids['group']] = {
    "isa": "PBXGroup",
    "children": [],
    "name": "BangumiTrackerTests",
    "sourceTree": "<group>",
}

# --- 5. Add container item proxy ---
objects[uuids['proxy']] = {
    "isa": "PBXContainerItemProxy",
    "containerPortal": "1A34B0992FDD9FF600CE2C7A",
    "proxyType": 1,
    "remoteGlobalIDString": "1A34B0A02FDD9FF600CE2C7A",
    "remoteInfo": "BangumiTracker",
}

# --- 6. Add target dependency ---
objects[uuids['dep']] = {
    "isa": "PBXTargetDependency",
    "target": "1A34B0A02FDD9FF600CE2C7A",
    "targetProxy": uuids['proxy'],
}

# --- 7. Add native test target ---
objects[uuids['target']] = {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": uuids['configList'],
    "buildPhases": [
        uuids['srcPhase'],
        uuids['fwPhase'],
        uuids['resPhase'],
    ],
    "buildRules": [],
    "dependencies": [uuids['dep']],
    "fileSystemSynchronizedGroups": [uuids['group']],
    "name": "BangumiTrackerTests",
    "productName": "BangumiTrackerTests",
    "productReference": uuids['productRef'],
    "productType": "com.apple.product-type.bundle.unit-test",
}

# --- 8. Add config list for test target ---
objects[uuids['configList']] = {
    "isa": "XCConfigurationList",
    "buildConfigurations": [uuids['debugCfg'], uuids['releaseCfg']],
    "defaultConfigurationIsVisible": 0,
    "defaultConfigurationName": "Release",
}

# --- 9. Add product reference ---
objects[uuids['productRef']] = uuids['productRef']  # placeholder

# --- 10. Add test group to root group children ---
root_group_key = None
for k, v in objects.items():
    if isinstance(v, dict) and v.get('isa') == 'PBXGroup' and 'children' in v and 'sourceTree' in v and v.get('name') is None:
        root_group_key = k
        break

if root_group_key:
    root_children = objects[root_group_key].get('children', [])
    if uuids['group'] not in root_children:
        root_children.insert(2, uuids['group'])  # Insert after the first real entry
        objects[root_group_key]['children'] = root_children

# --- 11. Add product reference to Products group ---
products_group_key = None
for k, v in objects.items():
    if isinstance(v, dict) and v.get('isa') == 'PBXGroup' and v.get('name') == 'Products':
        products_group_key = k
        break

if products_group_key:
    prod_children = objects[products_group_key].get('children', [])
    prod_children.append(uuids['productRef'])
    objects[products_group_key]['children'] = prod_children

# --- 12. Add target to project target list ---
root_object_id = data.get('rootObject')
if root_object_id and root_object_id in objects:
    project_obj = objects[root_object_id]
    targets = project_obj.get('targets', [])
    if uuids['target'] not in targets:
        targets.append(uuids['target'])
        project_obj['targets'] = targets

    # Add target attributes
    target_attrs = project_obj.get('attributes', {}).get('TargetAttributes', {})
    target_attrs[uuids['target']] = {
        "CreatedOnToolsVersion": "26.5",
        "TestTargetID": "1A34B0A02FDD9FF600CE2C7A",
    }
    project_obj.setdefault('attributes', {})['TargetAttributes'] = target_attrs

# --- Write back ---
with open('/tmp/bangumi_project.json', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

# Convert back to ASCII plist format
subprocess.run([
    'plutil', '-convert', 'binary1',
    '-o', '/tmp/project_new.pbxproj',
    '/tmp/bangumi_project.json'
], check=True)

# Try converting back to old-style plist (ASCII)
subprocess.run([
    'plutil', '-convert', 'xml1',
    '-o', 'BangumiTracker.xcodeproj/project.pbxproj',
    '/tmp/bangumi_project.json'
], check=True)

print("✅ Test target added successfully!")
print(f"Target UUID: {uuids['target']}")
print(f"Group UUID: {uuids['group']}")
print(f"Debug config: {uuids['debugCfg']}")
print(f"Release config: {uuids['releaseCfg']}")
