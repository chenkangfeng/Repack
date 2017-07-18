#!/bin/sh

#################### 配置 ####################

#p12文件
P12_NAME="app.p12"
#p12文件密码
P12_PWD="123456"
#证书
PROVISION="app.mobileprovision"
#新Version(不填则使用旧的)
NEW_VERSION=
#新Build(不填则使用旧的)
NEW_BUILD＝

#################### 参数 ####################

RUN_PATH=$(pwd)
SCRIPT_PATH=$(cd $(dirname $BASH_SOURCE); pwd)
cd $SCRIPT_PATH

#使用错误信息
USAGE_ERROR_MESSAGE="Usage:$(basename $BASH_SOURCE) [-p <app>] [-r <ipa>] <output ipa>"

if [ $# -ne 3 ]; then
    echo $USAGE_ERROR_MESSAGE && exit
fi

for i in {1..2}
do
    OPTIND=$i
    OPTFLAG=false
    while getopts ":p:r:" OPTION
    do
        OPTFLAG=true
        case "$OPTION" in
            "p")
                INPUT_APP="$OPTARG"
                if [ ! -d $INPUT_APP ]; then
                    echo "$INPUT_APP app not exist" && exit
                fi
                WORK_PATH=$(dirname $INPUT_APP)
                NEED_UNZIP=false;;
            "r")
                INPUT_IPA="$OPTARG"
                if [ ! -f $INPUT_IPA ]; then
                    echo "$INPUT_IPA ipa not exist" && exit
                fi
                WORK_PATH=$(dirname $INPUT_IPA)
                NEED_UNZIP=true;;
            "?")
                echo $USAGE_ERROR_MESSAGE && exit;;
        esac
    done
    if $OPTFLAG; then
        break
    fi
done

if [ $OPTIND -eq 3 ]; then
    OUTPUT_IPA=$3
elif [ $OPTIND -eq 4 ]; then
    OUTPUT_IPA=$1
else
    echo $USAGE_ERROR_MESSAGE && exit
fi
if [ "$(echo $WORK_PATH | egrep "^[.]")" != "" ]; then
    WORK_PATH=$RUN_PATH/$WORK_PATH
fi
if [ "$(echo $OUTPUT_IPA | egrep "^[/]")" != "" ]; then
    OUTPUT_IPA=$OUTPUT_IPA
elif [ "$(echo $OUTPUT_IPA | egrep "^[.]")" != "" ]; then
    OUTPUT_IPA="$RUN_PATH/$OUTPUT_IPA"
else
    OUTPUT_IPA="$WORK_PATH/$OUTPUT_IPA"
fi
if [ -f $OUTPUT_IPA ]; then
    echo "Already exists same ipa" && exit
fi

#################### 运行 ####################

#初始化
OUTPUT_PATH="$SCRIPT_PATH/Package"
if [ -d $OUTPUT_PATH ]; then
    rm -rf $OUTPUT_PATH
fi
mkdir $OUTPUT_PATH
if $NEED_UNZIP; then
    unzip -o "$INPUT_IPA" -d "$OUTPUT_PATH/" > /dev/null
    APP_NAME=$(ls $OUTPUT_PATH/Payload)
else
    APP_NAME=$(basename $INPUT_APP)
    mkdir "$OUTPUT_PATH/Payload"
    cp -rf "$INPUT_APP" "$OUTPUT_PATH/Payload/" > /dev/null
fi

KEYCHAIN_NAME=$(echo $APP_NAME | tr -d " ")

#导入签名
security create-keychain -p "$KEYCHAIN_NAME" "$KEYCHAIN_NAME.keychain"
security unlock-keychain -p "$KEYCHAIN_NAME" "$KEYCHAIN_NAME.keychain"
security import "$P12_NAME" -k "$KEYCHAIN_NAME.keychain" -P "$P12_PWD" -T /usr/bin/codesign

#初始化信息
BUNDLE=$(security cms -D -i $PROVISION | egrep -A1 -a "application-identifier" | egrep "<string>.[^<]*" -o | cut -b 9-)
PREFIX=${BUNDLE%%.*}
CERT=""
for i in $(seq 1 $(security find-identity -p codesigning $KEYCHAIN_NAME.keychain | egrep "iPhone.*[^\"]" -o | wc -l))
do
    CERT=$(security find-identity -p codesigning $KEYCHAIN_NAME.keychain | egrep "iPhone.*[^\"]" -o | head -$i | tail -1)
    if [ "$(echo $CERT | egrep "$PREFIX")" != "" ]; then
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

