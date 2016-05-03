#!/bin/sh

if [ $# -lt 1 ]; then
    echo "Usage:$BASH_SOURCE ipa"
    exit -1
fi

#ipa包名
IPA_NAME=$1
#p12文件
P12_NAME="app.p12"
#p12文件密码
P12_PWD="123"
#证书
PROVISION="app.mobileprovision"

#################### 运行 ####################

#初始化
SCRIPT_PATH=$(cd $(dirname $BASH_SOURCE); pwd)
cd $SCRIPT_PATH

if [ -f $IPA_NAME ]; then
    unzip -o $IPA_NAME > /dev/null
    rm -rf $IPA_NAME
fi
APP_NAME=$(ls Payload)

#导入签名
security create-keychain -p "$APP_NAME" "$APP_NAME.keychain"
security unlock-keychain -p "$APP_NAME" "$APP_NAME.keychain"
security import "$P12_NAME" -k "$APP_NAME.keychain" -P "$P12_PWD" -T /usr/bin/codesign

#初始化信息
CERT=$(security find-identity -p codesigning $APP_NAME.keychain | egrep "iPhone.*[^\"]" -o | tail -1)
PREFIX=$(echo $CERT | egrep "[(].*[^)]" -o | cut -b 2-)
BUNDLE=$(cat $PROVISION | egrep -A1 -a "application-identifier" | egrep "$PREFIX[.|-|0-9|a-z|A-Z]*" -o)
echo "\033[31m$CERT\n$BUNDLE\033[0m"

#生成xcent
echo "
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
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
" > $APP_NAME.xcent
plutil -convert binary1 $APP_NAME.xcent

#生成plist
echo "
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
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
" > ResourceRules.plist
plutil -convert binary1 ResourceRules.plist

#替换证书
rm -rf "Payload/$APP_NAME/_CodeSignature"
rm -rf "Payload/$APP_NAME/embedded.mobileprovision"
cp "$PROVISION" "Payload/$APP_NAME/embedded.mobileprovision"
cp "ResourceRules.plist" "Payload/$APP_NAME/ResourceRules.plist"

#签名
/usr/bin/codesign --force --sign "$CERT"                                   \
                  --resource-rules "Payload/$APP_NAME/ResourceRules.plist" \
                  --entitlements "$APP_NAME.xcent" "Payload/$APP_NAME"     \
                  > /dev/null

#打包
/usr/bin/xcrun -sdk iphoneos PackageApplication                     \
               -v "Payload/$APP_NAME"                               \
               -o "$SCRIPT_PATH/$IPA_NAME"                          \
               --sign "$CERT"                                       \
               --embed "Payload/$APP_NAME/embedded.mobileprovision" \
               > /dev/null

#删除签名
security delete-keychain "$APP_NAME.keychain"

#销毁
rm -rf "$APP_NAME.xcent"
rm -rf "ResourceRules.plist"
rm -rf "Payload"
