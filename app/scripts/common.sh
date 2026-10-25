# Shared settings for the build scripts. Source this file.
HOST=jacky@100.80.92.2
KEY="$HOME/.ssh/raft_macbook_ed25519"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=25 -o ServerAliveInterval=30 -i "$KEY" -o IdentitiesOnly=yes)
rssh() { ssh "${SSH_OPTS[@]}" "$HOST" "$@"; }
RSYNC_SSH="ssh -o BatchMode=yes -o ConnectTimeout=25 -i $KEY -o IdentitiesOnly=yes"
IOS_BUNDLE=com.jackyzhong.eczematwin2
WATCH_BUNDLE=com.jackyzhong.eczematwin2.watchkitapp
IPHONE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus
WATCH_TYPE=com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm
IOS_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0
WATCH_RUNTIME=com.apple.CoreSimulator.SimRuntime.watchOS-27-0
