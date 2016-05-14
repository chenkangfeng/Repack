#!/bin/sh

#################### 配置 ####################

#p12文件
P12_NAME="app.p12"
#p12文件密码
P12_PWD=""
#证书
PROVISION="app.mobileprovision"

if [ $# -ne 2 ]; then
    echo "Usage: $BASH_SOURCE [-p app] [-r ipa]" && exit
fi

while getopts "p:r:" OPTION
do
    case "$OPTION" in
        "p")
            APP_NAME="$OPTARG"
            if [ ! -d $APP_NAME ]; then
                echo "$APP_NAME not exist" && exit
            fi
            IPA_NAME="${APP_NAME%.*}.ipa"
            NEED_UNZIP=false;;
        "r")
            IPA_NAME="$OPTARG"
            if [ ! -f $IPA_NAME ]; then
                echo "$IPA_NAME not exist" && exit
            fi
            APP_NAME="${IPA_NAME%.*}.app"
            NEED_UNZIP=true;;
        "?")
            echo "\033[1A\033[K\c"
            echo "Usage: $BASH_SOURCE [-p app] [-r ipa]" && exit;;
    esac
done

#################### 运行 ####################

#初始化
SCRIPT_PATH=$(cd $(dirname $BASH_SOURCE); pwd)
OUTPUT_PATH="$SCRIPT_PATH/Package"
cd $SCRIPT_PATH

if [ -d $OUTPUT_PATH ]; then
    rm -rf $OUTPUT_PATH
fi
mkdir $OUTPUT_PATH
if $NEED_UNZIP; then
    unzip -o "$IPA_NAME" -d "$OUTPUT_PATH/" > /dev/null
    #rm -rf "$IPA_NAME"
else
    mkdir "$OUTPUT_PATH/Payload"
    cp -rf "$APP_NAME" "$OUTPUT_PATH/Payload/" > /dev/null
fi

#导入签名
security create-keychain -p "$APP_NAME" "$APP_NAME.keychain"
security unlock-keychain -p "$APP_NAME" "$APP_NAME.keychain"
security import "$P12_NAME" -k "$APP_NAME.keychain" -P "$P12_PWD" -T /usr/bin/codesign

#初始化信息
CERT=$(security find-identity -p codesigning $APP_NAME.keychain | egrep "iPhone.*[^\"]" -o | tail -1)
PREFIX=$(echo $CERT | egrep "[(].*[^)]" -o | cut -b 2-)
BUNDLE=$(cat $PROVISION | egrep -A1 -a "application-identifier" | egrep "$PREFIX[.|-|0-9|a-z|A-Z]*" -o)
echo "\033[31m$CERT\n$BUNDLE\033[0m"

#替换Bundle
INFO_PLIST=$(ls "$OUTPUT_PATH/Payload/$APP_NAME/*Info.plist")
plutil -convert xml1 "$INFO_PLIST"
OLD_BUNDLE=$(cat "$INFO_PLIST" | egrep -A1 -a "CFBundleIdentifier" | egrep "<string>.[^<]*" -o | cut -b 9-)
sed -i "" "s/$OLD_BUNDLE/$BUNDLE/g" "$INFO_PLIST"

#生成xcent
cat > "$OUTPUT_PATH/$APP_NAME.xcent" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>$BUNDLE</string>
    <key>com.apple.developer.team-identifier</key>
    <string>$PREFIX</string>
    <key>get-task-allow</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$BUNDLE</string>
    </array>
</dict>
</plist>
EOF
plutil -convert binary1 "$OUTPUT_PATH/$APP_NAME.xcent"

#生成plist
cat > "$OUTPUT_PATH/ResourceRules.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>rules</key>
    <dict>
        <key>.*</key>
        <true/>
        <key>^Info.plist$</key>
        <dict>
            <key>omit</key>
            <true/>
            <key>weight</key>
            <real>10</real>
        </dict>
        <key>^ResourceRules.plist$</key>
        <dict>
            <key>omit</key>
            <true/>
            <key>weight</key>
            <real>100</real>
        </dict>
    </dict>
</dict>
</plist>
EOF
plutil -convert binary1 "$OUTPUT_PATH/ResourceRules.plist"

#替换证书
rm -rf "$OUTPUT_PATH/Payload/$APP_NAME/_CodeSignature"
rm -rf "$OUTPUT_PATH/Payload/$APP_NAME/embedded.mobileprovision"
cp "$PROVISION" "$OUTPUT_PATH/Payload/$APP_NAME/embedded.mobileprovision"
cp "$OUTPUT_PATH/ResourceRules.plist" "$OUTPUT_PATH/Payload/$APP_NAME/ResourceRules.plist"

#签名
/usr/bin/codesign --force --sign "$CERT"                                                         \
                  --resource-rules "$OUTPUT_PATH/Payload/$APP_NAME/ResourceRules.plist"          \
                  --entitlements "$OUTPUT_PATH/$APP_NAME.xcent" "$OUTPUT_PATH/Payload/$APP_NAME" \
                  > /dev/null

#打包
/usr/bin/xcrun -sdk iphoneos PackageApplication -v "$OUTPUT_PATH/Payload/$APP_NAME" \
               -o "$OUTPUT_PATH/$IPA_NAME" --sign "$CERT"                           \
               --embed "$OUTPUT_PATH/Payload/$APP_NAME/embedded.mobileprovision"    \
               > /dev/null

#删除签名
security delete-keychain "$APP_NAME.keychain"

#销毁
rm -rf "$OUTPUT_PATH/$APP_NAME.xcent"
rm -rf "$OUTPUT_PATH/ResourceRules.plist"
rm -rf "$OUTPUT_PATH/Payload"
