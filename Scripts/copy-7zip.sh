#!/bin/sh
set -eu
project_dir="${SRCROOT:?}"
helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
resource_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$helper_dir"
# Remove the legacy non-localized About text from incremental build products.
rm -f "$resource_dir/Credits.rtf"
for language in en de; do
    mkdir -p "$resource_dir/$language.lproj"
    cp "$project_dir/Sources/YA7/Resources/$language.lproj/Localizable.strings" "$resource_dir/$language.lproj/Localizable.strings"
    cp "$project_dir/Bundle/Localization/$language.lproj/InfoPlist-$PRODUCT_NAME.strings" "$resource_dir/$language.lproj/InfoPlist.strings"
    cp "$project_dir/Bundle/Localization/$language.lproj/Credits.rtf" "$resource_dir/$language.lproj/Credits.rtf"
done
cp "$project_dir/Vendor/7zip/7zz" "$helper_dir/7zz"
cp "$project_dir/Vendor/7zip/License.txt" "$resource_dir/7zip-Lizenz.txt"
mkdir -p "$resource_dir/Legal"
cp "$project_dir/LICENSE" "$resource_dir/Legal/YA7-License.txt"
cp "$project_dir/LICENSING.md" "$resource_dir/Legal/YA7-Licensing.md"
cp "$project_dir/ThirdParty/NOTICE.txt" "$resource_dir/Legal/NOTICE.txt"
cp "$project_dir/ThirdParty/LGPL-2.1.txt" "$resource_dir/Legal/LGPL-2.1.txt"
cp "$project_dir/Vendor/7zip/License.txt" "$resource_dir/Legal/7zip-License.txt"
if [ "$WRAPPER_EXTENSION" = app ]; then
    cp "$project_dir/Vendor/7zip/7z2605-src.tar.xz" "$resource_dir/Legal/7z2605-src.tar.xz"
    cp "$project_dir/Vendor/7zip/Source-Provenance.json" "$resource_dir/Legal/Source-Provenance.json"
fi
if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    if [ -z "$signing_identity" ]; then signing_identity=-; fi
    timestamp_option=--timestamp
    if [ "$signing_identity" = - ]; then timestamp_option=--timestamp=none; fi
    if [ "$WRAPPER_EXTENSION" = appex ]; then
        codesign --force --sign "$signing_identity" --options runtime "$timestamp_option" --entitlements "$project_dir/Bundle/Helper.entitlements" "$helper_dir/7zz"
    else
        codesign --force --sign "$signing_identity" --options runtime "$timestamp_option" "$helper_dir/7zz"
    fi
fi
