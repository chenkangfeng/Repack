#!/bin/sh

SCRIPT_PATH=$(cd $(dirname $BASH_SOURCE); pwd)
cd $SCRIPT_PATH

#################### 配置 ####################

#p12文件
P12_NAME="app.p12"
#p12文件密码
P12_PWD=""
#证书
PROVISION="app.mobileprovision"
#输出路径
OUTPUT_PATH="$SCRIPT_PATH/Package"
#错误信息
ERROR_MESSAGE="Usage:$(basename $BASH_SOURCE) [-p app] [-r ipa]"

if [ $# -ne 2 ]; then
    echo $ERROR_MESSAGE && exit
fi

while getopts ":p:r:o:" OPTION
do
    case "$OPTION" in
        "p")
            APP_NAME="$OPTARG"
            if [ ! -d $APP_NAME ]; then
                echo "$APP_NAME app not exist" && exit
            fi
            WORK_PATH=$(dirname $APP_NAME)
            APP_NAME=$(basename $APP_NAME)
            IPA_NAME="${APP_NAME%.*}.ipa"
            NEED_UNZIP=false;;
        "r")
            IPA_NAME="$OPTARG"
            if [ ! -f $IPA_NAME ]; then
                echo "$IPA_NAME ipa not exist" && exit
            fi
            WORK_PATH=$(dirname $IPA_NAME)
            IPA_NAME=$(basename $IPA_NAME)
            APP_NAME="${IPA_NAME%.*}.app"
            NEED_UNZIP=true;;
        "?")
            echo $ERROR_MESSAGE && exit;;
    esac
done

#################### 运行 ####################

#初始化
if [ -d $OUTPUT_PATH ]; then
    rm -rf $OUTPUT_PATH
fi
mkdir $OUTPUT_PATH
if $NEED_UNZIP; then
    unzip -o "$WORK_PATH/$IPA_NAME" -d "$OUTPUT_PATH/" > /dev/null
    APP_NAME=$(ls $OUTPUT_PATH/Payload)
else
    mkdir "$OUTPUT_PATH/Payload"
    cp -rf "$WORK_PATH/$APP_NAME" "$OUTPUT_PATH/Payload/" > /dev/null
fi

#导入签名
security create-keychain -p "$APP_NAME" "$APP_NAME.keychain"
security unlock-keychain -p "$APP_NAME" "$APP_NAME.keychain"
security import "$P12_NAME" -k "$APP_NAME.keychain" -P "$P12_PWD" -T /usr/bin/codesign

#初始化信息
BUNDLE=$(cat $PROVISION | egrep -A1 -a "application-identifier" | egrep "<string>.[^<]*" -o | cut -b 9-)
PREFIX=${BUNDLE%%.*}
CERT=""
for i in $(seq 1 $(security find-identity -p codesigning $APP_NAME.keychain | egrep "iPhone.*[^\"]" -o | wc -l))
do
    CERT=$(security find-identity -p codesigning $APP_NAME.keychain | egrep "iPhone.*[^\"]" -o | head -$i | tail -1)
    if [ -n $(echo $CERT | egrep "$PREFIX" -o) ]; then
        break
    else
        CERT=""
    fi
done
if [ "$CERT" == "" ]; then
    echo "\033[31mNot found match bundleid in the certificate\033[0m" && exit
else
    echo "\033[31m$CERT\n$BUNDLE\033[0m"
fi

#替换Bundle
INFO_PLIST=$(ls "$OUTPUT_PATH/Payload/$APP_NAME" | egrep ".*Info.plist" -o)
INFO_PLIST="$OUTPUT_PATH/Payload/$APP_NAME/$INFO_PLIST"
plutil -convert xml1 "$INFO_PLIST"
OLD_BUNDLE=$(cat "$INFO_PLIST" | egrep -A1 -a "CFBundleIdentifier" | egrep "<string>.[^<]*" -o | cut -b 9-)
NEW_BUNDLE=${BUNDLE#$PREFIX.}
if [ $OLD_BUNDLE != $NEW_BUNDLE ]; then
    sed -i "" "s/$OLD_BUNDLE/$NEW_BUNDLE/g" "$INFO_PLIST"
    echo "\033[31mOld bundleid $OLD_BUNDLE\nReplace to $NEW_BUNDLE\033[0m"
fi
plutil -convert binary1 "$INFO_PLIST"

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