INFO_PLIST=$(ls "$OUTPUT_PATH/Payload/$APP_NAME" | egrep ".*Info.plist" -o)
INFO_PLIST="$OUTPUT_PATH/Payload/$APP_NAME/$INFO_PLIST"
plutil -convert xml1 "$INFO_PLIST"

#替换Bundle
OLD_BUNDLE=$(cat "$INFO_PLIST" | egrep -A1 -a "CFBundleIdentifier" | egrep "<string>.[^<]*" -o | cut -b 9-)
NEW_BUNDLE=${BUNDLE#$PREFIX.}
if [ $OLD_BUNDLE != $NEW_BUNDLE ]; then
    sed -i "" "s/$OLD_BUNDLE/$NEW_BUNDLE/g" "$INFO_PLIST"
    echo "\033[31mOld bundleid $OLD_BUNDLE\nReplace to $NEW_BUNDLE\033[0m"
fi

#替换Version
OLD_VERSION=$(cat "$INFO_PLIST" | egrep -A1 -a "CFBundleVersion" | egrep "<string>.[^<]*" -o | cut -b 9-)
OLD_VERSION_LINE=$(cat "$INFO_PLIST" | egrep -n "CFBundleVersion" | cut -d ":" -f 1)
OLD_VERSION_LINE=$[$OLD_VERSION_LINE+1]
if [ $NEW_VERSION ]; then
    if [ $OLD_VERSION != $NEW_VERSION ]; then
        sed -i "" "${OLD_VERSION_LINE}s/$OLD_VERSION/$NEW_VERSION/" "$INFO_PLIST"
        echo "\033[31mOld version $OLD_VERSION\nReplace to $NEW_VERSION\033[0m"
    fi
fi

#替换Build
OLD_BUILD=$(cat "$INFO_PLIST" | egrep -A1 -a "CFBundleShortVersionString" | egrep "<string>.[^<]*" -o | cut -b 9-)
OLD_BUILD_LINE=$(cat "$INFO_PLIST" | egrep -n "CFBundleShortVersionString" | cut -d ":" -f 1)
OLD_BUILD_LINE=$[$OLD_BUILD_LINE+1]
if [ $NEW_BUILD ]; then
    if [ $OLD_BUILD != $NEW_BUILD ]; then
        sed -i "" "${OLD_BUILD_LINE}s/$OLD_BUILD/$NEW_BUILD/" "$INFO_PLIST"
        echo "\033[31mOld build $OLD_BUILD\nReplace to $NEW_BUILD\033[0m"
    fi
fi

plutil -convert binary1 "$INFO_PLIST"

#替换证书
rm -rf "$OUTPUT_PATH/Payload/$APP_NAME/_CodeSignature"
rm -rf "$OUTPUT_PATH/Payload/$APP_NAME/embedded.mobileprovision"
cp "$PROVISION" "$OUTPUT_PATH/Payload/$APP_NAME/embedded.mobileprovision"

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

if [ -f "$OUTPUT_PATH/Payload/$APP_NAME/ResourceRules.plist" ]; then
    #签名
    /usr/bin/codesign --force --sign "$CERT"                                                         \
                      --resource-rules "$OUTPUT_PATH/Payload/$APP_NAME/ResourceRules.plist"          \
                      --entitlements "$OUTPUT_PATH/$APP_NAME.xcent" "$OUTPUT_PATH/Payload/$APP_NAME" \
                      > /dev/null
else
    #签名
    /usr/bin/codesign --force --sign "$CERT"                                                         \
                      --entitlements "$OUTPUT_PATH/$APP_NAME.xcent" "$OUTPUT_PATH/Payload/$APP_NAME" \
                      > /dev/null
fi

#打包
/usr/bin/xcrun -sdk iphoneos "$SCRIPT_PATH/package.pl"                           \
               -v "$OUTPUT_PATH/Payload/$APP_NAME"                               \
               -o "$OUTPUT_IPA" --sign "$CERT"                                   \
               --embed "$OUTPUT_PATH/Payload/$APP_NAME/embedded.mobileprovision" \
               > /dev/null

#删除签名
security delete-keychain "$KEYCHAIN_NAME.keychain"

#销毁
rm -rf "$OUTPUT_PATH"
